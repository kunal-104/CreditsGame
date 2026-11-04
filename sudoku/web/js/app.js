import * as E from './engine.js';
import { Board } from './board.js';

// ---------------------------------------------------------------- storage
const store = {
  get(k, d) {
    try { const v = localStorage.getItem('ss.' + k); return v == null ? d : JSON.parse(v); } catch { return d; }
  },
  set(k, v) {
    try { localStorage.setItem('ss.' + k, JSON.stringify(v)); } catch { /* storage unavailable */ }
  },
};

const DEFAULT_SETTINGS = {
  theme: 'auto', highlightPeers: true, highlightSame: true, showMistakes: true, autoRemoveNotes: true, timer: true,
};
const settings = { ...DEFAULT_SETTINGS, ...store.get('settings', {}) };
const saveSettings = () => store.set('settings', settings);

let BANK = null, LESSONS = null;
const view = document.getElementById('view');
const modal = document.getElementById('modal');
const toastEl = document.getElementById('toast');
const backBtn = document.getElementById('backBtn');

const fmtTime = (s) => {
  s = Math.floor(s);
  const h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60), x = s % 60;
  return (h ? h + ':' + String(m).padStart(2, '0') : m) + ':' + String(x).padStart(2, '0');
};
const esc = (s) => String(s).replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
const todayKey = () => new Date().toISOString().slice(0, 10);
const LEVEL_DESC = {
  1: 'Singles only, great for learning',
  2: 'Row and column scanning',
  3: 'Pointing and claiming',
  4: 'Pairs and triples',
  5: 'X-Wings and XY-Wings',
  6: 'Colouring, Swordfish, UR',
  7: 'XY-Chains, the hardest level',
};

let toastTimer;
function toast(msg) {
  toastEl.textContent = msg;
  toastEl.hidden = false;
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => (toastEl.hidden = true), 2600);
}

function applyTheme() {
  if (settings.theme === 'auto') delete document.documentElement.dataset.theme;
  else document.documentElement.dataset.theme = settings.theme;
}
applyTheme();
document.getElementById('themeBtn').onclick = () => {
  const dark = settings.theme === 'dark' || (settings.theme === 'auto' && matchMedia('(prefers-color-scheme: dark)').matches);
  settings.theme = dark ? 'light' : 'dark';
  saveSettings(); applyTheme();
};
backBtn.onclick = () => (history.length > 1 ? history.back() : (location.hash = '#/'));

function showModal(html, onMount) {
  modal.innerHTML = `<div class="card">${html}</div>`;
  modal.hidden = false;
  modal.onclick = (e) => { if (e.target === modal) closeModal(); };
  onMount && onMount(modal);
}
function closeModal() { modal.hidden = true; modal.innerHTML = ''; }

// ---------------------------------------------------------------- stats & progress
function getStats() { return store.get('stats', {}); }
function recordWin(level, time, hints, mistakes) {
  const st = getStats();
  const s = st[level] || { played: 0, won: 0, best: null, total: 0, noHint: 0 };
  s.won++;
  s.total += time;
  if (!hints && !mistakes) s.noHint++;
  const isBest = s.best == null || time < s.best;
  if (isBest) s.best = time;
  st[level] = s;
  store.set('stats', st);
  return isBest;
}
function recordStart(level) {
  const st = getStats();
  const s = st[level] || { played: 0, won: 0, best: null, total: 0, noHint: 0 };
  s.played++;
  st[level] = s;
  store.set('stats', st);
}
const getProgress = () => store.get('academy', {});
function markLesson(id) { const p = getProgress(); p[id] = true; store.set('academy', p); }

function dailyInfo() {
  const d = store.get('daily', { done: {}, streak: 0, last: null });
  return d;
}
function markDaily(time) {
  const d = dailyInfo();
  const key = todayKey();
  if (d.done[key]) return;
  d.done[key] = time;
  const y = new Date(Date.now() - 86400000).toISOString().slice(0, 10);
  d.streak = d.last === y ? d.streak + 1 : 1;
  d.last = key;
  store.set('daily', d);
}

