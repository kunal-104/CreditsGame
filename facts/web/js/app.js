import * as Wiki from './wiki.js';

// ------------------------------------------------------------ storage
const store = {
  get(k, d) { try { const v = localStorage.getItem('curio.' + k); return v == null ? d : JSON.parse(v); } catch { return d; } },
  set(k, v) { try { localStorage.setItem('curio.' + k, JSON.stringify(v)); } catch { /* unavailable */ } },
};

let DATA = null;
let CAT = {}, COUNTRY = {};
const profile = Object.assign({ home: null, interests: [], xp: 0, streak: 0, lastDay: null, theme: 'auto', bestCombo: 0, wiki: 0 }, store.get('profile', {}));
const answers = store.get('answers', {}); // id -> {ok, bad, last, lastOk}
let saved = store.get('saved', []); // [{type:'fact', id} | {type:'wiki', title, extract, url, thumb}]
const daily = store.get('daily', {}); // date -> {score, total}
const saveProfile = () => { store.set('profile', profile); updatePills(); };

const view = document.getElementById('view');
const modal = document.getElementById('modal');
const toastEl = document.getElementById('toast');
const backBtn = document.getElementById('backBtn');

// ------------------------------------------------------------ helpers
const esc = (s) => String(s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const flag = (code) => (code === 'world' ? '🌐' : String.fromCodePoint(...[...code].map((c) => 127397 + c.charCodeAt(0))));
const wikiUrl = (title) => 'https://en.wikipedia.org/w/index.php?title=Special:Search&go=Go&search=' + encodeURIComponent(title);
const todayKey = (d = new Date()) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
function hashStr(s) { let h = 2166136261; for (const c of s) h = Math.imul(h ^ c.charCodeAt(0), 16777619); return h >>> 0; }
function rng(seed) {
  let a = seed >>> 0;
  return () => { a = (a + 0x6d2b79f5) >>> 0; let t = a; t = Math.imul(t ^ (t >>> 15), t | 1); t ^= t + Math.imul(t ^ (t >>> 7), t | 61); return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
}
function shuffle(a, r = Math.random) { for (let i = a.length - 1; i > 0; i--) { const j = Math.floor(r() * (i + 1)); [a[i], a[j]] = [a[j], a[i]]; } return a; }

let toastTimer;
function toast(msg) { toastEl.textContent = msg; toastEl.hidden = false; clearTimeout(toastTimer); toastTimer = setTimeout(() => (toastEl.hidden = true), 2400); }
function showModal(html, mount) { modal.innerHTML = `<div class="card">${html}</div>`; modal.hidden = false; mount && mount(modal); }
function closeModal() { modal.hidden = true; modal.innerHTML = ''; }

function applyTheme() {
  if (profile.theme === 'auto') delete document.documentElement.dataset.theme;
  else document.documentElement.dataset.theme = profile.theme;
}

// ------------------------------------------------------------ levels & xp
const TITLES = [[1, 'Curious'], [3, 'Explorer'], [6, 'Scholar'], [10, 'Sage'], [15, 'Polymath'], [25, 'Living Encyclopedia']];
const xpFor = (lvl) => 50 * lvl * (lvl - 1); // xp needed to reach level
function levelOf(xp) { let l = 1; while (xp >= xpFor(l + 1)) l++; return l; }
const titleOf = (lvl) => TITLES.filter(([l]) => lvl >= l).pop()[1];
function addXp(n) {
  const before = levelOf(profile.xp);
  profile.xp += n;
  const after = levelOf(profile.xp);
  touchStreak();
  saveProfile();
  if (after > before) setTimeout(() => toast(`Level ${after}! You're now a${/^[AEIOU]/.test(titleOf(after)) ? 'n' : ''} ${titleOf(after)} ✨`), 600);
}
function touchStreak() {
  const t = todayKey();
  if (profile.lastDay === t) return;
  const y = todayKey(new Date(Date.now() - 86400000));
  profile.streak = profile.lastDay === y ? profile.streak + 1 : 1;
  profile.lastDay = t;
}
function currentStreak() {
  const y = todayKey(new Date(Date.now() - 86400000));
  return profile.lastDay === todayKey() || profile.lastDay === y ? profile.streak : 0;
}
function updatePills() {
  document.getElementById('streakPill').textContent = '🔥 ' + currentStreak();
  document.getElementById('xpPill').textContent = '⭐ ' + profile.xp;
}

// ------------------------------------------------------------ sessions
// Prioritises facts you haven't seen, facts you got wrong, facts from beyond your home country,
// and your interests. Balances myths and truths so guessing "Fact" every time doesn't pay.
function buildSession(pool, size = 10, seed = null) {
  const r = seed == null ? Math.random : rng(seed);
  const now = Date.now();
  const scored = pool.map((f) => {
    const a = answers[f.id];
    let p = r() * 1.5;
    if (!a) p += 4;
    else if (a.bad > a.ok || (a.lastOk === false && now - a.last > 3600e3)) p += 3;
    else p -= 2 + (now - a.last < 86400e3 ? 2 : 0);
    if (profile.home && !f.r.includes(profile.home) && !f.r.includes('world')) p += 1.2;
    if (profile.interests.includes(f.c)) p += 0.8;
    return { f, p };
  }).sort((a, b) => b.p - a.p);
  const n = Math.min(size, pool.length);
  const myths = scored.filter((x) => !x.f.a), truths = scored.filter((x) => x.f.a);
  const wantMyths = Math.min(myths.length, Math.round(n * (0.35 + r() * 0.15)));
  const pick = [...myths.slice(0, wantMyths), ...truths.slice(0, n - wantMyths)];
  if (pick.length < n) pick.push(...scored.filter((x) => !pick.includes(x)).slice(0, n - pick.length));
  // avoid three in a row from the same category
  const out = shuffle(pick.map((x) => x.f), r);
  for (let i = 2; i < out.length; i++) {
    if (out[i].c === out[i - 1].c && out[i].c === out[i - 2].c) {
      const j = out.findIndex((x, k) => k > i && x.c !== out[i].c);
      if (j > 0) [out[i], out[j]] = [out[j], out[i]];
    }
  }
  return out;
}

function recordAnswer(f, correct) {
  const a = answers[f.id] || { ok: 0, bad: 0, last: 0, lastOk: null };
  correct ? a.ok++ : a.bad++;
  a.last = Date.now();
  a.lastOk = correct;
  answers[f.id] = a;
  store.set('answers', answers);
}

const isSaved = (id) => saved.some((s) => s.type === 'fact' && s.id === id);
function toggleSaveFact(id) {
  if (isSaved(id)) saved = saved.filter((s) => !(s.type === 'fact' && s.id === id));
  else saved.unshift({ type: 'fact', id, at: Date.now() });
  store.set('saved', saved);
  return isSaved(id);
}

// ------------------------------------------------------------ router
const routes = { '': renderToday, explore: renderExplore, play: renderPlay, passport: renderPassport, country: renderCountry, live: renderLive, timemachine: renderTimeMachine, rabbithole: renderRabbitHole, me: renderMe, saved: renderSaved };
let cleanup = null;
let pendingSession = null; // {title, facts, kind}
function route() {
  if (cleanup) { cleanup(); cleanup = null; }
  closeModal();
  const [name, ...args] = location.hash.replace(/^#\/?/, '').split('/');
  const tab = { '': 'today', explore: 'explore', passport: 'passport', country: 'passport', live: 'live', timemachine: 'live', rabbithole: 'live', me: 'me', saved: 'me' }[name];
  document.querySelectorAll('#tabbar a').forEach((a) => a.classList.toggle('on', a.dataset.tab === tab));
  document.body.classList.toggle('playing', name === 'play');
  backBtn.hidden = ['', 'explore', 'passport', 'live', 'me'].includes(name);
  window.scrollTo(0, 0);
  (routes[name] || renderToday)(...args.map(decodeURIComponent));
  updatePills();
}
window.addEventListener('hashchange', route);
backBtn.onclick = () => (history.length > 1 ? history.back() : (location.hash = '#/'));

function startSession(title, facts, kind = 'mix', meta = {}) {
  if (!facts.length) return toast('Nothing to play here yet');
  pendingSession = { title, facts, kind, ...meta };
  location.hash = '#/play';
}

// ------------------------------------------------------------ today
function factOfTheDay() {
  const pool = DATA.facts.filter((f) => f.a && !(profile.home && f.r.includes(profile.home)));
  return pool[hashStr('fotd' + todayKey()) % pool.length];
}
function renderToday() {
  const lvl = levelOf(profile.xp);
  const into = profile.xp - xpFor(lvl), span = xpFor(lvl + 1) - xpFor(lvl);
  const d = daily[todayKey()];
  const f = factOfTheDay();
  const seen = Object.keys(answers).length;
  const mistakes = DATA.facts.filter((x) => answers[x.id] && answers[x.id].lastOk === false).length;
  const home = profile.home ? COUNTRY[profile.home] : null;
  view.innerHTML = `
    <div class="hero-card">
      <span class="deco">🧭</span>
      <h2>${d ? 'Daily done ✓' : 'Your daily 10'}</h2>
      <p>${d ? `You scored ${d.score}/${d.total} today. Keep exploring below, or come back tomorrow for a new set.` : 'Ten surprising claims from around the world. Fact or myth? Takes about 3 minutes.'}</p>
      <button class="btn" id="dailyBtn">${d ? 'Play a bonus round' : 'Start today’s 10'}</button>
    </div>
    <div class="card">
      <div class="lvl">
        <div class="badge">${lvl}</div>
        <div class="grow">
          <b>${titleOf(lvl)}</b> <span class="muted small">· ${profile.xp} XP</span>
          <div class="bar" style="margin-top:6px"><div style="width:${(into / span) * 100}%"></div></div>
          <div class="muted small" style="margin-top:4px">${span - into} XP to level ${lvl + 1} · ${seen} of ${DATA.facts.length} facts discovered</div>
        </div>
      </div>
    </div>
    <div class="card fotd">
      <div class="muted small" style="margin-bottom:6px">${CAT[f.c].emoji} Fact of the day · ${f.r.map(flag).join(' ')}</div>
      <b>${esc(f.s)}</b>
      <p class="small muted" style="margin:8px 0 0">${esc(f.e)}</p>
      <div class="row" style="margin-top:10px"><a class="btn small" href="${wikiUrl(f.w)}" target="_blank" rel="noopener">Read more ↗</a>
      <button class="btn small ghost" id="fotdSave">${isSaved(f.id) ? '★ Saved' : '☆ Save'}</button></div>
    </div>
    <div class="section-title"><h2>Go deeper</h2></div>
    <div class="grid2">
      <a class="tile" href="#/passport"><span class="emoji">🛂</span><b>World Passport</b><small>${home ? `Facts from beyond ${esc(home.name)} that you probably don't know` : 'Collect stamps from countries around the world'}</small></a>
      <a class="tile" href="#/timemachine"><span class="emoji">⏳</span><b>Time Machine</b><small>Real events from this day in history. Which came first?</small></a>
      <a class="tile" href="#/rabbithole"><span class="emoji">🕳️</span><b>Rabbit Hole</b><small>An endless feed of random Wikipedia articles, so there's always something new</small></a>
      ${mistakes ? `<button class="tile" id="reviewBtn"><span class="emoji">🔁</span><b>Review mistakes</b><small>${mistakes} fact${mistakes > 1 ? 's' : ''} to revisit. Spaced repetition helps them stick.</small></button>`
        : '<a class="tile" href="#/explore"><span class="emoji">🧭</span><b>20 topics</b><small>Science, wars, languages, money, ethics and more</small></a>'}
    </div>`;
  view.querySelector('#dailyBtn').onclick = () => {
    const seed = d ? null : hashStr('daily' + todayKey());
    startSession(d ? 'Bonus round' : 'Daily 10', buildSession(DATA.facts, 10, seed), d ? 'mix' : 'daily');
  };
  view.querySelector('#fotdSave').onclick = (e) => { e.target.textContent = toggleSaveFact(f.id) ? '★ Saved' : '☆ Save'; };
  const rb = view.querySelector('#reviewBtn');
  if (rb) rb.onclick = () => startSession('Review', buildSession(DATA.facts.filter((x) => answers[x.id] && answers[x.id].lastOk === false), 10), 'review');
}

// ------------------------------------------------------------ explore
function catProgress(id) {
  const list = DATA.facts.filter((f) => f.c === id);
  return { total: list.length, seen: list.filter((f) => answers[f.id]).length };
}
function renderExplore() {
  view.innerHTML = `<h1>Explore</h1><p class="muted" style="margin-top:-4px">Pick a topic. Each round mixes facts with common myths.</p>
    <div class="cats">${DATA.categories.map((c) => {
      const p = catProgress(c.id);
      return `<button class="cat" data-c="${c.id}" style="--c:${c.color}"><span class="e">${c.emoji}</span><div><b>${esc(c.name)}</b><small>${p.seen}/${p.total} discovered</small><div class="mini"><div style="width:${(p.seen / p.total) * 100}%"></div></div></div></button>`;
    }).join('')}</div>`;
  view.querySelectorAll('.cat').forEach((b) => (b.onclick = () => {
    const c = CAT[b.dataset.c];
    startSession(c.name, buildSession(DATA.facts.filter((f) => f.c === c.id), 10), 'category');
  }));
}

// ------------------------------------------------------------ play
function renderPlay() {
  const S = pendingSession;
  if (!S) { location.hash = '#/'; return; }
  let i = 0, score = 0, combo = 0, xpEarned = 0, newFacts = 0;
  const results = [];
  const render = () => {
    if (i >= S.facts.length) return renderSummary();
    const f = S.facts[i];
    const c = CAT[f.c];
    view.innerHTML = `
      <div class="play-head">
        <button class="icon-btn" id="quit" aria-label="Quit"><svg viewBox="0 0 24 24"><path d="M18 6L6 18M6 6l12 12"/></svg></button>
        <div class="bar"><div style="width:${(i / S.facts.length) * 100}%"></div></div>
        <span class="combo">${combo >= 2 ? '🔥×' + combo : `${i + 1}/${S.facts.length}`}</span>
      </div>
      <div class="stage">
        <div class="qcard pop" id="qcard" style="--c:${c.color}">
          <span class="stamp fact">FACT</span><span class="stamp myth">MYTH</span>
          <div class="meta"><span class="chip">${c.emoji} ${esc(c.name)}</span><span class="flags">${f.r.map(flag).join('')}</span></div>
          <div class="statement">${esc(f.s)}</div>
          <div id="area">
            <div class="answers"><button class="btn myth" id="bMyth">✗ Myth</button><button class="btn fact" id="bFact">✓ Fact</button></div>
            <div class="swipe-hint" style="margin-top:10px"><span>← swipe</span><span>swipe →</span></div>
          </div>
        </div>
      </div>`;
    view.querySelector('#quit').onclick = () => (results.length ? renderSummary() : history.back());
    const card = view.querySelector('#qcard');
    view.querySelector('#bMyth').onclick = () => answer(false);
    view.querySelector('#bFact').onclick = () => answer(true);
    enableSwipe(card, (dir) => answer(dir > 0));
  };

  let answered = false;
  function answer(said) {
    if (answered) return;
    answered = true;
    const f = S.facts[i];
    const correct = said === f.a;
    const first = !answers[f.id];
    if (first) newFacts++;
    recordAnswer(f, correct);
    let gain = correct ? 10 + Math.min(combo, 5) * 2 : 3;
    combo = correct ? combo + 1 : 0;
    profile.bestCombo = Math.max(profile.bestCombo, combo);
    if (correct) score++;
    xpEarned += gain;
    addXp(gain);
    results.push({ f, correct });
    const card = view.querySelector('#qcard');
    card.style.transform = '';
    card.querySelectorAll('.stamp').forEach((s) => (s.style.opacity = 0));
    const area = view.querySelector('#area');
    area.innerHTML = `
      <span class="xp-float">+${gain} XP</span>
      <div class="verdict ${correct ? 'ok' : 'no'}">${correct ? '✓ Correct!' : '✗ Not quite'}<span class="tag">${f.a ? 'It’s a FACT' : 'It’s a MYTH'}</span></div>
      <p class="explain">${esc(f.e)}</p>
      <div class="reveal-actions">
        <button class="btn primary grow" id="next">${i + 1 < S.facts.length ? 'Next →' : 'See results'}</button>
        <a class="btn" href="${wikiUrl(f.w)}" target="_blank" rel="noopener">Learn more ↗</a>
        <button class="btn" id="save">${isSaved(f.id) ? '★' : '☆'}</button>
      </div>`;
    if (navigator.vibrate) navigator.vibrate(correct ? 20 : [40, 40, 40]);
    view.querySelector('.combo').textContent = combo >= 2 ? '🔥×' + combo : `${i + 1}/${S.facts.length}`;
    area.querySelector('#save').onclick = (e) => { e.target.textContent = toggleSaveFact(f.id) ? '★' : '☆'; toast(isSaved(f.id) ? 'Saved to your collection' : 'Removed'); };
    area.querySelector('#next').onclick = next;
    area.querySelector('#next').focus({ preventScroll: true });
  }
  function next() { i++; answered = false; render(); }

  function renderSummary() {
    document.body.classList.remove('playing');
    const total = results.length;
    if (S.kind === 'daily' && total === S.facts.length) {
      daily[todayKey()] = { score, total };
      store.set('daily', daily);
    }
    const pct = total ? score / total : 0;
    const msg = pct === 1 ? 'Perfect round! 🏆' : pct >= .7 ? 'Impressive! 🎉' : pct >= .4 ? 'Nice, and you learned something new! 📚' : 'Every wrong answer is a new fact learned. 🌱';
    view.innerHTML = `
      <div class="card" style="text-align:center">
        <div class="muted small">${esc(S.title)}</div>
        <div class="summary-score">${score}/${total}</div>
        <p style="margin:6px 0 2px"><b>${msg}</b></p>
        <p class="muted small" style="margin:0">+${xpEarned} XP · ${newFacts} new fact${newFacts === 1 ? '' : 's'} · best streak 🔥${profile.bestCombo}</p>
      </div>
      <div class="card">${results.map(({ f, correct }) => `
        <div class="list-item"><span class="ic ${correct ? 'ok' : 'no'}">${correct ? '✓' : '✗'}</span>
          <div class="grow"><div><b>${f.a ? 'Fact' : 'Myth'}:</b> ${esc(f.s)}</div><div class="small muted">${esc(f.e)}</div></div></div>`).join('')}
      </div>
      <div class="row"><a class="btn grow" href="#/">Home</a><button class="btn primary grow" id="again">Play another</button></div>`;
    view.querySelector('#again').onclick = () => {
      const pool = S.kind === 'category' ? DATA.facts.filter((f) => f.c === S.facts[0].c)
        : S.kind === 'country' ? DATA.facts.filter((f) => f.r.includes(S.country)) : DATA.facts;
      pendingSession = { ...S, kind: S.kind === 'daily' ? 'mix' : S.kind, facts: buildSession(pool, 10) };
      route();
    };
    pendingSession = S;
  }

  const onKey = (e) => {
    if (e.key === 'ArrowLeft') answer(false);
    else if (e.key === 'ArrowRight') answer(true);
    else if ((e.key === 'Enter' || e.key === ' ') && answered && view.querySelector('#next')) { e.preventDefault(); next(); }
  };
  document.addEventListener('keydown', onKey);
  cleanup = () => document.removeEventListener('keydown', onKey);
  render();
}

function enableSwipe(card, onSwipe) {
  let x0 = null, dx = 0, id = null;
  const fact = card.querySelector('.stamp.fact'), myth = card.querySelector('.stamp.myth');
  card.addEventListener('pointerdown', (e) => {
    if (e.target.closest('button,a')) return;
    x0 = e.clientX; id = e.pointerId; dx = 0; card.classList.add('dragging');
    card.setPointerCapture(id);
  });
  card.addEventListener('pointermove', (e) => {
    if (x0 == null || e.pointerId !== id) return;
    dx = e.clientX - x0;
    card.style.transform = `translateX(${dx}px) rotate(${dx / 18}deg)`;
    fact.style.opacity = Math.max(0, Math.min(1, dx / 90));
    myth.style.opacity = Math.max(0, Math.min(1, -dx / 90));
  });
  const end = () => {
    if (x0 == null) return;
    card.classList.remove('dragging');
    x0 = null;
    if (Math.abs(dx) > 90) onSwipe(Math.sign(dx));
    else { card.style.transform = ''; fact.style.opacity = 0; myth.style.opacity = 0; }
  };
  card.addEventListener('pointerup', end);
  card.addEventListener('pointercancel', end);
}

// ------------------------------------------------------------ passport
function countryStats(code) {
  const list = DATA.facts.filter((f) => f.r.includes(code));
  return { list, total: list.length, seen: list.filter((f) => answers[f.id]).length };
}
function renderPassport() {
  const countries = DATA.countries.map((c) => ({ ...c, ...countryStats(c.code) })).filter((c) => c.total > 0);
  const stamped = countries.filter((c) => c.seen === c.total).length;
  const home = profile.home ? COUNTRY[profile.home] : null;
  countries.sort((a, b) => (a.code === profile.home) - (b.code === profile.home) || (a.seen === a.total) - (b.seen === b.total) || b.total - a.total);
  view.innerHTML = `<h1>World Passport</h1>
    <p class="muted" style="margin-top:-4px">${home ? `Born in ${flag(home.code)} ${esc(home.name)}? These facts come from everywhere else. ` : ''}Discover every fact from a country to earn its stamp.</p>
    <div class="card row"><div class="grow"><b>${stamped}</b> <span class="muted">of ${countries.length} stamps collected</span><div class="bar" style="margin-top:6px"><div style="width:${(stamped / countries.length) * 100}%"></div></div></div>
      <button class="btn primary" id="surprise">🎲 Surprise me</button></div>
    <input class="search" id="q" placeholder="Search countries…" aria-label="Search countries">
    <div class="countries" id="list"></div>`;
  const list = view.querySelector('#list');
  const draw = (q = '') => {
    list.innerHTML = countries.filter((c) => c.name.toLowerCase().includes(q.toLowerCase())).map((c) => `
      <button class="country ${c.seen === c.total ? 'stamped' : ''} ${c.code === profile.home ? 'home' : ''}" data-code="${c.code}">
        <span class="flag">${flag(c.code)}</span><b>${esc(c.name)}</b><small>${c.code === profile.home ? 'Home · ' : ''}${c.seen}/${c.total} facts</small></button>`).join('');
    list.querySelectorAll('.country').forEach((b) => (b.onclick = () => (location.hash = '#/country/' + b.dataset.code)));
  };
  view.querySelector('#q').oninput = (e) => draw(e.target.value);
  view.querySelector('#surprise').onclick = () => {
    const opts = countries.filter((c) => c.code !== profile.home && c.seen < c.total);
    const pick = (opts.length ? opts : countries)[Math.floor(Math.random() * (opts.length || countries.length))];
    location.hash = '#/country/' + pick.code;
  };
  draw();
}

function renderCountry(code) {
  const c = COUNTRY[code];
  if (!c) { location.hash = '#/passport'; return; }
  const st = countryStats(code);
  view.innerHTML = `
    <div class="card" style="text-align:center">
      <div style="font-size:4rem;line-height:1.1">${flag(code)}</div>
      <h1 style="margin:6px 0 2px">${esc(c.name)}</h1>
      <p class="muted" style="margin:0 0 14px">${st.seen}/${st.total} facts discovered${st.seen === st.total ? ' · Stamp collected ✓' : ''}</p>
      <button class="btn primary block" id="go">${st.seen ? 'Play again' : 'Visit ' + esc(c.name)}</button>
    </div>
    <div class="section-title"><h2>Discovered</h2></div>
    <div class="card">${st.list.filter((f) => answers[f.id]).map((f) => `<div class="list-item"><span>${CAT[f.c].emoji}</span><div><b>${f.a ? 'Fact' : 'Myth'}:</b> ${esc(f.s)}<div class="small muted">${esc(f.e)}</div></div></div>`).join('') || '<div class="empty"><div class="big">🔒</div>Play to unlock this country\'s facts</div>'}</div>
    <a class="btn block" href="${wikiUrl(c.name)}" target="_blank" rel="noopener">Read about ${esc(c.name)} on Wikipedia ↗</a>`;
  view.querySelector('#go').onclick = () => startSession(c.name, buildSession(st.list, 10), 'country', { country: code });
}

// ------------------------------------------------------------ live
function renderLive() {
  view.innerHTML = `<h1>Live</h1><p class="muted" style="margin-top:-4px">Unlimited modes powered by Wikipedia's millions of articles. Needs an internet connection.</p>
    <a class="tile" href="#/timemachine" style="margin-bottom:12px"><span class="emoji">⏳</span><b>Time Machine</b><small>Two real events that happened on today's date in history. Which came first? Every day brings new events.</small></a>
    <a class="tile" href="#/rabbithole"><span class="emoji">🕳️</span><b>Rabbit Hole</b><small>A random Wikipedia article every time. Places, people, inventions, species, wars and more, with no end to it.</small></a>`;
}

function renderTimeMachine() {
  let round = 0, score = 0, events = [], dateLabel = '';
  let day = new Date();
  const ROUNDS = 8;
  async function load(d) {
    view.innerHTML = `<h1>Time Machine</h1><div class="card"><div class="skeleton" style="height:90px;margin-bottom:12px"></div><div class="skeleton" style="height:90px"></div></div>`;
    try {
      const res = await Wiki.onThisDay(d.getMonth() + 1, d.getDate());
      events = shuffle(res.filter((e) => e.year && e.text));
      dateLabel = d.toLocaleDateString(undefined, { month: 'long', day: 'numeric' });
      if (events.length < 4) throw new Error('not enough events');
      round = 0; score = 0;
      ask();
    } catch (e) {
      view.innerHTML = `<h1>Time Machine</h1><div class="card empty"><div class="big">📡</div><p>Couldn't reach Wikipedia. Check your connection and try again.</p><button class="btn primary" id="retry">Retry</button></div>`;
      view.querySelector('#retry').onclick = () => load(d);
    }
  }
  function pair() {
    for (let t = 0; t < 50; t++) {
      const a = events[Math.floor(Math.random() * events.length)], b = events[Math.floor(Math.random() * events.length)];
      if (a !== b && Math.abs(a.year - b.year) >= 3) return Math.random() < .5 ? [a, b] : [b, a];
    }
    return [events[0], events[1]];
  }
  function ask() {
    if (round >= ROUNDS) return done();
    const [a, b] = pair();
    const opt = (e, k) => `<button class="event-choice" data-k="${k}">${e.thumb ? `<img src="${esc(e.thumb)}" alt="" loading="lazy">` : ''}<div class="grow"><span class="yr">${e.year < 0 ? -e.year + ' BC' : e.year}</span>${esc(e.text)}</div></button>`;
    view.innerHTML = `<div class="row"><h1 class="grow" style="margin:0">Time Machine</h1><span class="pill">${round + 1}/${ROUNDS}</span></div>
      <p class="muted">On <b>${dateLabel}</b>… which of these happened <b>first</b>?</p>
      ${opt(a, 0)}<div class="vs">or</div>${opt(b, 1)}<div id="after"></div>`;
    const btns = [...view.querySelectorAll('.event-choice')];
    btns.forEach((btn) => (btn.onclick = () => {
      if (btns[0].classList.contains('shown')) return;
      const pickEarlier = +btn.dataset.k === 0 ? a.year <= b.year : b.year <= a.year;
      const earlierIdx = a.year <= b.year ? 0 : 1;
      btns.forEach((x) => x.classList.add('shown'));
      btns[earlierIdx].classList.add('right');
      if (!pickEarlier) btn.classList.add('wrong');
      if (pickEarlier) { score++; addXp(8); } else addXp(2);
      const pages = [a, b].flatMap((e) => (e.page ? [e.page] : []));
      view.querySelector('#after').innerHTML = `
        <p><b>${pickEarlier ? '✓ Correct!' : '✗ Not this time.'}</b> They're ${Math.abs(a.year - b.year)} years apart.</p>
        <div class="row" style="flex-wrap:wrap">${pages.map((p) => `<a class="btn small" target="_blank" rel="noopener" href="${esc(p.url)}">${esc(p.title)} ↗</a>`).join('')}</div>
        <button class="btn primary block" style="margin-top:12px" id="nx">${round + 1 < ROUNDS ? 'Next →' : 'Results'}</button>`;
      view.querySelector('#nx').onclick = () => { round++; ask(); };
    }));
  }
  function done() {
    view.innerHTML = `<div class="card" style="text-align:center"><div class="muted small">Time Machine · ${dateLabel}</div><div class="summary-score">${score}/${ROUNDS}</div>
      <p>${score >= 6 ? 'You really know your timeline! 🕰️' : 'History is full of surprises. 📜'}</p>
      <div class="row"><button class="btn grow" id="other">🎲 Random date</button><button class="btn primary grow" id="again">Play again</button></div></div>`;
    view.querySelector('#again').onclick = () => { round = 0; score = 0; ask(); };
    view.querySelector('#other').onclick = () => { day = new Date(2024, Math.floor(Math.random() * 12), 1 + Math.floor(Math.random() * 28)); load(day); };
  }
  load(day);
}

function renderRabbitHole() {
  const queue = [];
  let current = null, alive = true, count = 0;
  cleanup = () => { alive = false; };
  async function fill() {
    while (alive && queue.length < 3) {
      try { const a = await Wiki.randomArticle(); if (a) queue.push(a); } catch { break; }
    }
  }
  async function show() {
    if (!queue.length) {
      view.innerHTML = `<h1>Rabbit Hole</h1><div class="card article"><div class="skeleton" style="height:200px;margin-bottom:12px"></div><div class="skeleton" style="height:24px;width:60%;margin-bottom:10px"></div><div class="skeleton" style="height:70px"></div></div>`;
      await fill();
      if (!alive) return;
      if (!queue.length) {
        view.innerHTML = `<h1>Rabbit Hole</h1><div class="card empty"><div class="big">📡</div><p>Couldn't reach Wikipedia. Check your connection and try again.</p><button class="btn primary" id="retry">Retry</button></div>`;
        view.querySelector('#retry').onclick = show;
        return;
      }
    }
    current = queue.shift();
    fill();
    const sv = saved.some((s) => s.type === 'wiki' && s.title === current.title);
    view.innerHTML = `<div class="row"><h1 class="grow" style="margin:0">Rabbit Hole</h1><span class="pill">🕳️ ${count}</span></div>
      <p class="muted small">A random article from Wikipedia's millions. Tap next to go deeper.</p>
      <div class="card article pop">
        ${current.thumb ? `<img class="hero" src="${esc(current.thumb)}" alt="">` : ''}
        <h2>${esc(current.title)}</h2>
        ${current.description ? `<div class="desc">${esc(current.description)}</div>` : ''}
        <p>${esc(current.extract)}</p>
        <div class="row" style="flex-wrap:wrap">
          <a class="btn" href="${esc(current.url)}" target="_blank" rel="noopener">Read full article ↗</a>
          <button class="btn" id="sv">${sv ? '★ Saved' : '☆ Save'}</button>
        </div>
      </div>
      <button class="btn primary block" id="next">Next rabbit hole →</button>`;
    view.querySelector('#next').onclick = () => { count++; profile.wiki++; addXp(2); show(); };
    view.querySelector('#sv').onclick = (e) => {
      const has = saved.some((s) => s.type === 'wiki' && s.title === current.title);
      saved = has ? saved.filter((s) => !(s.type === 'wiki' && s.title === current.title)) : [{ type: 'wiki', ...current, at: Date.now() }, ...saved];
      store.set('saved', saved);
      e.target.textContent = has ? '☆ Save' : '★ Saved';
    };
  }
  show();
}

// ------------------------------------------------------------ me
function renderMe() {
  const lvl = levelOf(profile.xp);
  const vals = Object.values(answers);
  const answered = vals.length;
  const ok = vals.reduce((s, a) => s + a.ok, 0), all = vals.reduce((s, a) => s + a.ok + a.bad, 0);
  const home = profile.home ? COUNTRY[profile.home] : null;
  const stamps = DATA.countries.filter((c) => { const s = countryStats(c.code); return s.total && s.seen === s.total; }).length;
  view.innerHTML = `
    <div class="card" style="text-align:center">
      <div style="font-size:3rem">${home ? flag(home.code) : '🌐'}</div>
      <h1 style="margin:4px 0 0">${titleOf(lvl)}</h1>
      <p class="muted" style="margin:0">Level ${lvl} · ${profile.xp} XP${home ? ' · from ' + esc(home.name) : ''}</p>
    </div>
    <div class="stats3">
      <div class="stat"><b>${answered}</b><span>facts discovered</span></div>
      <div class="stat"><b>${all ? Math.round((ok / all) * 100) : 0}%</b><span>accuracy</span></div>
      <div class="stat"><b>🔥${currentStreak()}</b><span>day streak</span></div>
      <div class="stat"><b>${stamps}</b><span>passport stamps</span></div>
      <div class="stat"><b>${profile.wiki}</b><span>rabbit holes</span></div>
      <div class="stat"><b>${saved.length}</b><span>saved</span></div>
    </div>
    <a class="btn block" style="margin:14px 0" href="#/saved">★ Saved collection</a>
    <div class="card"><b>Knowledge map</b>
      ${DATA.categories.map((c) => { const p = catProgress(c.id); return `<div class="catbar"><span>${c.emoji}</span><div class="bar"><div style="width:${(p.seen / p.total) * 100}%;background:${c.color}"></div></div><span class="small muted">${p.seen}/${p.total}</span></div>`; }).join('')}
    </div>
    <div class="card">
      <div class="row"><b class="grow">Home country</b><button class="btn small" id="homeBtn">${home ? flag(home.code) + ' ' + esc(home.name) : 'Choose'}</button></div>
      <div class="row" style="margin-top:12px"><b class="grow">Theme</b>
        <select class="btn small" id="theme"><option value="auto">System</option><option value="light">Light</option><option value="dark">Dark</option></select></div>
    </div>
    <button class="btn block ghost" id="reset">Reset progress</button>
    <p class="muted small" style="text-align:center">Facts are curated and link to Wikipedia. Live modes use the Wikipedia API (CC BY-SA).</p>`;
  view.querySelector('#homeBtn').onclick = () => onboarding(1);
  const th = view.querySelector('#theme');
  th.value = profile.theme;
  th.onchange = () => { profile.theme = th.value; saveProfile(); applyTheme(); };
  view.querySelector('#reset').onclick = () => showModal(`<h3>Reset all progress?</h3><p class="muted">XP, streak, answers and saved items will be deleted.</p>
    <div class="row"><button class="btn grow" id="no">Cancel</button><button class="btn primary grow" id="yes">Reset</button></div>`, (m) => {
    m.querySelector('#no').onclick = closeModal;
    m.querySelector('#yes').onclick = () => { for (const k of ['answers', 'saved', 'daily', 'profile']) store.set(k, null); location.reload(); };
  });
}

function renderSaved() {
  const items = saved.map((s) => {
    if (s.type === 'fact') {
      const f = DATA.facts.find((x) => x.id === s.id);
      return f ? `<div class="list-item"><span>${CAT[f.c].emoji}</span><div class="grow"><b>${f.a ? 'Fact' : 'Myth'}:</b> ${esc(f.s)}<div class="small muted">${esc(f.e)}</div><a class="small" href="${wikiUrl(f.w)}" target="_blank" rel="noopener">Wikipedia ↗</a></div></div>` : '';
    }
    return `<div class="list-item"><span>🕳️</span><div class="grow"><b>${esc(s.title)}</b><div class="small muted">${esc(s.extract.slice(0, 220))}${s.extract.length > 220 ? '…' : ''}</div><a class="small" href="${esc(s.url)}" target="_blank" rel="noopener">Read ↗</a></div></div>`;
  }).join('');
  view.innerHTML = `<h1>Saved</h1>${items ? `<div class="card">${items}</div>` : '<div class="card empty"><div class="big">☆</div>Tap ☆ on any fact or article to keep it here.</div>'}`;
}

// ------------------------------------------------------------ onboarding
function onboarding(step = 0) {
  const sorted = [...DATA.countries].sort((a, b) => a.name.localeCompare(b.name));
  if (step === 0) {
    showModal(`<div style="font-size:3rem;text-align:center">🧭</div><h2 style="text-align:center">Welcome to curio<span style="color:var(--accent)">.</span></h2>
      <p class="muted" style="text-align:center">The world is full of things you've never heard of: laws, languages, wars, beliefs, inventions and everyday customs. A few minutes a day, one surprising fact at a time.</p>
      <p style="text-align:center"><b>Swipe right for Fact, left for Myth.</b><br><span class="muted small">Every answer comes with the story behind it.</span></p>
      <button class="btn primary block" id="go">Let’s go</button>`, (m) => (m.querySelector('#go').onclick = () => onboarding(1)));
    return;
  }
  if (step === 1) {
    showModal(`<h2>Where are you from?</h2><p class="muted small">We'll show you more facts from <i>other</i> parts of the world, the ones you're least likely to know.</p>
      <input class="search" id="q" placeholder="Search…" style="box-shadow:none;background:var(--surface-2)">
      <div class="onb-list" id="l"></div><button class="btn ghost block" id="skip">Skip</button>`, (m) => {
      const l = m.querySelector('#l');
      const draw = (q = '') => {
        l.innerHTML = sorted.filter((c) => c.name.toLowerCase().includes(q.toLowerCase())).map((c) => `<button class="onb-item ${c.code === profile.home ? 'sel' : ''}" data-c="${c.code}"><span style="font-size:1.4rem">${flag(c.code)}</span>${esc(c.name)}</button>`).join('');
        l.querySelectorAll('.onb-item').forEach((b) => (b.onclick = () => { profile.home = b.dataset.c; saveProfile(); onboarding(profile.interestsDone ? 3 : 2); }));
      };
      m.querySelector('#q').oninput = (e) => draw(e.target.value);
      m.querySelector('#skip').onclick = () => onboarding(profile.interestsDone ? 3 : 2);
      draw();
      m.querySelector('#q').focus();
    });
    return;
  }
  if (step === 2) {
    const sel = new Set(profile.interests);
    showModal(`<h2>What sparks your curiosity?</h2><p class="muted small">Pick a few. You'll still see a bit of everything.</p>
      <div class="interest-grid">${DATA.categories.map((c) => `<button class="interest ${sel.has(c.id) ? 'sel' : ''}" data-c="${c.id}">${c.emoji} ${esc(c.name)}</button>`).join('')}</div>
      <button class="btn primary block" id="done" style="margin-top:14px">Start exploring</button>`, (m) => {
      m.querySelectorAll('.interest').forEach((b) => (b.onclick = () => { sel.has(b.dataset.c) ? sel.delete(b.dataset.c) : sel.add(b.dataset.c); b.classList.toggle('sel'); }));
      m.querySelector('#done').onclick = () => { profile.interests = [...sel]; profile.interestsDone = true; profile.onboarded = true; saveProfile(); closeModal(); route(); };
    });
    return;
  }
  closeModal();
  route();
}

// ------------------------------------------------------------ boot
async function boot() {
  applyTheme();
  view.innerHTML = '<p class="muted" style="text-align:center;margin-top:30vh">Loading…</p>';
  try {
    DATA = await fetch('data/facts.json').then((r) => r.json());
  } catch {
    view.innerHTML = '<div class="card"><b>Could not load facts.</b><p class="muted">Serve this folder over HTTP (for example <code>npx serve facts/web</code>).</p></div>';
    return;
  }
  CAT = Object.fromEntries(DATA.categories.map((c) => [c.id, c]));
  COUNTRY = Object.fromEntries(DATA.countries.map((c) => [c.code, c]));
  route();
  if (!profile.onboarded) onboarding(0);
  if ('serviceWorker' in navigator && location.protocol !== 'file:') navigator.serviceWorker.register('sw.js').catch(() => {});
}
boot();
