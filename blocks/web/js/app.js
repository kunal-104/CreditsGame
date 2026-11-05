import { Game, SHAPE, N, PRAISE } from './logic.js';

// ---------------------------------------------------------------- storage
const store = {
  get(k, d) { try { const v = localStorage.getItem('blockora.' + k); return v == null ? d : JSON.parse(v); } catch { return d; } },
  set(k, v) { try { localStorage.setItem('blockora.' + k, JSON.stringify(v)); } catch { /* unavailable */ } },
};
const settings = Object.assign({ theme: 'aurora', sound: true, haptics: true, seenHowTo: false }, store.get('settings', {}));
const stats = Object.assign({ games: 0, best: 0, total: 0, lines: 0, bestCombo: 0, maxLines: 0, daily: {}, dailyStreak: 0, lastDaily: null }, store.get('stats', {}));
let achievements = store.get('achievements', {});
const saveSettings = () => store.set('settings', settings);
const saveStats = () => store.set('stats', stats);

const view = document.getElementById('view');
const modal = document.getElementById('modal');
const toastEl = document.getElementById('toast');

const todayKey = (d = new Date()) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
function hashStr(s) { let h = 2166136261; for (const c of s) h = Math.imul(h ^ c.charCodeAt(0), 16777619); return h >>> 0; }

const THEMES = {
  aurora: ['#1b1640', '#9775fa'], daylight: ['#e9f1ff', '#5b5bf7'], ocean: ['#062a3a', '#3ee6c1'], candy: ['#ffe3f1', '#ff4d9d'],
};
function applyTheme() {
  document.documentElement.dataset.theme = settings.theme;
  document.querySelector('meta[name=theme-color]').setAttribute('content', THEMES[settings.theme][0]);
}
applyTheme();

let toastTimer;
function toast(msg) { toastEl.textContent = msg; toastEl.hidden = false; clearTimeout(toastTimer); toastTimer = setTimeout(() => (toastEl.hidden = true), 2200); }
function showModal(html, mount, dismissable = true) {
  modal.innerHTML = `<div class="card">${html}</div>`;
  modal.hidden = false;
  modal.onclick = dismissable ? (e) => { if (e.target === modal) closeModal(); } : null;
  mount && mount(modal);
}
function closeModal() { modal.hidden = true; modal.innerHTML = ''; }

// ---------------------------------------------------------------- sound (synthesised, no files)
let actx = null;
function tone(freq, dur = 0.12, type = 'sine', vol = 0.15, delay = 0) {
  if (!settings.sound) return;
  try {
    actx = actx || new (window.AudioContext || window.webkitAudioContext)();
    const t = actx.currentTime + delay;
    const o = actx.createOscillator(), g = actx.createGain();
    o.type = type; o.frequency.setValueAtTime(freq, t);
    g.gain.setValueAtTime(0.0001, t);
    g.gain.exponentialRampToValueAtTime(vol, t + 0.01);
    g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
    o.connect(g).connect(actx.destination);
    o.start(t); o.stop(t + dur + 0.02);
  } catch { /* audio unavailable */ }
}
const sfx = {
  pick: () => tone(520, 0.06, 'triangle', 0.08),
  place: () => tone(300, 0.09, 'triangle', 0.14),
  bad: () => tone(140, 0.12, 'sawtooth', 0.05),
  clear: (n, combo) => { const base = 523 * Math.pow(1.06, Math.min(combo, 8)); [0, 4, 7, 12, 16].slice(0, Math.min(5, n + 2)).forEach((s, k) => tone(base * Math.pow(2, s / 12), 0.18, 'sine', 0.12, k * 0.06)); },
  over: () => [392, 330, 262, 196].forEach((f, k) => tone(f, 0.25, 'triangle', 0.12, k * 0.12)),
  best: () => [523, 659, 784, 1047, 1319].forEach((f, k) => tone(f, 0.2, 'sine', 0.12, k * 0.08)),
};
const buzz = (p) => { if (settings.haptics && navigator.vibrate) navigator.vibrate(p); };

