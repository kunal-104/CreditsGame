// Sudoku engine: board model, brute-force solver, generator and a
// human-style logical solver that explains every step it takes.
// Pure ES module with no DOM access, so it runs in the browser and in Node.

export const ALL = 0x3fe; // bits 1..9

export const rowOf = (i) => (i / 9) | 0;
export const colOf = (i) => i % 9;
export const boxOf = (i) => ((rowOf(i) / 3) | 0) * 3 + ((colOf(i) / 3) | 0);
export const bit = (d) => 1 << d;

const POP = new Uint8Array(1024);
for (let m = 1; m < 1024; m++) POP[m] = POP[m >> 1] + (m & 1);
export const popcount = (m) => POP[m];

export function digitsOf(mask) {
  const out = [];
  for (let d = 1; d <= 9; d++) if (mask & (1 << d)) out.push(d);
  return out;
}

// 27 units: rows 0-8, columns 9-17, boxes 18-26.
export const UNITS = [];
for (let r = 0; r < 9; r++) UNITS.push({ type: 'row', index: r, cells: [...Array(9)].map((_, c) => r * 9 + c) });
for (let c = 0; c < 9; c++) UNITS.push({ type: 'column', index: c, cells: [...Array(9)].map((_, r) => r * 9 + c) });
for (let b = 0; b < 9; b++) {
  const cells = [];
  const r0 = ((b / 3) | 0) * 3, c0 = (b % 3) * 3;
  for (let r = 0; r < 3; r++) for (let c = 0; c < 3; c++) cells.push((r0 + r) * 9 + c0 + c);
  UNITS.push({ type: 'box', index: b, cells });
}
export const CELL_UNITS = [...Array(81)].map((_, i) => [rowOf(i), 9 + colOf(i), 18 + boxOf(i)]);
export const PEERS = [...Array(81)].map((_, i) => {
  const s = new Set();
  for (const u of CELL_UNITS[i]) for (const c of UNITS[u].cells) if (c !== i) s.add(c);
  return [...s];
});
const PEER_SET = PEERS.map((p) => new Set(p));
export const sees = (a, b) => a !== b && PEER_SET[a].has(b);

export const cellName = (i) => `R${rowOf(i) + 1}C${colOf(i) + 1}`;
export const unitName = (u) => `${UNITS[u].type} ${UNITS[u].index + 1}`;
const cap = (s) => s[0].toUpperCase() + s.slice(1);
const list = (arr) => (arr.length <= 1 ? arr.join('') : arr.slice(0, -1).join(', ') + ' and ' + arr[arr.length - 1]);
const cellsTxt = (cells) => list(cells.map(cellName));

// ---------- parsing ----------
export function parse(str) {
  const g = new Array(81).fill(0);
  for (let i = 0; i < 81; i++) {
    const ch = str[i];
    g[i] = ch >= '1' && ch <= '9' ? +ch : 0;
  }
  return g;
}
export const stringify = (g) => g.map((d) => (d ? String(d) : '.')).join('');