// ---------------------------------------------------------------- puzzles
function hashStr(s) { let h = 2166136261; for (const c of s) h = Math.imul(h ^ c.charCodeAt(0), 16777619); return h >>> 0; }
function pickPuzzle(level, rng) {
  const list = BANK.levels[level];
  const [p, s] = list[Math.floor(rng() * list.length)];
  return { ...E.transform(p, s, rng), level };
}
function dailyPuzzle() {
  const key = todayKey();
  const rng = E.mulberry32(hashStr('daily' + key));
  const dow = new Date(key + 'T12:00:00Z').getUTCDay(); // 0 = Sunday
  const level = [6, 2, 3, 3, 4, 4, 5][dow];
  return pickPuzzle(level, rng);
}
function practicePuzzle(tech) {
  const lvl = E.TECHNIQUES[tech].level;
  const list = BANK.practice[tech] || [];
  const rng = E.mulberry32((Math.random() * 2 ** 32) >>> 0);
  let entry;
  if (list.length) {
    const ref = list[Math.floor(rng() * list.length)];
    entry = typeof ref === 'number' ? BANK.levels[lvl][ref] : ref;
  } else {
    entry = BANK.levels[lvl][Math.floor(rng() * BANK.levels[lvl].length)];
  }
  return { ...E.transform(entry[0], entry[1], rng), level: lvl };
}

// ---------------------------------------------------------------- game state
let game = store.get('game', null);
function newGame(p, mode = 'classic', extra = {}) {
  const grid = E.parse(p.puzzle);
  game = {
    puzzle: p.puzzle, solution: p.solution, level: p.level, mode, ...extra,
    grid, given: grid.map(Boolean), notes: new Array(81).fill(0),
    time: 0, mistakes: 0, hints: 0, done: false, started: Date.now(),
  };
  history_ = [];
  recordStart(p.level);
  saveGame();
  location.hash = '#/play';
}
let history_ = [];
const saveGame = () => store.set('game', game);