// ---------------------------------------------------------------- confetti
function confetti(count = 120) {
  const cv = document.createElement('canvas');
  cv.className = 'confetti';
  cv.width = innerWidth * devicePixelRatio; cv.height = innerHeight * devicePixelRatio;
  document.body.appendChild(cv);
  const ctx = cv.getContext('2d');
  const cs = getComputedStyle(document.documentElement);
  const colors = [1, 2, 3, 4, 5, 6, 7].map((k) => cs.getPropertyValue('--b' + k).trim());
  const parts = Array.from({ length: count }, () => ({
    x: cv.width / 2 + (Math.random() - .5) * cv.width * .3, y: cv.height * .35,
    vx: (Math.random() - .5) * 18 * devicePixelRatio, vy: (-Math.random() * 16 - 6) * devicePixelRatio,
    s: (6 + Math.random() * 8) * devicePixelRatio, r: Math.random() * 6, vr: (Math.random() - .5) * .3, c: colors[(Math.random() * colors.length) | 0],
  }));
  let frames = 0;
  (function step() {
    ctx.clearRect(0, 0, cv.width, cv.height);
    for (const p of parts) {
      p.vy += 0.45 * devicePixelRatio; p.x += p.vx; p.y += p.vy; p.vx *= 0.99; p.r += p.vr;
      ctx.save(); ctx.translate(p.x, p.y); ctx.rotate(p.r); ctx.fillStyle = p.c; ctx.fillRect(-p.s / 2, -p.s / 2, p.s, p.s * .6); ctx.restore();
    }
    if (++frames < 150) requestAnimationFrame(step); else cv.remove();
  })();
}

// ---------------------------------------------------------------- achievements
const ACH = [
  ['first', '🧱', 'First Steps', 'Finish your first game'],
  ['clear1', '✨', 'Clean Sweep', 'Clear your first line'],
  ['multi3', '💥', 'Triple Threat', 'Clear 3 lines with one piece'],
  ['combo3', '🔥', 'On Fire', 'Reach a 3× combo'],
  ['combo6', '🌋', 'Volcanic', 'Reach a 6× combo'],
  ['s500', '🥉', 'Rising Star', 'Score 500 in one game'],
  ['s1500', '🥈', 'Block Master', 'Score 1,500 in one game'],
  ['s3000', '🥇', 'Legend', 'Score 3,000 in one game'],
  ['lines100', '📏', 'Line Collector', 'Clear 100 lines in total'],
  ['games25', '🎮', 'Regular', 'Play 25 games'],
  ['daily1', '📅', 'Daily Player', 'Finish a Daily Challenge'],
  ['daily7', '🏆', 'Weekly Warrior', 'Daily Challenge 7 days in a row'],
];
function unlock(id) {
  if (achievements[id]) return;
  achievements[id] = Date.now();
  store.set('achievements', achievements);
  const a = ACH.find((x) => x[0] === id);
  setTimeout(() => toast(`${a[1]} Achievement unlocked: ${a[2]}`), 300);
}

// ---------------------------------------------------------------- routing
let cleanup = null;
function go(screen, arg) {
  if (cleanup) { cleanup(); cleanup = null; }
  closeModal();
  view.className = screen === 'game' ? 'game' : '';
  (screen === 'game' ? renderGame : renderHome)(arg);
}

// ---------------------------------------------------------------- home
function savedGame() {
  const j = store.get('game', null);
  if (!j || j.over) return null;
  try { return Game.fromJSON(j); } catch { return null; }
}