// ---------- random ----------
export function mulberry32(seed) {
  let a = seed >>> 0;
  return function () {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
export function shuffle(arr, rng) {
  for (let i = arr.length - 1; i > 0; i--) {
    const j = Math.floor(rng() * (i + 1));
    [arr[i], arr[j]] = [arr[j], arr[i]];
  }
  return arr;
}

// ---------- brute force ----------
// Counts solutions up to `limit`. Returns {count, solution}.
export function bruteForce(grid, limit = 2, rng = null) {
  const g = grid.slice();
  const rows = new Int32Array(9), cols = new Int32Array(9), boxes = new Int32Array(9);
  for (let i = 0; i < 81; i++) {
    const d = g[i];
    if (!d) continue;
    const b = 1 << d, r = rowOf(i), c = colOf(i), x = boxOf(i);
    if (rows[r] & b || cols[c] & b || boxes[x] & b) return { count: 0, solution: null };
    rows[r] |= b; cols[c] |= b; boxes[x] |= b;
  }
  let count = 0, solution = null;
  const rec = () => {
    let best = -1, bestMask = 0, bestCount = 10;
    for (let i = 0; i < 81; i++) {
      if (g[i]) continue;
      const m = ALL & ~(rows[rowOf(i)] | cols[colOf(i)] | boxes[boxOf(i)]);
      const n = POP[m];
      if (n < bestCount) {
        best = i; bestMask = m; bestCount = n;
        if (n <= 1) break;
      }
    }
    if (best < 0) {
      count++;
      if (!solution) solution = g.slice();
      return;
    }
    if (bestCount === 0) return;
    let ds = digitsOf(bestMask);
    if (rng) shuffle(ds, rng);
    const r = rowOf(best), c = colOf(best), x = boxOf(best);
    for (const d of ds) {
      const b = 1 << d;
      g[best] = d; rows[r] |= b; cols[c] |= b; boxes[x] |= b;
      rec();
      g[best] = 0; rows[r] &= ~b; cols[c] &= ~b; boxes[x] &= ~b;
      if (count >= limit) return;
    }
  };
  rec();
  return { count, solution };
}

export const hasUniqueSolution = (g) => bruteForce(g, 2).count === 1;

export function randomSolution(rng) {
  return bruteForce(new Array(81).fill(0), 1, rng).solution;
}

// ---------- logical solver state ----------
export function makeState(grid) {
  const g = grid.slice();
  const cand = new Array(81).fill(0);
  for (let i = 0; i < 81; i++) {
    if (g[i]) continue;
    let m = ALL;
    for (const p of PEERS[i]) if (g[p]) m &= ~(1 << g[p]);
    cand[i] = m;
  }
  return { grid: g, cand };
}
export const cloneState = (s) => ({ grid: s.grid.slice(), cand: s.cand.slice() });

export function applyStep(s, step) {
  for (const [c, d] of step.places) {
    s.grid[c] = d;
    s.cand[c] = 0;
    for (const p of PEERS[c]) s.cand[p] &= ~(1 << d);
  }
  for (const [c, d] of step.elims) s.cand[c] &= ~(1 << d);
}

// Cells in unit u that still have digit d as a candidate.
const where = (s, u, d) => UNITS[u].cells.filter((c) => s.cand[c] & (1 << d));
const unitHas = (s, u, d) => UNITS[u].cells.some((c) => s.grid[c] === d);

function combos(arr, k, start = 0, acc = [], out = []) {
  if (acc.length === k) { out.push(acc.slice()); return out; }
  for (let i = start; i < arr.length; i++) {
    acc.push(arr[i]); combos(arr, k, i + 1, acc, out); acc.pop();
  }
  return out;
}

// ---------- technique catalogue ----------
export const TECHNIQUES = {
  full_house: { name: 'Full House', level: 1 },
  hidden_single_box: { name: 'Hidden Single (Box)', level: 1 },
  hidden_single_line: { name: 'Hidden Single (Row/Column)', level: 2 },
  naked_single: { name: 'Naked Single', level: 2 },
  pointing: { name: 'Pointing Pair/Triple', level: 3 },
  claiming: { name: 'Box/Line Claiming', level: 3 },
  naked_pair: { name: 'Naked Pair', level: 4 },
  hidden_pair: { name: 'Hidden Pair', level: 4 },
  naked_triple: { name: 'Naked Triple', level: 4 },
  hidden_triple: { name: 'Hidden Triple', level: 4 },
  x_wing: { name: 'X-Wing', level: 5 },
  skyscraper: { name: 'Skyscraper', level: 5 },
  two_string_kite: { name: '2-String Kite', level: 5 },
  xy_wing: { name: 'XY-Wing', level: 5 },
  naked_quad: { name: 'Naked Quad', level: 5 },
  xyz_wing: { name: 'XYZ-Wing', level: 6 },
  swordfish: { name: 'Swordfish', level: 6 },
  simple_coloring: { name: 'Simple Coloring', level: 6 },
  unique_rectangle: { name: 'Unique Rectangle', level: 6 },
  bug_plus_one: { name: 'BUG+1', level: 6 },
  xy_chain: { name: 'XY-Chain', level: 7 },
  jellyfish: { name: 'Jellyfish', level: 7 },
};

export const LEVELS = [
  null,
  { id: 1, name: 'Beginner', color: '#2fb380' },
  { id: 2, name: 'Easy', color: '#4caf50' },
  { id: 3, name: 'Medium', color: '#e0a400' },
  { id: 4, name: 'Hard', color: '#f07b2a' },
  { id: 5, name: 'Expert', color: '#e04848' },
  { id: 6, name: 'Master', color: '#a24ad8' },
  { id: 7, name: 'Grandmaster', color: '#3a3ad8' },
];

function mkStep(tech, o) {
  return {
    tech,
    places: o.places || [],
    elims: o.elims || [],
    cells: o.cells || [], // pattern cells
    units: o.units || [], // highlighted units
    marks: o.marks || [], // [cell, digit, 'key' | 'alt']
    text: o.text,
  };
}

// ---------- techniques ----------
function fullHouse(s) {
  for (let u = 0; u < 27; u++) {
    const empty = UNITS[u].cells.filter((c) => !s.grid[c]);
    if (empty.length !== 1) continue;
    const c = empty[0];
    const ds = digitsOf(s.cand[c]);
    if (ds.length !== 1) continue;
    const d = ds[0];
    return mkStep('full_house', {
      places: [[c, d]], units: [u], cells: [c],
      text: `${cap(unitName(u))} has only one empty cell left, ${cellName(c)}. The only digit missing from the ${UNITS[u].type} is ${d}, so ${cellName(c)} = ${d}.`,
    });
  }
  return null;
}

function hiddenSingle(s, kinds, tech) {
  for (const u of kinds) {
    for (let d = 1; d <= 9; d++) {
      if (unitHas(s, u, d)) continue;
      const w = where(s, u, d);
      if (w.length !== 1) continue;
      const c = w[0];
      return mkStep(tech, {
        places: [[c, d]], units: [u], cells: [c], marks: [[c, d, 'key']],
        text: `In ${unitName(u)}, the digit ${d} can only go in one place: ${cellName(c)}. Every other empty cell of the ${UNITS[u].type} already sees a ${d} in its row, column or box. So ${cellName(c)} = ${d}.`,
      });
    }
  }
  return null;
}
const BOX_UNITS = [...Array(9)].map((_, i) => 18 + i);
const LINE_UNITS = [...Array(18)].map((_, i) => i);

function nakedSingle(s) {
  for (let c = 0; c < 81; c++) {
    if (s.grid[c] || popcount(s.cand[c]) !== 1) continue;
    const d = digitsOf(s.cand[c])[0];
    return mkStep('naked_single', {
      places: [[c, d]], cells: [c], units: CELL_UNITS[c], marks: [[c, d, 'key']],
      text: `Look at ${cellName(c)}: its row, column and box already contain every digit except ${d}. With only one candidate left, ${cellName(c)} = ${d}.`,
    });
  }
  return null;
}

function pointing(s) {
  for (let b = 0; b < 9; b++) {
    const u = 18 + b;
    for (let d = 1; d <= 9; d++) {
      const w = where(s, u, d);
      if (w.length < 2 || w.length > 3) continue;
      for (const [lineKind, lineIdx] of [[0, rowOf], [9, colOf]]) {
        const l0 = lineIdx(w[0]);
        if (!w.every((c) => lineIdx(c) === l0)) continue;
        const line = lineKind + l0;
        const elims = UNITS[line].cells.filter((c) => boxOf(c) !== b && s.cand[c] & bit(d)).map((c) => [c, d]);
        if (!elims.length) continue;
        return mkStep('pointing', {
          elims, cells: w, units: [u, line], marks: w.map((c) => [c, d, 'key']),
          text: `In box ${b + 1}, the digit ${d} can only go in ${cellsTxt(w)}, which all lie in ${unitName(line)}. Whichever of them gets the ${d}, ${unitName(line)} gets its ${d} inside box ${b + 1}. So ${d} can be removed from the rest of ${unitName(line)}: ${cellsTxt(elims.map((e) => e[0]))}.`,
        });
      }
    }
  }
  return null;
}

function claiming(s) {
  for (let line = 0; line < 18; line++) {
    for (let d = 1; d <= 9; d++) {
      const w = where(s, line, d);
      if (w.length < 2 || w.length > 3) continue;
      const b = boxOf(w[0]);
      if (!w.every((c) => boxOf(c) === b)) continue;
      const u = 18 + b;
      const elims = UNITS[u].cells.filter((c) => !w.includes(c) && s.cand[c] & bit(d)).map((c) => [c, d]);
      if (!elims.length) continue;
      return mkStep('claiming', {
        elims, cells: w, units: [line, u], marks: w.map((c) => [c, d, 'key']),
        text: `In ${unitName(line)}, the digit ${d} can only go in ${cellsTxt(w)}, all inside box ${b + 1}. The ${UNITS[line].type} must place its ${d} in box ${b + 1}, so no other cell of box ${b + 1} can be ${d}. Remove ${d} from ${cellsTxt(elims.map((e) => e[0]))}.`,
      });
    }
  }
  return null;
}

const SUBSET_NAME = { 2: 'pair', 3: 'triple', 4: 'quad' };
function nakedSubset(s, n, tech) {
  for (let u = 0; u < 27; u++) {
    const cells = UNITS[u].cells.filter((c) => !s.grid[c] && popcount(s.cand[c]) >= 2 && popcount(s.cand[c]) <= n);
    if (cells.length < n) continue;
    for (const combo of combos(cells, n)) {
      let m = 0;
      for (const c of combo) m |= s.cand[c];
      if (popcount(m) !== n) continue;
      const ds = digitsOf(m);
      const elims = [];
      for (const c of UNITS[u].cells) {
        if (combo.includes(c) || s.grid[c]) continue;
        for (const d of ds) if (s.cand[c] & bit(d)) elims.push([c, d]);
      }
      if (!elims.length) continue;
      const marks = [];
      for (const c of combo) for (const d of digitsOf(s.cand[c])) marks.push([c, d, 'key']);
      return mkStep(tech, {
        elims, cells: combo, units: [u], marks,
        text: `In ${unitName(u)}, the ${n} cells ${cellsTxt(combo)} together contain only the ${n} candidates ${list(ds.map(String))}. These ${n} digits must fill these ${n} cells (a naked ${SUBSET_NAME[n]}), so they cannot appear anywhere else in the ${UNITS[u].type}. Remove them from ${cellsTxt([...new Set(elims.map((e) => e[0]))])}.`,
      });
    }
  }
  return null;
}

function hiddenSubset(s, n, tech) {
  for (let u = 0; u < 27; u++) {
    const ds = [];
    for (let d = 1; d <= 9; d++) {
      if (unitHas(s, u, d)) continue;
      const k = where(s, u, d).length;
      if (k >= 1 && k <= n) ds.push(d);
    }
    if (ds.length < n) continue;
    for (const combo of combos(ds, n)) {
      const cellSet = new Set();
      for (const d of combo) for (const c of where(s, u, d)) cellSet.add(c);
      if (cellSet.size !== n) continue;
      const cells = [...cellSet].sort((a, b) => a - b);
      const keep = combo.reduce((m, d) => m | bit(d), 0);
      const elims = [];
      for (const c of cells) for (const d of digitsOf(s.cand[c] & ~keep)) elims.push([c, d]);
      if (!elims.length) continue;
      const marks = [];
      for (const c of cells) for (const d of combo) if (s.cand[c] & bit(d)) marks.push([c, d, 'key']);
      return mkStep(tech, {
        elims, cells, units: [u], marks,
        text: `In ${unitName(u)}, the digits ${list(combo.map(String))} can only go in the ${n} cells ${cellsTxt(cells)} (a hidden ${SUBSET_NAME[n]}). Those cells must hold exactly these digits, so every other candidate in them can be removed.`,
      });
    }
  }
  return null;
}

const FISH = { 2: 'X-Wing', 3: 'Swordfish', 4: 'Jellyfish' };
function fish(s, n, tech) {
  for (let d = 1; d <= 9; d++) {
    for (const baseRows of [true, false]) {
      // positions per base line as a 9-bit mask over the cover lines
      const bases = [];
      for (let l = 0; l < 9; l++) {
        const u = baseRows ? l : 9 + l;
        if (unitHas(s, u, d)) continue;
        const w = where(s, u, d);
        if (w.length < 2 || w.length > n) continue;
        let m = 0;
        for (const c of w) m |= 1 << (baseRows ? colOf(c) : rowOf(c));
        bases.push({ l, m, w });
      }
      if (bases.length < n) continue;
      for (const combo of combos(bases, n)) {
        let m = 0;
        for (const b of combo) m |= b.m;
        if (popcount(m) !== n) continue;
        const baseIdx = new Set(combo.map((b) => b.l));
        const elims = [];
        const coverUnits = [];
        for (let x = 0; x < 9; x++) {
          if (!(m & (1 << x))) continue;
          const cu = baseRows ? 9 + x : x;
          coverUnits.push(cu);
          for (const c of UNITS[cu].cells) {
            const bl = baseRows ? rowOf(c) : colOf(c);
            if (!baseIdx.has(bl) && s.cand[c] & bit(d)) elims.push([c, d]);
          }
        }
        if (!elims.length) continue;
        const cells = combo.flatMap((b) => b.w);
        const baseUnits = combo.map((b) => (baseRows ? b.l : 9 + b.l));
        const bt = baseRows ? 'rows' : 'columns', ct = baseRows ? 'columns' : 'rows';
        return mkStep(tech, {
          elims, cells, units: baseUnits, marks: cells.map((c) => [c, d, 'key']),
          text: `${FISH[n]} on ${d}: in ${bt} ${list(combo.map((b) => String(b.l + 1)))}, the digit ${d} can only go in ${ct} ${list(coverUnits.map((cu) => String(UNITS[cu].index + 1)))}. These ${n} ${bt} need ${n} ${d}s and they must take up all ${n} of those ${ct}, so no other cell in those ${ct} can be ${d}. Remove ${d} from ${cellsTxt(elims.map((e) => e[0]))}.`,
        });
      }
    }
  }
  return null;
}

// conjugate pairs for digit d: units where d appears exactly twice
function strongLinks(s, d) {
  const links = [];
  for (let u = 0; u < 27; u++) {
    if (unitHas(s, u, d)) continue;
    const w = where(s, u, d);
    if (w.length === 2) links.push({ u, a: w[0], b: w[1] });
  }
  return links;
}

function skyscraper(s) {
  for (let d = 1; d <= 9; d++) {
    for (const rowsBase of [true, false]) {
      const lines = [];
      for (let l = 0; l < 9; l++) {
        const u = rowsBase ? l : 9 + l;
        if (unitHas(s, u, d)) continue;
        const w = where(s, u, d);
        if (w.length === 2) lines.push({ u, w });
      }
      const cross = rowsBase ? colOf : rowOf;
      for (let i = 0; i < lines.length; i++) {
        for (let j = i + 1; j < lines.length; j++) {
          const A = lines[i].w, B = lines[j].w;
          for (let ai = 0; ai < 2; ai++) for (let bi = 0; bi < 2; bi++) {
            if (cross(A[ai]) !== cross(B[bi])) continue;
            const ta = A[1 - ai], tb = B[1 - bi];
            if (cross(ta) === cross(tb)) continue; // that would be an X-Wing
            const elims = [];
            for (let c = 0; c < 81; c++) {
              if (c === ta || c === tb || !(s.cand[c] & bit(d))) continue;
              if (sees(c, ta) && sees(c, tb)) elims.push([c, d]);
            }
            if (!elims.length) continue;
            const cells = [A[ai], B[bi], ta, tb];
            const lt = rowsBase ? 'row' : 'column';
            return mkStep('skyscraper', {
              elims, cells, units: [lines[i].u, lines[j].u],
              marks: [[A[ai], d, 'alt'], [B[bi], d, 'alt'], [ta, d, 'key'], [tb, d, 'key']],
              text: `Skyscraper on ${d}: ${cap(unitName(lines[i].u))} and ${unitName(lines[j].u)} each have exactly two places for ${d}. Their bases ${cellName(A[ai])} and ${cellName(B[bi])} line up, and at most one of the bases can be ${d}. So at least one of the tops, ${cellName(ta)} or ${cellName(tb)}, must be ${d}. Any cell that sees both tops cannot be ${d}: remove it from ${cellsTxt(elims.map((e) => e[0]))}.`,
            });
          }
        }
      }
    }
  }
  return null;
}

function twoStringKite(s) {
  for (let d = 1; d <= 9; d++) {
    const rowPairs = [], colPairs = [];
    for (let l = 0; l < 9; l++) {
      if (!unitHas(s, l, d)) { const w = where(s, l, d); if (w.length === 2) rowPairs.push({ u: l, w }); }
      if (!unitHas(s, 9 + l, d)) { const w = where(s, 9 + l, d); if (w.length === 2) colPairs.push({ u: 9 + l, w }); }
    }
    for (const R of rowPairs) for (const C of colPairs) {
      for (let ri = 0; ri < 2; ri++) for (let ci = 0; ci < 2; ci++) {
        const rb = R.w[ri], cb = C.w[ci];
        const re = R.w[1 - ri], ce = C.w[1 - ci];
        if (rb === cb || re === ce || rb === ce || cb === re) continue;
        if (boxOf(rb) !== boxOf(cb)) continue;
        if (boxOf(re) === boxOf(rb) || boxOf(ce) === boxOf(cb)) continue;
        const target = rowOf(ce) * 9 + colOf(re);
        if (!(s.cand[target] & bit(d)) || target === re || target === ce) continue;
        return mkStep('two_string_kite', {
          elims: [[target, d]], cells: [rb, cb, re, ce], units: [R.u, C.u, 18 + boxOf(rb)],
          marks: [[rb, d, 'alt'], [cb, d, 'alt'], [re, d, 'key'], [ce, d, 'key']],
          text: `2-String Kite on ${d}: ${unitName(R.u)} has ${d} only in ${cellName(rb)} and ${cellName(re)}, and ${unitName(C.u)} has ${d} only in ${cellName(cb)} and ${cellName(ce)}. ${cellName(rb)} and ${cellName(cb)} share box ${boxOf(rb) + 1}, so at most one of them is ${d}. That means ${cellName(re)} or ${cellName(ce)} must be ${d}. ${cellName(target)} sees both, so it cannot be ${d}.`,
        });
      }
    }
  }
  return null;
}

function xyWing(s) {
  const biv = [];
  for (let c = 0; c < 81; c++) if (!s.grid[c] && popcount(s.cand[c]) === 2) biv.push(c);
  for (const p of biv) {
    const [x, y] = digitsOf(s.cand[p]);
    const wings = biv.filter((c) => sees(c, p) && c !== p);
    for (const a of wings) {
      if (!(s.cand[a] & bit(x)) || s.cand[a] & bit(y)) continue;
      const z = digitsOf(s.cand[a] & ~bit(x))[0];
      for (const b of wings) {
        if (b === a || s.cand[b] !== (bit(y) | bit(z))) continue;
        const elims = [];
        for (let c = 0; c < 81; c++) {
          if (c === a || c === b || c === p || !(s.cand[c] & bit(z))) continue;
          if (sees(c, a) && sees(c, b)) elims.push([c, z]);
        }
        if (!elims.length) continue;
        return mkStep('xy_wing', {
          elims, cells: [p, a, b],
          marks: [[p, x, 'alt'], [p, y, 'alt'], [a, x, 'alt'], [b, y, 'alt'], [a, z, 'key'], [b, z, 'key']],
          text: `XY-Wing: the pivot ${cellName(p)} is ${x} or ${y}. If it is ${x}, then ${cellName(a)} (${x}/${z}) must be ${z}. If it is ${y}, then ${cellName(b)} (${y}/${z}) must be ${z}. Either way one of the two wings is ${z}, so any cell that sees both wings cannot be ${z}: remove ${z} from ${cellsTxt(elims.map((e) => e[0]))}.`,
        });
      }
    }
  }
  return null;
}

function xyzWing(s) {
  for (let p = 0; p < 81; p++) {
    if (s.grid[p] || popcount(s.cand[p]) !== 3) continue;
    const pm = s.cand[p];
    const wings = PEERS[p].filter((c) => !s.grid[c] && popcount(s.cand[c]) === 2 && (s.cand[c] & pm) === s.cand[c]);
    for (let i = 0; i < wings.length; i++) for (let j = i + 1; j < wings.length; j++) {
      const a = wings[i], b = wings[j];
      if (s.cand[a] === s.cand[b]) continue;
      const zMask = s.cand[a] & s.cand[b];
      if (popcount(zMask) !== 1) continue;
      const z = digitsOf(zMask)[0];
      const elims = [];
      for (let c = 0; c < 81; c++) {
        if (c === a || c === b || c === p || !(s.cand[c] & zMask)) continue;
        if (sees(c, a) && sees(c, b) && sees(c, p)) elims.push([c, z]);
      }
      if (!elims.length) continue;
      return mkStep('xyz_wing', {
        elims, cells: [p, a, b], marks: [[p, z, 'key'], [a, z, 'key'], [b, z, 'key']],
        text: `XYZ-Wing: the pivot ${cellName(p)} has candidates ${list(digitsOf(pm).map(String))}, and the wings ${cellName(a)} and ${cellName(b)} each share two of them. Whatever the pivot turns out to be, one of these three cells must be ${z}. A cell that sees all three cannot be ${z}: remove it from ${cellsTxt(elims.map((e) => e[0]))}.`,
      });
    }
  }
  return null;
}

function simpleColoring(s) {
  for (let d = 1; d <= 9; d++) {
    const links = strongLinks(s, d);
    const adj = new Map();
    for (const { a, b } of links) {
      if (!adj.has(a)) adj.set(a, new Set());
      if (!adj.has(b)) adj.set(b, new Set());
      adj.get(a).add(b); adj.get(b).add(a);
    }
    const color = new Map();
    for (const start of adj.keys()) {
      if (color.has(start)) continue;
      const comp = [];
      color.set(start, 0);
      const queue = [start];
      while (queue.length) {
        const c = queue.shift();
        comp.push(c);
        for (const n of adj.get(c)) if (!color.has(n)) { color.set(n, 1 - color.get(c)); queue.push(n); }
      }
      if (comp.length < 4) continue;
      const groups = [comp.filter((c) => color.get(c) === 0), comp.filter((c) => color.get(c) === 1)];
      const marks = comp.map((c) => [c, d, color.get(c) === 0 ? 'key' : 'alt']);
      // Color wrap: two cells of the same colour see each other -> that colour is false.
      for (let k = 0; k < 2; k++) {
        const g = groups[k];
        let clash = null;
        for (let i = 0; i < g.length && !clash; i++) for (let j = i + 1; j < g.length; j++) if (sees(g[i], g[j])) { clash = [g[i], g[j]]; break; }
        if (!clash) continue;
        return mkStep('simple_coloring', {
          elims: g.map((c) => [c, d]), cells: comp, marks,
          text: `Simple Coloring on ${d}: link the cells where ${d} has exactly two places in a unit and colour them alternately. Exactly one colour is true. ${cellName(clash[0])} and ${cellName(clash[1])} have the same colour but see each other, so they cannot both be ${d}. That colour must be false: remove ${d} from every cell of that colour.`,
        });
      }
      // Color trap: an outside cell that sees both colours.
      const elims = [];
      for (let c = 0; c < 81; c++) {
        if (color.has(c) && comp.includes(c)) continue;
        if (!(s.cand[c] & bit(d))) continue;
        if (groups[0].some((x) => sees(c, x)) && groups[1].some((x) => sees(c, x))) elims.push([c, d]);
      }
      if (elims.length) {
        return mkStep('simple_coloring', {
          elims, cells: comp, marks,
          text: `Simple Coloring on ${d}: link the cells where ${d} has exactly two places in a unit and colour them alternately (green / blue). One colour holds all the true ${d}s. ${cellsTxt(elims.map((e) => e[0]))} ${elims.length > 1 ? 'each see' : 'sees'} a green cell and a blue cell, so whichever colour is true, ${elims.length > 1 ? 'they' : 'it'} cannot be ${d}.`,
        });
      }
    }
  }
  return null;
}

function uniqueRectangle(s) {
  for (let r1 = 0; r1 < 9; r1++) for (let r2 = r1 + 1; r2 < 9; r2++) {
    for (let c1 = 0; c1 < 9; c1++) for (let c2 = c1 + 1; c2 < 9; c2++) {
      const cells = [r1 * 9 + c1, r1 * 9 + c2, r2 * 9 + c1, r2 * 9 + c2];
      if (new Set(cells.map(boxOf)).size !== 2) continue;
      if (cells.some((c) => s.grid[c])) continue;
      const bivs = cells.filter((c) => popcount(s.cand[c]) === 2);
      if (bivs.length !== 3) continue;
      const m = s.cand[bivs[0]];
      if (!bivs.every((c) => s.cand[c] === m)) continue;
      const t = cells.find((c) => !bivs.includes(c));
      if ((s.cand[t] & m) !== m) continue;
      const [a, b] = digitsOf(m);
      return mkStep('unique_rectangle', {
        elims: [[t, a], [t, b]], cells,
        marks: bivs.flatMap((c) => [[c, a, 'alt'], [c, b, 'alt']]),
        text: `Unique Rectangle: ${cellsTxt(bivs)} all contain only ${a}/${b} and form three corners of a rectangle across two boxes. If ${cellName(t)} were also ${a} or ${b}, the ${a}s and ${b}s could be swapped and the puzzle would have two solutions. A proper Sudoku has exactly one, so ${cellName(t)} cannot be ${a} or ${b}.`,
      });
    }
  }
  return null;
}

function bugPlusOne(s) {
  let tri = -1;
  for (let c = 0; c < 81; c++) {
    if (s.grid[c]) continue;
    const n = popcount(s.cand[c]);
    if (n === 2) continue;
    if (n === 3 && tri < 0) { tri = c; continue; }
    return null;
  }
  if (tri < 0) return null;
  for (const d of digitsOf(s.cand[tri])) {
    if (where(s, rowOf(tri), d).length === 3) {
      return mkStep('bug_plus_one', {
        places: [[tri, d]], cells: [tri], units: [rowOf(tri)], marks: [[tri, d, 'key']],
        text: `BUG+1: every unsolved cell has exactly two candidates except ${cellName(tri)}. If all cells were two-candidate cells the puzzle would have two solutions (a "Bivalue Universal Grave"). The extra candidate must be true to avoid that. In ${cellName(tri)}, ${d} appears three times in its row, so it is the extra one: ${cellName(tri)} = ${d}.`,
      });
    }
  }
  return null;
}

function xyChain(s) {
  const biv = [];
  for (let c = 0; c < 81; c++) if (!s.grid[c] && popcount(s.cand[c]) === 2) biv.push(c);
  const bivSet = new Set(biv);
  const nbrs = new Map(biv.map((c) => [c, PEERS[c].filter((p) => bivSet.has(p))]));
  for (let maxLen = 4; maxLen <= 8; maxLen++) {
    for (const start of biv) {
      for (const x of digitsOf(s.cand[start])) {
        const path = [start];
        const used = new Set([start]);
        const found = (function dfs(cell, incoming) {
          // cell's value if the previous link forces it: the other digit
          const out = digitsOf(s.cand[cell] & ~bit(incoming))[0];
          if (path.length >= 3 && out === x && path.length === maxLen) {
            const elims = [];
            for (let c = 0; c < 81; c++) {
              if (used.has(c) || !(s.cand[c] & bit(x))) continue;
              if (sees(c, start) && sees(c, cell)) elims.push([c, x]);
            }
            if (elims.length) return elims;
          }
          if (path.length >= maxLen) return null;
          for (const n of nbrs.get(cell)) {
            if (used.has(n) || !(s.cand[n] & bit(out))) continue;
            path.push(n); used.add(n);
            const r = dfs(n, out);
            if (r) return r;
            path.pop(); used.delete(n);
          }
          return null;
        })(start, x);
        if (found) {
          const end = path[path.length - 1];
          const marks = [];
          let inc = x;
          for (const c of path) {
            const o = digitsOf(s.cand[c] & ~bit(inc))[0];
            marks.push([c, inc, 'alt'], [c, o, 'key']);
            inc = o;
          }
          return mkStep('xy_chain', {
            elims: found, cells: path.slice(), marks,
            text: `XY-Chain on ${x}: follow the chain of two-candidate cells ${path.map(cellName).join(' → ')}. If ${cellName(start)} is not ${x}, each link forces the next cell, and the chain ends with ${cellName(end)} = ${x}. So either the start or the end of the chain is ${x}. Any cell that sees both ends cannot be ${x}: remove it from ${cellsTxt(found.map((e) => e[0]))}.`,
          });
        }
      }
    }
  }
  return null;
}

// Ordered from simplest to hardest. The hint system always reports the simplest step available.
export const STRATEGIES = [
  ['full_house', fullHouse],
  ['hidden_single_box', (s) => hiddenSingle(s, BOX_UNITS, 'hidden_single_box')],
  ['hidden_single_line', (s) => hiddenSingle(s, LINE_UNITS, 'hidden_single_line')],
  ['naked_single', nakedSingle],
  ['pointing', pointing],
  ['claiming', claiming],
  ['naked_pair', (s) => nakedSubset(s, 2, 'naked_pair')],
  ['hidden_pair', (s) => hiddenSubset(s, 2, 'hidden_pair')],
  ['naked_triple', (s) => nakedSubset(s, 3, 'naked_triple')],
  ['hidden_triple', (s) => hiddenSubset(s, 3, 'hidden_triple')],
  ['x_wing', (s) => fish(s, 2, 'x_wing')],
  ['skyscraper', skyscraper],
  ['two_string_kite', twoStringKite],
  ['xy_wing', xyWing],
  ['naked_quad', (s) => nakedSubset(s, 4, 'naked_quad')],
  ['xyz_wing', xyzWing],
  ['swordfish', (s) => fish(s, 3, 'swordfish')],
  ['simple_coloring', simpleColoring],
  ['unique_rectangle', uniqueRectangle],
  ['bug_plus_one', bugPlusOne],
  ['xy_chain', xyChain],
  ['jellyfish', (s) => fish(s, 4, 'jellyfish')],
];

export function findStep(state, maxLevel = 99) {
  for (const [id, fn] of STRATEGIES) {
    if (TECHNIQUES[id].level > maxLevel) continue;
    const step = fn(state);
    if (step) return step;
  }
  return null;
}

const isSolved = (s) => s.grid.every((d) => d);

// Solve with logic only. Returns {solved, steps, level, techniques:{id:count}}.
export function logicalSolve(grid, { record = false, maxLevel = 99 } = {}) {
  const s = makeState(grid);
  const steps = [];
  const used = {};
  let level = 0;
  while (!isSolved(s)) {
    const step = findStep(s, maxLevel);
    if (!step) return { solved: false, steps, level, techniques: used, state: s };
    used[step.tech] = (used[step.tech] || 0) + 1;
    level = Math.max(level, TECHNIQUES[step.tech].level);
    if (record) steps.push({ step, before: cloneState(s) });
    applyStep(s, step);
  }
  return { solved: true, steps, level, techniques: used, state: s };
}

// Next hint for a player's board. `grid` is the board as the player has it
// (givens + entries), `solution` the known solution.
// Returns {kind:'mistake', cells} | {kind:'steps', steps:[{step, state}]} | {kind:'solved'} | {kind:'stuck'}.
export function hint(grid, solution) {
  const wrong = [];
  for (let i = 0; i < 81; i++) if (grid[i] && grid[i] !== solution[i]) wrong.push(i);
  if (wrong.length) return { kind: 'mistake', cells: wrong };
  const s = makeState(grid);
  if (isSolved(s)) return { kind: 'solved' };
  const steps = [];
  // Walk forward through elimination-only steps until a placement is found.
  for (let guard = 0; guard < 40; guard++) {
    const step = findStep(s);
    if (!step) break;
    steps.push({ step, state: cloneState(s) });
    if (step.places.length) return { kind: 'steps', steps };
    applyStep(s, step);
  }
  if (steps.length) return { kind: 'steps', steps };
  return { kind: 'stuck' };
}

// ---------- transforms (make each bank puzzle feel brand new) ----------
// Applies a random validity- and difficulty-preserving transformation to puzzle and solution strings.
export function transform(puzzle, solution, rng) {
  const digits = shuffle([1, 2, 3, 4, 5, 6, 7, 8, 9], rng);
  const bands = shuffle([0, 1, 2], rng), stacks = shuffle([0, 1, 2], rng);
  const rowMap = [], colMap = [];
  for (const b of bands) for (const r of shuffle([0, 1, 2], rng)) rowMap.push(b * 3 + r);
  for (const b of stacks) for (const c of shuffle([0, 1, 2], rng)) colMap.push(b * 3 + c);
  const flip = rng() < 0.5;
  const map = (str) => {
    let out = '';
    for (let r = 0; r < 9; r++) for (let c = 0; c < 9; c++) {
      let sr = rowMap[r], sc = colMap[c];
      if (flip) [sr, sc] = [sc, sr];
      const ch = str[sr * 9 + sc];
      out += ch >= '1' && ch <= '9' ? String(digits[+ch - 1]) : '.';
    }
    return out;
  };
  return { puzzle: map(puzzle), solution: map(solution) };
}

// ---------- generator ----------
// Generates puzzles and yields each one at the point it reaches a new difficulty level.
export function* generateLadder(rng) {
  const sol = randomSolution(rng);
  const g = sol.slice();
  const order = shuffle([...Array(41)].map((_, i) => i), rng); // symmetric pairs i <-> 80-i
  let lastLevel = 0;
  let lastGood = null;
  for (const i of order) {
    const j = 80 - i;
    const keep = [g[i], g[j]];
    g[i] = 0; g[j] = 0;
    if (!hasUniqueSolution(g)) { g[i] = keep[0]; g[j] = keep[1]; continue; }
    const res = logicalSolve(g);
    if (!res.solved) { g[i] = keep[0]; g[j] = keep[1]; continue; }
    if (res.level > lastLevel && lastGood) yield lastGood;
    lastLevel = res.level;
    lastGood = { puzzle: stringify(g), solution: sol.join(''), level: res.level, techniques: res.techniques, clues: g.filter(Boolean).length };
  }
  if (lastGood) yield lastGood;
}