// ---------------------------------------------------------------- router
const routes = {
  '': renderHome,
  play: renderGame,
  new: renderNew,
  academy: renderAcademy,
  lesson: renderLesson,
  stats: renderStats,
  settings: renderSettings,
};
let cleanup = null;
function route() {
  if (cleanup) { cleanup(); cleanup = null; }
  closeModal();
  const [name, arg] = location.hash.replace(/^#\/?/, '').split('/');
  const fn = routes[name] || renderHome;
  backBtn.hidden = !name;
  view.className = '';
  window.scrollTo(0, 0);
  fn(arg);
  view.focus({ preventScroll: true });
}
window.addEventListener('hashchange', route);

// ---------------------------------------------------------------- home
function renderHome() {
  const daily = dailyInfo();
  const dp = dailyPuzzle();
  const doneToday = daily.done[todayKey()];
  const prog = getProgress();
  const total = LESSONS.lessons.length;
  const done = LESSONS.lessons.filter((l) => prog[l.id]).length;
  const st = getStats();
  const won = Object.values(st).reduce((a, s) => a + s.won, 0);
  const resume = game && !game.done;
  view.innerHTML = `
    <section class="hero">
      <h1>Learn it. Master it.</h1>
      <p class="muted">Every puzzle can be solved by logic, and every hint teaches you the technique behind it.</p>
    </section>
    ${resume ? `
    <div class="card row">
      <div class="grow"><b>Continue game</b><div class="muted small">${E.LEVELS[game.level].name} · ${fmtTime(game.time)}</div></div>
      <a class="btn primary" href="#/play">Resume</a>
    </div>` : ''}
    <div class="card daily">
      <div class="row">
        <div class="grow">
          <b>Daily Challenge</b>
          <div class="muted small">${new Date().toLocaleDateString(undefined, { weekday: 'long', month: 'short', day: 'numeric' })} · ${E.LEVELS[dp.level].name}</div>
          <div class="small">🔥 ${daily.streak || 0} day streak</div>
        </div>
        <button class="btn" id="dailyBtn">${doneToday ? 'Done ✓' : 'Play'}</button>
      </div>
    </div>
    <div class="card">
      <div class="row" style="margin-bottom:8px"><b class="grow">Sudoku Academy</b><span class="muted small">${done}/${total} lessons</span></div>
      <div class="progress"><div style="width:${(done / total) * 100}%"></div></div>
      <p class="muted small" style="margin:10px 0 12px">${total} lessons, from your first digit to XY-Chains. Each one has real examples to try and practice puzzles.</p>
      <a class="btn primary block" href="#/academy">${done ? 'Continue learning' : 'Start learning'}</a>
    </div>
    <div class="card">
      <b>New game</b>
      <div class="levels" style="margin-top:10px">
        ${E.LEVELS.slice(1).map((l) => `
          <button class="level-btn" data-level="${l.id}">
            <b><span class="dot" style="background:${l.color}"></span>${l.name}</b>
            <span class="muted small">${LEVEL_DESC[l.id]}</span>
          </button>`).join('')}
      </div>
    </div>
    <div class="nav">
      <a href="#/academy"><span>🎓</span>Academy</a>
      <a href="#/stats"><span>📊</span>Stats · ${won}</a>
      <a href="#/settings"><span>⚙️</span>Settings</a>
    </div>`;
  view.querySelectorAll('.level-btn').forEach((b) => (b.onclick = () => startLevel(+b.dataset.level)));
  view.querySelector('#dailyBtn').onclick = () => {
    if (doneToday) return toast(`Solved today in ${fmtTime(doneToday)}. Come back tomorrow!`);
    newGame(dp, 'daily', { day: todayKey() });
  };
}

function startLevel(level) {
  if (game && !game.done && game.grid.some((v, i) => v && !game.given[i])) {
    showModal(`<h3>Start a new game?</h3><p class="muted">Your current game will be lost.</p>
      <div class="row"><button class="btn grow" id="no">Cancel</button><button class="btn primary grow" id="yes">New game</button></div>`, (m) => {
      m.querySelector('#no').onclick = closeModal;
      m.querySelector('#yes').onclick = () => { closeModal(); newGame(pickPuzzle(level, Math.random)); };
    });
  } else newGame(pickPuzzle(level, Math.random));
}

function renderNew(level) { startLevel(+level || 1); }

// ---------------------------------------------------------------- game
function renderGame() {
  if (!game) { location.hash = '#/'; return; }
  view.className = 'game';
  const lvl = E.LEVELS[game.level];
  view.innerHTML = `
    <div class="game-layout">
      <div>
        <div class="game-head">
          <span class="chip" style="background:${lvl.color}">${game.mode === 'daily' ? 'Daily · ' : game.mode === 'practice' ? 'Practice · ' : ''}${lvl.name}</span>
          <div class="stat-inline">
            <span title="Mistakes">✗ <b id="mist">${game.mistakes}</b></span>
            <span title="Hints">💡 <b id="hintsN">${game.hints}</b></span>
            <span id="timer" ${settings.timer ? '' : 'hidden'}>${fmtTime(game.time)}</span>
            <button class="icon-btn" id="pauseBtn" aria-label="Pause" style="width:28px;height:28px">
              <svg viewBox="0 0 24 24"><path d="M9 5v14M15 5v14"/></svg>
            </button>
          </div>
        </div>
        <div id="board"></div>
      </div>
      <div>
        <div class="tools">
          <button class="tool" id="undoBtn"><svg viewBox="0 0 24 24"><path d="M9 14L4 9l5-5"/><path d="M4 9h11a5 5 0 0 1 0 10h-3"/></svg>Undo</button>
          <button class="tool" id="eraseBtn"><svg viewBox="0 0 24 24"><path d="M20 20H8l-5-5 10-10 8 8-7 7"/></svg>Erase</button>
          <button class="tool" id="notesBtn"><svg viewBox="0 0 24 24"><path d="M12 20h9"/><path d="M16.5 3.5a2.1 2.1 0 0 1 3 3L7 19l-4 1 1-4z"/></svg>Notes<span class="badge" id="notesBadge" hidden>ON</span></button>
          <button class="tool" id="autoBtn"><svg viewBox="0 0 24 24"><rect x="3" y="3" width="18" height="18" rx="2"/><path d="M8 8h.01M12 8h.01M16 8h.01M8 12h.01M12 12h.01M8 16h.01"/></svg>Auto notes</button>
          <button class="tool" id="hintBtn"><svg viewBox="0 0 24 24"><path d="M9 18h6M10 22h4"/><path d="M12 2a7 7 0 0 0-4 12.7V17h8v-2.3A7 7 0 0 0 12 2z"/></svg>Hint</button>
        </div>
        <div class="pad" id="pad">
          ${[1, 2, 3, 4, 5, 6, 7, 8, 9].map((d) => `<button class="num" data-d="${d}">${d}<small></small></button>`).join('')}
        </div>
        <div id="hintPanel"></div>
      </div>
    </div>`;

  let selected = game.grid.findIndex((v) => !v);
  let notesMode = false;
  let hintState = null; // {data, i, reveal}
  let flash = null;
  const board = new Board(view.querySelector('#board'), { onSelect: (i) => { selected = i; if (hintState) closeHint(); draw(); } });
  const pad = view.querySelector('#pad');
  const hintPanel = view.querySelector('#hintPanel');

  function draw() {
    let overlay = null;
    if (hintState && hintState.data.kind === 'steps') {
      const { step, state } = hintState.data.steps[hintState.i];
      overlay = { cand: state.cand, units: step.units, cells: step.cells, marks: step.marks, places: step.places, elims: step.elims, reveal: hintState.reveal };
    }
    board.render({
      grid: game.grid, given: game.given, notes: game.notes, selected: hintState ? -1 : selected,
      solution: game.solution.split('').map(Number), showMistakes: settings.showMistakes,
      highlightPeers: settings.highlightPeers, highlightSame: settings.highlightSame, overlay,
      flash: hintState && hintState.data.kind === 'mistake' ? new Set(hintState.data.cells) : flash,
    });
    const counts = new Array(10).fill(0);
    game.grid.forEach((v, i) => { if (v && v === +game.solution[i]) counts[v]++; });
    pad.querySelectorAll('.num').forEach((b) => {
      const d = +b.dataset.d;
      b.disabled = counts[d] >= 9 || game.done;
      b.querySelector('small').textContent = 9 - counts[d] || '';
      b.classList.toggle('notesmode', notesMode);
    });
    view.querySelector('#notesBtn').classList.toggle('on', notesMode);
    view.querySelector('#notesBadge').hidden = !notesMode;
    view.querySelector('#mist').textContent = game.mistakes;
    view.querySelector('#hintsN').textContent = game.hints;
    flash = null;
  }

  function snapshot() {
    history_.push({ grid: game.grid.slice(), notes: game.notes.slice() });
    if (history_.length > 300) history_.shift();
  }

  function input(d) {
    if (game.done || selected < 0 || game.given[selected]) return;
    if (hintState) closeHint();
    if (notesMode) {
      if (game.grid[selected]) return;
      snapshot();
      game.notes[selected] ^= 1 << d;
    } else {
      if (game.grid[selected] === d) return;
      snapshot();
      game.grid[selected] = d;
      game.notes[selected] = 0;
      if (d !== +game.solution[selected]) {
        game.mistakes++;
        if (navigator.vibrate) navigator.vibrate(60);
      } else if (settings.autoRemoveNotes) {
        for (const p of E.PEERS[selected]) game.notes[p] &= ~(1 << d);
      }
    }
    saveGame();
    draw();
    checkWin();
  }

  function erase() {
    if (game.done || selected < 0 || game.given[selected]) return;
    if (!game.grid[selected] && !game.notes[selected]) return;
    snapshot();
    game.grid[selected] = 0;
    game.notes[selected] = 0;
    saveGame(); draw();
  }

  function undo() {
    if (hintState) closeHint();
    const h = history_.pop();
    if (!h) return toast('Nothing to undo');
    game.grid = h.grid; game.notes = h.notes;
    saveGame(); draw();
  }

  function autoNotes() {
    if (game.done) return;
    snapshot();
    const s = E.makeState(game.grid);
    for (let i = 0; i < 81; i++) game.notes[i] = game.grid[i] ? 0 : s.cand[i];
    saveGame(); draw();
    toast('All candidates filled in');
  }

  function checkWin() {
    if (game.grid.join('') !== game.solution) return;
    game.done = true;
    saveGame();
    const best = recordWin(game.level, game.time, game.hints, game.mistakes);
    if (game.mode === 'daily') markDaily(game.time);
    if (game.mode === 'practice' && game.lesson) markLesson(game.lesson);
    const perfect = !game.hints && !game.mistakes;
    setTimeout(() => showModal(`
      <div class="big">${perfect ? '🏆' : '🎉'}</div>
      <h2>${perfect ? 'Flawless!' : 'Solved!'}</h2>
      <p class="muted">${E.LEVELS[game.level].name} · ${fmtTime(game.time)}${best ? ' · <b>New best!</b>' : ''}<br>
      ${game.mistakes} mistakes · ${game.hints} hints</p>
      <div class="row"><a class="btn grow" href="#/">Home</a>
      <button class="btn primary grow" id="again">Next puzzle</button></div>`, (m) => {
      m.querySelector('#again').onclick = () => { closeModal(); newGame(pickPuzzle(game.level, Math.random)); route(); };
    }), 350);
    draw();
  }

  // ----- hints
  function openHint() {
    if (game.done) return;
    const data = E.hint(game.grid, game.solution.split('').map(Number));
    if (data.kind === 'solved') return;
    if (data.kind === 'stuck') return toast('No logical step found');
    hintState = { data, i: 0, reveal: false };
    if (data.kind === 'steps') { game.hints++; saveGame(); }
    renderHint();
    draw();
  }
  function closeHint() { hintState = null; hintPanel.innerHTML = ''; draw(); }
  function renderHint() {
    const { data } = hintState;
    if (data.kind === 'mistake') {
      hintPanel.innerHTML = `<div class="sheet">
        <h3>Check these cells</h3>
        <p>${data.cells.length === 1 ? 'One of your digits is' : data.cells.length + ' of your digits are'} wrong (${data.cells.map(E.cellName).join(', ')}). Fix ${data.cells.length === 1 ? 'it' : 'them'} before continuing.</p>
        <div class="row"><button class="btn grow" id="hClose">Close</button><button class="btn primary grow" id="hFix">Remove ${data.cells.length === 1 ? 'it' : 'them'}</button></div></div>`;
      hintPanel.querySelector('#hClose').onclick = closeHint;
      hintPanel.querySelector('#hFix').onclick = () => {
        snapshot();
        for (const c of data.cells) game.grid[c] = 0;
        saveGame(); closeHint();
      };
      return;
    }
    const total = data.steps.length;
    const { step } = data.steps[hintState.i];
    const t = E.TECHNIQUES[step.tech];
    const lesson = LESSONS.lessons.find((l) => l.tech === step.tech);
    const last = hintState.i === total - 1;
    let html = `<div class="sheet"><h3><span class="tech">${esc(t.name)}</span>${total > 1 ? `<span class="muted small">Step ${hintState.i + 1} of ${total}</span>` : ''}</h3>`;
    if (!hintState.reveal) {
      html += `<p>There's a <b>${esc(t.name)}</b> in the highlighted area. Can you spot it?</p>
        <div class="row"><button class="btn grow" id="hClose">I'll find it</button><button class="btn primary grow" id="hReveal">Show me</button></div>`;
    } else {
      html += `<p>${esc(step.text)}</p>
        <div class="legend"><span><i style="background:var(--key)"></i>key</span><span><i style="background:var(--alt)"></i>linked</span><span><i style="background:var(--elim)"></i>remove</span><span><i style="background:var(--place)"></i>solve</span></div>
        <div class="row">
          ${hintState.i > 0 ? '<button class="btn" id="hPrev">Back</button>' : ''}
          ${last ? '<button class="btn primary grow" id="hApply">Apply</button>' : '<button class="btn primary grow" id="hNext">Next step</button>'}
        </div>
        ${lesson ? `<p class="small" style="margin:10px 0 0"><a href="#/lesson/${lesson.id}">Learn ${esc(t.name)} in the Academy →</a></p>` : ''}`;
    }
    html += '</div>';
    hintPanel.innerHTML = html;
    const $ = (s) => hintPanel.querySelector(s);
    $('#hClose') && ($('#hClose').onclick = closeHint);
    $('#hReveal') && ($('#hReveal').onclick = () => { hintState.reveal = true; renderHint(); draw(); });
    $('#hPrev') && ($('#hPrev').onclick = () => { hintState.i--; renderHint(); draw(); });
    $('#hNext') && ($('#hNext').onclick = () => { hintState.i++; renderHint(); draw(); });
    $('#hApply') && ($('#hApply').onclick = applyHint);
  }
  function applyHint() {
    snapshot();
    const notesInUse = game.notes.some(Boolean);
    for (const { step } of hintState.data.steps) {
      if (notesInUse) for (const [c, d] of step.elims) game.notes[c] &= ~(1 << d);
      for (const [c, d] of step.places) {
        game.grid[c] = d; game.notes[c] = 0;
        if (settings.autoRemoveNotes) for (const p of E.PEERS[c]) game.notes[p] &= ~(1 << d);
        selected = c;
        flash = new Set([c]);
      }
    }
    hintState = null; hintPanel.innerHTML = '';
    saveGame(); draw(); checkWin();
  }

  // ----- pause
  let paused = false;
  function setPaused(p) {
    paused = p;
    if (p) {
      showModal(`<div class="big">⏸</div><h2>Paused</h2><p class="muted">${fmtTime(game.time)}</p><button class="btn primary block" id="resume">Resume</button>`, (m) => {
        m.querySelector('#resume').onclick = () => { closeModal(); paused = false; };
        modal.onclick = null;
      });
    }
  }
  view.querySelector('#pauseBtn').onclick = () => setPaused(true);

  // ----- wiring
  pad.addEventListener('click', (e) => { const b = e.target.closest('.num'); if (b) input(+b.dataset.d); });
  view.querySelector('#eraseBtn').onclick = erase;
  view.querySelector('#undoBtn').onclick = undo;
  view.querySelector('#notesBtn').onclick = () => { notesMode = !notesMode; draw(); };
  view.querySelector('#autoBtn').onclick = autoNotes;
  view.querySelector('#hintBtn').onclick = () => (hintState ? closeHint() : openHint());

  const onKey = (e) => {
    if (!modal.hidden) return;
    if (e.key >= '1' && e.key <= '9') { input(+e.key); e.preventDefault(); return; }
    const mv = { ArrowUp: -9, ArrowDown: 9, ArrowLeft: -1, ArrowRight: 1 }[e.key];
    if (mv) {
      if (selected < 0) selected = 0;
      const r = E.rowOf(selected), c = E.colOf(selected);
      const nr = (r + (mv === -9 ? -1 : mv === 9 ? 1 : 0) + 9) % 9, nc = (c + (mv === -1 ? -1 : mv === 1 ? 1 : 0) + 9) % 9;
      selected = nr * 9 + nc; draw(); e.preventDefault(); return;
    }
    if (e.key === 'Backspace' || e.key === 'Delete' || e.key === '0') { erase(); e.preventDefault(); }
    else if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === 'z') { undo(); e.preventDefault(); }
    else if (e.key.toLowerCase() === 'n') { notesMode = !notesMode; draw(); }
    else if (e.key.toLowerCase() === 'h') { hintState ? closeHint() : openHint(); }
    else if (e.key === 'Escape' && hintState) closeHint();
  };
  document.addEventListener('keydown', onKey);
  const timerEl = view.querySelector('#timer');
  const tick = setInterval(() => {
    if (game.done || paused || document.hidden || !modal.hidden) return;
    game.time++;
    timerEl.textContent = fmtTime(game.time);
    if (game.time % 5 === 0) saveGame();
  }, 1000);
  cleanup = () => { clearInterval(tick); document.removeEventListener('keydown', onKey); saveGame(); };
  draw();
}