function renderHome() {
  const g = savedGame();
  const dkey = todayKey();
  const dailyScore = stats.daily[dkey];
  const unlocked = Object.keys(achievements).length;
  const d = new Date();
  const logo = [1, 0, 2, 3, 4, 0, 5, 6, 7].map((k) => `<i style="--c:${k ? `var(--b${k})` : 'transparent'};${k ? '' : 'box-shadow:none'}"></i>`).join('');
  view.innerHTML = `
    <div class="home">
      <div class="logo"><div class="blocks">${logo}</div><h1>Blockora</h1><p>Drop. Clear. Combo.</p></div>
      <div class="stats-row">
        <div class="stat"><b>${stats.best.toLocaleString()}</b><span>Best</span></div>
        <div class="stat"><b>${stats.games}</b><span>Games</span></div>
        <div class="stat"><b>${stats.bestCombo}×</b><span>Top combo</span></div>
      </div>
      ${g ? `<button class="btn primary big block" id="resume">▶ Continue · ${g.score.toLocaleString()}</button>
             <button class="btn block" id="new">New game</button>`
          : '<button class="btn primary big block" id="new">▶ Play</button>'}
      <button class="card daily btn block" id="daily" style="text-align:left;justify-content:flex-start">
        <span class="cal"><span>${d.getDate()}<small>${d.toLocaleDateString(undefined, { month: 'short' })}</small></span></span>
        <span class="grow"><b>Daily Challenge</b><br><span class="muted small">${dailyScore != null ? `Today's best: ${dailyScore.toLocaleString()}` : 'Same pieces for everyone today'} · 🔥 ${currentDailyStreak()} day streak</span></span>
      </button>
      <div class="themes">${Object.entries(THEMES).map(([k, [a, b]]) => `<button class="theme-dot ${settings.theme === k ? 'on' : ''}" data-t="${k}" style="--a:${a};--b:${b}" aria-label="${k} theme"></button>`).join('')}</div>
      <div class="links">
        <button class="btn" id="ach">🏅 ${unlocked}/${ACH.length}</button>
        <button class="btn" id="how">❓ How to play</button>
        <button class="btn" id="set">⚙️</button>
      </div>
    </div>`;
  const $ = (s) => view.querySelector(s);
  if (g) $('#resume').onclick = () => go('game', { resume: g });
  $('#new').onclick = () => {
    if (g) {
      showModal(`<h2>New game?</h2><p class="muted">Your current game (${g.score.toLocaleString()} points) will be lost.</p>
        <div class="row"><button class="btn grow" id="no">Cancel</button><button class="btn primary grow" id="yes">New game</button></div>`, (m) => {
        m.querySelector('#no').onclick = closeModal;
        m.querySelector('#yes').onclick = () => go('game', { mode: 'classic' });
      });
    } else go('game', { mode: 'classic' });
  };
  $('#daily').onclick = () => go('game', { mode: 'daily' });
  view.querySelectorAll('.theme-dot').forEach((b) => (b.onclick = () => { settings.theme = b.dataset.t; saveSettings(); applyTheme(); renderHome(); }));
  $('#ach').onclick = showAchievements;
  $('#how').onclick = () => showHowTo();
  $('#set').onclick = showSettings;
  if (!settings.seenHowTo) showHowTo();
}

function currentDailyStreak() {
  const y = todayKey(new Date(Date.now() - 86400000));
  return stats.lastDaily === todayKey() || stats.lastDaily === y ? stats.dailyStreak : 0;
}

function showHowTo(after) {
  showModal(`<div class="big-emoji">🧩</div><h2>How to play</h2>
    <div class="howto">
      <div><span class="n">1</span><span>Drag a piece from the tray onto the board. You can also tap a piece, then tap where it should go.</span></div>
      <div><span class="n">2</span><span>Fill a whole <b>row</b>, <b>column</b> or <b>3×3 square</b> to clear it.</span></div>
      <div><span class="n">3</span><span>Clear several at once, or on back-to-back moves, for big <b>combo</b> points.</span></div>
      <div><span class="n">4</span><span>The game ends when none of your pieces fit. You get one free 🔀 Shuffle per game.</span></div>
    </div>
    <button class="btn primary block" id="ok">Got it!</button>`, (m) => {
    m.querySelector('#ok').onclick = () => { settings.seenHowTo = true; saveSettings(); closeModal(); after && after(); };
  });
}

function showAchievements() {
  showModal(`<h2>Achievements</h2><div class="list">${ACH.map(([id, e, t, d]) => `
    <div class="it ${achievements[id] ? '' : 'locked'}"><span class="b">${e}</span><span class="grow"><b>${t}</b><br><span class="muted small">${d}</span></span>${achievements[id] ? '✓' : ''}</div>`).join('')}</div>
    <div class="list" style="margin-top:10px">
      <div class="it"><span class="grow muted">Total lines cleared</span><b>${stats.lines.toLocaleString()}</b></div>
      <div class="it"><span class="grow muted">Average score</span><b>${stats.games ? Math.round(stats.total / stats.games).toLocaleString() : 0}</b></div>
      <div class="it"><span class="grow muted">Most lines in one move</span><b>${stats.maxLines}</b></div>
    </div>
    <button class="btn primary block" id="ok" style="margin-top:12px">Close</button>`, (m) => (m.querySelector('#ok').onclick = closeModal));
}

function showSettings() {
  showModal(`<h2>Settings</h2>
    <label class="switch"><span>🔊 Sound effects</span><input type="checkbox" id="snd" ${settings.sound ? 'checked' : ''}></label>
    <label class="switch"><span>📳 Vibration</span><input type="checkbox" id="hap" ${settings.haptics ? 'checked' : ''}></label>
    <button class="btn block" id="reset" style="margin-top:14px">Reset statistics</button>
    <button class="btn primary block" id="ok" style="margin-top:10px">Done</button>`, (m) => {
    m.querySelector('#snd').onchange = (e) => { settings.sound = e.target.checked; saveSettings(); };
    m.querySelector('#hap').onchange = (e) => { settings.haptics = e.target.checked; saveSettings(); };
    m.querySelector('#ok').onclick = () => { closeModal(); renderHome(); };
    m.querySelector('#reset').onclick = () => {
      Object.assign(stats, { games: 0, best: 0, total: 0, lines: 0, bestCombo: 0, maxLines: 0, daily: {}, dailyStreak: 0, lastDaily: null });
      achievements = {};
      saveStats(); store.set('achievements', achievements); store.set('game', null);
      toast('Statistics reset'); closeModal(); renderHome();
    };
  });
}

// ---------------------------------------------------------------- game
function renderGame({ mode = 'classic', resume = null } = {}) {
  let game;
  if (resume) game = resume;
  else if (mode === 'daily') game = new Game({ seed: hashStr('daily' + todayKey()), mode: 'daily' });
  else game = new Game({ mode: 'classic' });
  const isDaily = game.mode === 'daily';
  if (isDaily) game.dayKey = game.dayKey || todayKey();
  const best = () => (isDaily ? Math.max(stats.daily[game.dayKey] || 0) : stats.best);
  const startBest = best();
  let celebratedBest = false;

  view.innerHTML = `
    <div class="hud">
      <button class="icon" id="home" aria-label="Menu">☰</button>
      <div class="score" id="score"><b>${game.score}</b><span>${isDaily ? 'Daily · ' : ''}Best ${best().toLocaleString()}</span></div>
      <button class="icon" id="shuffle" aria-label="Shuffle pieces">🔀<small id="shN" style="font-size:.7rem"></small></button>
    </div>
    <div class="sub-hud"><span id="lines">Lines ${game.lines}</span><span id="combo"></span></div>
    <div class="board-wrap"><div class="board" id="board"></div><div id="fx"></div></div>
    <div class="tray" id="tray"></div>`;
  const boardEl = view.querySelector('#board');
  const trayEl = view.querySelector('#tray');
  const fxEl = view.querySelector('#fx');
  const cells = [];
  for (let i = 0; i < N * N; i++) {
    const d = document.createElement('div');
    const r = Math.floor(i / N), c = i % N;
    d.className = 'cell' + ((Math.floor(r / 3) + Math.floor(c / 3)) % 2 ? ' alt' : '');
    d.dataset.base = d.className;
    boardEl.appendChild(d);
    cells.push(d);
  }

  let preview = null; // {cells, clears, color}
  let selected = -1;
  const clearing = new Map(); // cell -> color (for the clear animation)
  const placedNow = new Set();

  function drawBoard() {
    const pv = preview ? new Set(preview.cells) : null;
    const pvClear = preview ? preview.clears.cells : null;
    for (let i = 0; i < N * N; i++) {
      const el = cells[i];
      let cls = el.dataset.base;
      let color = game.board[i] || clearing.get(i) || 0;
      if (color) cls += ' blk';
      if (clearing.has(i)) cls += ' clearing';
      if (placedNow.has(i)) cls += ' placed';
      if (pv && pv.has(i)) { cls += ' pv'; color = preview.color; }
      if (pvClear && pvClear.has(i)) cls += ' pv-clear';
      if (el.className !== cls) el.className = cls;
      const v = color ? `var(--b${color})` : '';
      if (el.style.getPropertyValue('--c') !== v) el.style.setProperty('--c', v);
    }
  }

  function pieceHTML(name, size) {
    const s = SHAPE[name];
    const set = new Set(s.cells.map(([r, c]) => r + ',' + c));
    let h = '';
    for (let r = 0; r < s.h; r++) for (let c = 0; c < s.w; c++) h += `<i class="${set.has(r + ',' + c) ? '' : 'e'}" style="--c:var(--b${s.color})"></i>`;
    return `<div class="piece" style="grid-template-columns:repeat(${s.w},var(--s));--s:${size}px">${h}</div>`;
  }

  function trayCell() {
    const slotW = (trayEl.clientWidth - 16) / 3;
    return Math.max(12, Math.min(24, Math.floor((slotW - 24) / 5) - 3));
  }

  function drawTray() {
    const size = trayCell();
    trayEl.innerHTML = game.tray.map((t, k) => {
      if (!t) return `<div class="slot" data-k="${k}"></div>`;
      const fits = fitsSomewhere(t);
      return `<div class="slot ${fits ? '' : 'dim'} ${selected === k ? 'sel' : ''}" data-k="${k}">${pieceHTML(t, size)}</div>`;
    }).join('');
    trayEl.querySelectorAll('.slot').forEach((el) => el.addEventListener('pointerdown', onPick));
    view.querySelector('#shN').textContent = game.shuffles ? '' : '0';
    view.querySelector('#shuffle').style.opacity = game.shuffles ? 1 : 0.4;
  }

  function fitsSomewhere(t) {
    const s = SHAPE[t];
    for (let r = 0; r <= N - s.h; r++) for (let c = 0; c <= N - s.w; c++) if (game.canPlace(game.tray.indexOf(t), r, c)) return true;
    return false;
  }

  function drawHud(bump = false) {
    const sc = view.querySelector('#score');
    sc.querySelector('b').textContent = game.score.toLocaleString();
    sc.querySelector('span').textContent = `${isDaily ? 'Daily · ' : ''}Best ${Math.max(best(), game.score).toLocaleString()}`;
    if (bump) { sc.classList.remove('bump'); void sc.offsetWidth; sc.classList.add('bump'); }
    view.querySelector('#lines').textContent = `Lines ${game.lines}`;
    view.querySelector('#combo').innerHTML = game.combo >= 2 ? `<span class="combo-tag">🔥 Combo ×${game.combo}</span>` : '';
  }

  function persist() { store.set('game', isDaily ? null : game.toJSON()); }

  // ----- geometry
  function boardMetrics() {
    const rect = boardEl.getBoundingClientRect();
    const first = cells[0].getBoundingClientRect(), second = cells[1].getBoundingClientRect();
    return { left: first.left, top: first.top, pitch: second.left - first.left, size: first.width, rect };
  }

  // ----- dragging
  let drag = null;
  function onPick(e) {
    const k = +e.currentTarget.dataset.k;
    const name = game.tray[k];
    if (!name || game.over) return;
    e.preventDefault();
    const m = boardMetrics();
    const s = SHAPE[name];
    const ghost = document.createElement('div');
    ghost.className = 'ghost';
    ghost.style.gridTemplateColumns = `repeat(${s.w}, ${m.size}px)`;
    ghost.style.gap = `${m.pitch - m.size}px`;
    const set = new Set(s.cells.map(([r, c]) => r + ',' + c));
    for (let r = 0; r < s.h; r++) for (let c = 0; c < s.w; c++) {
      const i = document.createElement('i');
      i.style.width = i.style.height = m.size + 'px';
      if (set.has(r + ',' + c)) i.style.setProperty('--c', `var(--b${s.color})`); else i.className = 'e';
      ghost.appendChild(i);
    }
    document.body.appendChild(ghost);
    const touch = e.pointerType !== 'mouse';
    const gw = s.w * m.pitch, gh = s.h * m.pitch;
    drag = { k, s, ghost, gw, gh, lift: touch ? Math.max(60, m.pitch * 1.6) : 0, startX: e.clientX, startY: e.clientY, moved: false, slot: e.currentTarget, m };
    e.currentTarget.classList.add('lifted');
    sfx.pick();
    moveGhost(e.clientX, e.clientY);
    window.addEventListener('pointermove', onMove);
    window.addEventListener('pointerup', onUp);
    window.addEventListener('pointercancel', onCancel);
  }
  function moveGhost(x, y) {
    const d = drag;
    const left = x - d.gw / 2, top = y - d.gh - d.lift + (d.lift ? 0 : d.gh / 2);
    d.ghost.style.transform = `translate(${left}px, ${top}px)`;
    const r = Math.round((top - d.m.top) / d.m.pitch), c = Math.round((left - d.m.left) / d.m.pitch);
    const p = game.preview(d.k, r, c);
    d.target = p ? { r, c } : null;
    const next = p ? { cells: p.cells, clears: p.clears, color: d.s.color } : null;
    const changed = JSON.stringify(next && next.cells) !== JSON.stringify(preview && preview.cells);
    preview = next;
    if (changed) drawBoard();
  }
  function onMove(e) {
    if (!drag) return;
    if (Math.hypot(e.clientX - drag.startX, e.clientY - drag.startY) > 6) drag.moved = true;
    moveGhost(e.clientX, e.clientY);
  }
  function endDrag() {
    window.removeEventListener('pointermove', onMove);
    window.removeEventListener('pointerup', onUp);
    window.removeEventListener('pointercancel', onCancel);
  }
  function onUp() {
    if (!drag) return;
    endDrag();
    const d = drag;
    drag = null;
    preview = null;
    if (!d.moved) {
      // treat as a tap: select this piece for tap-to-place
      d.ghost.remove();
      d.slot.classList.remove('lifted');
      selected = selected === d.k ? -1 : d.k;
      drawTray(); drawBoard();
      return;
    }
    if (d.target) {
      d.ghost.remove();
      doPlace(d.k, d.target.r, d.target.c);
    } else {
      sfx.bad();
      const rect = d.slot.getBoundingClientRect();
      d.ghost.classList.add('back');
      d.ghost.style.transform = `translate(${rect.left + rect.width / 2 - d.gw / 2}px, ${rect.top + rect.height / 2 - d.gh / 2}px) scale(.5)`;
      setTimeout(() => { d.ghost.remove(); d.slot.classList.remove('lifted'); }, 200);
      drawBoard();
    }
  }
  function onCancel() {
    if (!drag) return;
    endDrag();
    drag.ghost.remove();
    drag.slot.classList.remove('lifted');
    drag = null; preview = null;
    drawBoard();
  }

  // tap-to-place: tap a board cell with a piece selected (piece is centred on that cell)
  boardEl.addEventListener('pointerup', (e) => {
    if (selected < 0 || drag) return;
    const idx = cells.indexOf(e.target.closest('.cell'));
    if (idx < 0) return;
    const s = SHAPE[game.tray[selected]];
    const r = Math.floor(idx / N) - Math.floor((s.h - 1) / 2), c = (idx % N) - Math.floor((s.w - 1) / 2);
    if (game.canPlace(selected, r, c)) { const k = selected; selected = -1; doPlace(k, r, c); }
    else { sfx.bad(); buzz(30); toast("That piece doesn't fit there"); }
  });

  function doPlace(k, r, c) {
    const colorOf = game.board.slice();
    const s = SHAPE[game.tray[k]];
    const res = game.place(k, r, c);
    if (!res) return;
    selected = -1;
    for (const p of res.placed) colorOf[p] = s.color;
    placedNow.clear();
    res.placed.forEach((p) => { if (!res.cleared.includes(p)) placedNow.add(p); });
    res.cleared.forEach((p) => clearing.set(p, colorOf[p]));
    if (res.lines) {
      sfx.clear(res.lines, res.combo); buzz(res.lines > 1 ? [20, 30, 40] : 25);
      const praise = PRAISE[Math.min(PRAISE.length - 1, res.lines + Math.max(0, res.combo - 1))] || 'Nice!';
      fxEl.innerHTML = `<div class="popup"><b>+${res.points}</b><span>${res.combo >= 2 ? `Combo ×${res.combo}! ` : ''}${praise}</span></div>`;
      if (res.lines >= 3 || res.combo >= 4) confetti(80);
      stats.maxLines = Math.max(stats.maxLines, res.lines);
      unlock('clear1');
      if (res.lines >= 3) unlock('multi3');
      if (res.combo >= 3) unlock('combo3');
      if (res.combo >= 6) unlock('combo6');
    } else { sfx.place(); buzz(10); }
    if (!celebratedBest && startBest > 0 && game.score > startBest) {
      celebratedBest = true; sfx.best(); confetti(140); toast('🏆 New best score!');
    }
    drawBoard(); drawTray(); drawHud(true);
    persist();
    setTimeout(() => { clearing.clear(); placedNow.clear(); drawBoard(); }, 430);
    setTimeout(() => { if (fxEl.firstChild) fxEl.innerHTML = ''; }, 1000);
    if (res.over) setTimeout(onStuck, 650);
  }

  function onStuck() {
    if (game.shuffles > 0) {
      showModal(`<div class="big-emoji">😮</div><h2>No moves left!</h2><p class="muted">Use your free shuffle to get new pieces and keep going?</p>
        <div class="row"><button class="btn grow" id="end">End game</button><button class="btn primary grow" id="sh">🔀 Shuffle</button></div>`, (m) => {
        m.querySelector('#end').onclick = () => { game.shuffles = 0; finish(); };
        m.querySelector('#sh').onclick = () => { closeModal(); doShuffle(); };
      }, false);
    } else finish();
  }

  function doShuffle() {
    if (!game.shuffle()) { toast('No shuffles left'); return; }
    sfx.pick(); drawTray(); drawBoard(); persist();
    if (game.over) setTimeout(onStuck, 400);
  }

  function finish() {
    sfx.over();
    stats.games++;
    stats.total += game.score;
    stats.lines += game.lines;
    stats.bestCombo = Math.max(stats.bestCombo, game.bestCombo);
    const prevBest = isDaily ? (stats.daily[game.dayKey] || 0) : stats.best;
    const newBest = game.score > prevBest;
    if (isDaily) {
      if (stats.daily[game.dayKey] == null) {
        const y = todayKey(new Date(Date.now() - 86400000));
        stats.dailyStreak = stats.lastDaily === y ? stats.dailyStreak + 1 : (stats.lastDaily === game.dayKey ? stats.dailyStreak : 1);
        stats.lastDaily = game.dayKey;
      }
      stats.daily[game.dayKey] = Math.max(prevBest, game.score);
      unlock('daily1');
      if (stats.dailyStreak >= 7) unlock('daily7');
    } else stats.best = Math.max(stats.best, game.score);
    saveStats();
    store.set('game', null);
    unlock('first');
    if (game.score >= 500) unlock('s500');
    if (game.score >= 1500) unlock('s1500');
    if (game.score >= 3000) unlock('s3000');
    if (stats.lines >= 100) unlock('lines100');
    if (stats.games >= 25) unlock('games25');
    if (newBest && prevBest > 0) confetti(160);
    showModal(`<div class="big-emoji">${newBest ? '🏆' : '🧱'}</div>
      <h2>${newBest ? (prevBest ? 'New best!' : 'Great game!') : 'Game over'}</h2>
      <div class="final">${game.score.toLocaleString()}</div>
      <p class="muted">${isDaily ? 'Daily best' : 'Best'} ${Math.max(prevBest, game.score).toLocaleString()} · ${game.lines} lines · top combo ×${game.bestCombo}</p>
      <div class="row"><button class="btn grow" id="home2">Home</button><button class="btn primary grow" id="again">${isDaily ? 'Try again' : 'Play again'}</button></div>`, (m) => {
      m.querySelector('#home2').onclick = () => go('home');
      m.querySelector('#again').onclick = () => go('game', { mode: game.mode });
    }, false);
  }

  view.querySelector('#home').onclick = () => {
    showModal(`<h2>Paused</h2><p class="muted">${game.score.toLocaleString()} points${isDaily ? ' · Daily Challenge' : ''}</p>
      <button class="btn primary block" id="res">▶ Resume</button>
      <button class="btn block" id="restart" style="margin-top:10px">↻ Restart</button>
      <button class="btn block" id="hm" style="margin-top:10px">🏠 Home${isDaily ? '' : ' (game is saved)'}</button>`, (m) => {
      m.querySelector('#res').onclick = closeModal;
      m.querySelector('#restart').onclick = () => go('game', { mode: game.mode });
      m.querySelector('#hm').onclick = () => go('home');
    });
  };
  view.querySelector('#shuffle').onclick = () => {
    if (!game.shuffles) return toast('No shuffles left this game');
    showModal(`<h2>Shuffle pieces?</h2><p class="muted">Swap your remaining pieces for new ones. You have 1 shuffle per game.</p>
      <div class="row"><button class="btn grow" id="no">Cancel</button><button class="btn primary grow" id="yes">🔀 Shuffle</button></div>`, (m) => {
      m.querySelector('#no').onclick = closeModal;
      m.querySelector('#yes').onclick = () => { closeModal(); doShuffle(); };
    });
  };
  const onResize = () => drawTray();
  window.addEventListener('resize', onResize);
  cleanup = () => { window.removeEventListener('resize', onResize); if (drag) onCancel(); persist(); };

  drawBoard(); drawTray(); drawHud();
  persist();
  if (game.over) setTimeout(onStuck, 300);
  window.__blockora = { game, doPlace }; // test hook
}

go('home');
if ('serviceWorker' in navigator && location.protocol !== 'file:') navigator.serviceWorker.register('sw.js').catch(() => {});