// ---------------------------------------------------------------- academy
function renderAcademy() {
  view.className = 'wide';
  const prog = getProgress();
  let n = 0;
  view.innerHTML = `<h1>Sudoku Academy</h1>
    <p class="muted">Seven stages from complete beginner to grandmaster. Each lesson explains one technique, lets you find it in a real puzzle, and gives you practice puzzles that need it.</p>
    ${LESSONS.stages.map((st) => `
      <div class="stage"><span class="chip" style="background:${E.LEVELS[st.level].color}">${st.level}</span><h2>${esc(st.name)}</h2></div>
      <p class="muted small" style="margin:0 0 10px">${esc(st.tagline)}</p>
      ${LESSONS.lessons.filter((l) => l.level === st.level).map((l) => `
        <a class="lesson-link ${prog[l.id] ? 'done' : ''}" href="#/lesson/${l.id}">
          <span class="n">${prog[l.id] ? '✓' : ++n && n}</span>
          <div class="grow"><b>${esc(l.title)}</b><p>${esc(l.summary)}</p></div>
        </a>`).join('')}`).join('')}`;
  // keep numbering consistent for completed lessons too
  let k = 0;
  view.querySelectorAll('.lesson-link .n').forEach((el) => { k++; if (el.textContent !== '✓') el.textContent = k; });
}

function renderLesson(id) {
  const lessons = LESSONS.lessons;
  const idx = lessons.findIndex((l) => l.id === id);
  if (idx < 0) { location.hash = '#/academy'; return; }
  const L = lessons[idx];
  const next = lessons[idx + 1];
  const examples = L.tech ? BANK.examples[L.tech] || [] : [];
  view.className = 'wide';
  view.innerHTML = `
    <p class="muted small" style="margin:0">Stage ${L.level} · ${E.LEVELS[L.level].name}</p>
    <h1>${esc(L.title)}</h1>
    <div class="card lesson-body">
      ${L.body.map((p) => `<p>${esc(p)}</p>`).join('')}
      <div class="key-idea">${esc(L.keyIdea)}</div>
      <p class="tip">💡 ${esc(L.tip)}</p>
    </div>
    ${examples.length ? `
      <div class="card">
        <div class="row"><h3 class="grow" style="margin:0">Try it</h3><span class="muted small" id="exN"></span></div>
        <p id="task" style="margin:6px 0 10px"></p>
        <div id="exBoard"></div>
        <div class="feedback" id="fb"></div>
        <div id="explain"></div>
        <div class="row" style="flex-wrap:wrap">
          <button class="btn" id="showBtn">Show me</button>
          <button class="btn" id="nextEx">Another example</button>
          <span class="grow"></span>
          <button class="btn primary" id="practiceBtn">Practice puzzle</button>
        </div>
      </div>` : `
      <div class="card"><button class="btn primary block" id="doneBtn">Mark as complete</button></div>`}
    <div class="row" style="margin-top:12px">
      ${idx > 0 ? `<a class="btn" href="#/lesson/${lessons[idx - 1].id}">← ${esc(lessons[idx - 1].title)}</a>` : ''}
      <span class="grow"></span>
      ${next ? `<a class="btn" href="#/lesson/${next.id}">${esc(next.title)} →</a>` : '<a class="btn" href="#/academy">Academy</a>'}
    </div>`;

  const doneBtn = view.querySelector('#doneBtn');
  if (doneBtn) doneBtn.onclick = () => { markLesson(L.id); toast('Lesson complete ✓'); if (next) location.hash = '#/lesson/' + next.id; };
  if (!examples.length) return;

  let ex = 0, solved = false, wrongTries = 0;
  const fb = view.querySelector('#fb');
  const explain = view.querySelector('#explain');
  const showCands = E.TECHNIQUES[L.tech].level >= 3;
  let sel = -1;
  const board = new Board(view.querySelector('#exBoard'), { onSelect: (i) => tap(i) });

  function targets() {
    const s = examples[ex].step;
    return new Set(s.places.length ? s.places.map((p) => p[0]) : s.elims.map((e) => e[0]));
  }
  function draw() {
    const e = examples[ex];
    const grid = E.parse(e.grid);
    const s = e.step;
    board.render({
      grid, given: grid.map(Boolean), notes: showCands ? e.cand : new Array(81).fill(0), selected: sel,
      highlightPeers: false, highlightSame: false,
      overlay: {
        cand: showCands || solved ? e.cand.map((m, i) => (showCands || (solved && s.cells.includes(i)) ? m : 0)) : new Array(81).fill(0),
        units: s.units, cells: s.cells, marks: s.marks, places: s.places, elims: s.elims, reveal: solved,
      },
    });
  }
  function load() {
    solved = false; wrongTries = 0; sel = -1;
    fb.textContent = ''; fb.className = 'feedback'; explain.innerHTML = '';
    view.querySelector('#exN').textContent = `Example ${ex + 1} of ${examples.length}`;
    view.querySelector('#task').textContent = L.task || 'Find the move.';
    draw();
  }
  function reveal(ok) {
    solved = true;
    fb.className = 'feedback ' + (ok ? 'ok' : '');
    fb.textContent = ok ? 'Correct! 🎉' : '';
    explain.innerHTML = `<p>${esc(examples[ex].step.text)}</p>`;
    if (ok) markLesson(L.id);
    draw();
  }
  function tap(i) {
    if (solved) return;
    sel = i;
    if (targets().has(i)) reveal(true);
    else {
      wrongTries++;
      fb.className = 'feedback bad';
      fb.textContent = wrongTries >= 2 ? 'Not this one. Tap "Show me" if you need help.' : 'Not quite. Look at the highlighted area again.';
      const b = view.querySelector('#exBoard');
      b.classList.remove('shake'); void b.offsetWidth; b.classList.add('shake');
      draw();
    }
  }
  view.querySelector('#showBtn').onclick = () => reveal(false);
  view.querySelector('#nextEx').onclick = () => { ex = (ex + 1) % examples.length; load(); };
  view.querySelector('#practiceBtn').onclick = () => newGame(practicePuzzle(L.tech), 'practice', { lesson: L.id });
  load();
}

// ---------------------------------------------------------------- stats
function renderStats() {
  const st = getStats();
  const d = dailyInfo();
  const rows = E.LEVELS.slice(1).map((l) => {
    const s = st[l.id] || { played: 0, won: 0, best: null, total: 0, noHint: 0 };
    return `<tr><td><span class="dot" style="display:inline-block;width:9px;height:9px;border-radius:50%;background:${l.color};margin-right:6px"></span>${l.name}</td>
      <td>${s.won}/${s.played}</td><td>${s.best != null ? fmtTime(s.best) : '–'}</td><td>${s.won ? fmtTime(s.total / s.won) : '–'}</td><td>${s.noHint || 0}</td></tr>`;
  }).join('');
  const prog = getProgress();
  const learned = LESSONS.lessons.filter((l) => prog[l.id]).length;
  const won = Object.values(st).reduce((a, s) => a + s.won, 0);
  view.innerHTML = `<h1>Statistics</h1>
    <div class="tiles" style="margin-bottom:12px">
      <div class="tile"><b>${won}</b><span class="muted small">solved</span></div>
      <div class="tile"><b>🔥 ${d.streak || 0}</b><span class="muted small">daily streak</span></div>
      <div class="tile"><b>${learned}/${LESSONS.lessons.length}</b><span class="muted small">lessons</span></div>
    </div>
    <div class="card"><table>
      <thead><tr><th>Level</th><th>Won</th><th>Best</th><th>Avg</th><th>Flawless</th></tr></thead>
      <tbody>${rows}</tbody></table></div>`;
}

// ---------------------------------------------------------------- settings
function renderSettings() {
  const opts = [
    ['highlightPeers', 'Highlight row, column and box', 'Shade the cells that share a unit with the selected cell'],
    ['highlightSame', 'Highlight matching digits', 'Show every copy of the selected digit, including in notes'],
    ['showMistakes', 'Show mistakes immediately', 'Mark wrong digits in red as soon as you enter them'],
    ['autoRemoveNotes', 'Auto-remove notes', 'Placing a digit removes it from notes in the same row, column and box'],
    ['timer', 'Show timer', 'The timer still runs when hidden'],
  ];
  view.innerHTML = `<h1>Settings</h1>
    <div class="card">
      ${opts.map(([k, t, d]) => `<label class="switch"><span><b>${t}</b><br><span class="muted small">${d}</span></span><input type="checkbox" data-k="${k}" ${settings[k] ? 'checked' : ''}></label>`).join('')}
      <label class="switch"><span><b>Theme</b></span>
        <select id="theme" class="btn"><option value="auto">System</option><option value="light">Light</option><option value="dark">Dark</option></select></label>
    </div>
    <div class="card">
      <b>Keyboard shortcuts</b>
      <p class="muted small" style="margin:6px 0 0">1–9 enter digit · Arrows move · N notes · H hint · Backspace erase · Ctrl+Z undo</p>
    </div>
    <div class="card"><button class="btn block" id="reset">Reset all progress</button></div>`;
  view.querySelectorAll('input[data-k]').forEach((i) => (i.onchange = () => { settings[i.dataset.k] = i.checked; saveSettings(); }));
  const th = view.querySelector('#theme');
  th.value = settings.theme;
  th.onchange = () => { settings.theme = th.value; saveSettings(); applyTheme(); };
  view.querySelector('#reset').onclick = () => showModal(`<h3>Reset everything?</h3><p class="muted">Statistics, lessons, streak and your current game will be deleted.</p>
    <div class="row"><button class="btn grow" id="no">Cancel</button><button class="btn primary grow" id="yes">Reset</button></div>`, (m) => {
    m.querySelector('#no').onclick = closeModal;
    m.querySelector('#yes').onclick = () => {
      for (const k of ['stats', 'academy', 'daily', 'game']) store.set(k, null);
      game = null; closeModal(); toast('Progress reset'); location.hash = '#/';
    };
  });
}

// ---------------------------------------------------------------- boot
async function boot() {
  view.innerHTML = '<p class="muted" style="text-align:center;margin-top:30vh">Loading…</p>';
  try {
    const [b, l] = await Promise.all([fetch('data/bank.json').then((r) => r.json()), fetch('data/lessons.json').then((r) => r.json())]);
    BANK = b; LESSONS = l;
  } catch (e) {
    view.innerHTML = '<div class="card"><b>Could not load puzzles.</b><p class="muted">Serve this folder over HTTP (for example <code>npx serve sudoku/web</code>) instead of opening the file directly.</p></div>';
    return;
  }
  route();
  if ('serviceWorker' in navigator && location.protocol !== 'file:') navigator.serviceWorker.register('sw.js').catch(() => {});
}
boot();
