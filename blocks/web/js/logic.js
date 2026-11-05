// Blockora game logic: 9x9 board, three pieces per tray, clear full rows,
// columns and 3x3 boxes. Pure module: no DOM, runs in browser and Node.

export const N = 9;

// Shapes drawn with '#'. Each entry: [name, colorIndex, weight, ...rows]
const DEFS = [
  ['dot', 1, 3, '#'],
  ['i2', 2, 4, '##'], ['i2v', 2, 4, '#', '#'],
  ['i3', 3, 4, '###'], ['i3v', 3, 4, '#', '#', '#'],
  ['i4', 4, 3, '####'], ['i4v', 4, 3, '#', '#', '#', '#'],
  ['i5', 5, 2, '#####'], ['i5v', 5, 2, '#', '#', '#', '#', '#'],
  ['o2', 6, 4, '##', '##'],
  ['o3', 7, 1.5, '###', '###', '###'],
  ['r23', 6, 2, '###', '###'], ['r32', 6, 2, '##', '##', '##'],
  ['c3a', 1, 3, '##', '#.'], ['c3b', 1, 3, '##', '.#'], ['c3c', 1, 3, '#.', '##'], ['c3d', 1, 3, '.#', '##'],
  ['l4a', 2, 2, '#.', '#.', '##'], ['l4b', 2, 2, '###', '#..'], ['l4c', 2, 2, '##', '.#', '.#'], ['l4d', 2, 2, '..#', '###'],
  ['j4a', 3, 2, '.#', '.#', '##'], ['j4b', 3, 2, '#..', '###'], ['j4c', 3, 2, '##', '#.', '#.'], ['j4d', 3, 2, '###', '..#'],
  ['t4a', 4, 2, '###', '.#.'], ['t4b', 4, 2, '.#', '##', '.#'], ['t4c', 4, 2, '.#.', '###'], ['t4d', 4, 2, '#.', '##', '#.'],
  ['s4a', 5, 1.5, '.##', '##.'], ['s4b', 5, 1.5, '#.', '##', '.#'],
  ['z4a', 7, 1.5, '##.', '.##'], ['z4b', 7, 1.5, '.#', '##', '#.'],
  ['v5a', 5, 1.5, '#..', '#..', '###'], ['v5b', 5, 1.5, '###', '#..', '#..'], ['v5c', 5, 1.5, '###', '..#', '..#'], ['v5d', 5, 1.5, '..#', '..#', '###'],
  ['plus', 4, 1, '.#.', '###', '.#.'],
  ['d2a', 3, 1, '#.', '.#'], ['d2b', 3, 1, '.#', '#.'],
];

export const SHAPES = DEFS.map(([name, color, weight, ...rows]) => {
  const cells = [];
  rows.forEach((row, r) => [...row].forEach((ch, c) => { if (ch === '#') cells.push([r, c]); }));
  return { name, color, weight, cells, h: rows.length, w: Math.max(...rows.map((x) => x.length)) };
});
export const SHAPE = Object.fromEntries(SHAPES.map((s) => [s.name, s]));

export function mulberry32(seed) {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

export const emptyBoard = () => new Array(N * N).fill(0);

export function canPlace(board, shape, r, c) {
  for (const [dr, dc] of shape.cells) {
    const rr = r + dr, cc = c + dc;
    if (rr < 0 || cc < 0 || rr >= N || cc >= N) return false;
    if (board[rr * N + cc]) return false;
  }
  return true;
}

export function fitsAnywhere(board, shape) {
  for (let r = 0; r <= N - shape.h; r++) for (let c = 0; c <= N - shape.w; c++) if (canPlace(board, shape, r, c)) return true;
  return false;
}

// Lines (rows, columns, boxes) that are completely filled.
export function findClears(board) {
  const rows = [], cols = [], boxes = [];
  for (let i = 0; i < N; i++) {
    let rf = true, cf = true, bf = true;
    const br = Math.floor(i / 3) * 3, bc = (i % 3) * 3;
    for (let j = 0; j < N; j++) {
      if (!board[i * N + j]) rf = false;
      if (!board[j * N + i]) cf = false;
      if (!board[(br + Math.floor(j / 3)) * N + bc + (j % 3)]) bf = false;
    }
    if (rf) rows.push(i);
    if (cf) cols.push(i);
    if (bf) boxes.push(i);
  }
  const cells = new Set();
  for (const r of rows) for (let j = 0; j < N; j++) cells.add(r * N + j);
  for (const c of cols) for (let j = 0; j < N; j++) cells.add(j * N + c);
  for (const b of boxes) {
    const br = Math.floor(b / 3) * 3, bc = (b % 3) * 3;
    for (let j = 0; j < N; j++) cells.add((br + Math.floor(j / 3)) * N + bc + (j % 3));
  }
  return { rows, cols, boxes, lines: rows.length + cols.length + boxes.length, cells };
}

// Points for one placement.
export function scoreFor(placed, lines, combo) {
  if (!lines) return placed;
  const base = lines * 18 + (lines - 1) * lines * 9; // multi-line bonus grows quadratically
  return placed + base + (combo - 1) * 10 * lines;
}

export const PRAISE = ['', 'Nice!', 'Great!', 'Amazing!', 'Incredible!', 'Unstoppable!'];

function pickShape(rng, board) {
  // Fewer empty cells -> slightly favour small pieces so the game stays fair.
  const empty = board.filter((v) => !v).length;
  const crowd = 1 - empty / (N * N);
  let total = 0;
  const ws = SHAPES.map((s) => {
    const w = s.weight * (s.cells.length <= 3 ? 1 + crowd : s.cells.length >= 5 ? 1 - crowd * 0.6 : 1);
    total += w;
    return w;
  });
  let x = rng() * total;
  for (let i = 0; i < SHAPES.length; i++) { x -= ws[i]; if (x <= 0) return SHAPES[i]; }
  return SHAPES[0];
}

export function makeTray(rng, board) {
  let tray = null;
  for (let attempt = 0; attempt < 25; attempt++) {
    tray = [pickShape(rng, board), pickShape(rng, board), pickShape(rng, board)];
    if (tray.some((s) => fitsAnywhere(board, s))) break;
  }
  return tray.map((s) => s.name);
}

export class Game {
  constructor({ seed = (Math.random() * 2 ** 32) >>> 0, mode = 'classic' } = {}) {
    this.seed = seed;
    this.mode = mode;
    this.rngState = seed;
    this.board = emptyBoard();
    this.score = 0;
    this.combo = 0; // consecutive placements that cleared something
    this.bestCombo = 0;
    this.lines = 0;
    this.moves = 0;
    this.shuffles = 1;
    this.over = false;
    this.tray = this._tray();
  }

  _rng() {
    // persistable RNG: keep state on the instance
    const r = mulberry32(this.rngState);
    const v = r();
    this.rngState = (this.rngState + 0x6d2b79f5) >>> 0;
    return v;
  }

  _tray() { return makeTray(() => this._rng(), this.board); }

  shape(i) { return this.tray[i] ? SHAPE[this.tray[i]] : null; }

  canPlace(i, r, c) { const s = this.shape(i); return !!s && !this.over && canPlace(this.board, s, r, c); }

  // Board as it would look after placing (for previews), plus what would clear.
  preview(i, r, c) {
    const s = this.shape(i);
    if (!s || !canPlace(this.board, s, r, c)) return null;
    const b = this.board.slice();
    for (const [dr, dc] of s.cells) b[(r + dr) * N + c + dc] = s.color;
    return { cells: s.cells.map(([dr, dc]) => (r + dr) * N + c + dc), clears: findClears(b) };
  }

  place(i, r, c) {
    const s = this.shape(i);
    if (!s || this.over || !canPlace(this.board, s, r, c)) return null;
    const placed = s.cells.map(([dr, dc]) => (r + dr) * N + c + dc);
    for (const p of placed) this.board[p] = s.color;
    const cl = findClears(this.board);
    if (cl.lines) {
      this.combo++;
      this.bestCombo = Math.max(this.bestCombo, this.combo);
    } else this.combo = 0;
    const points = scoreFor(s.cells.length, cl.lines, Math.max(1, this.combo));
    for (const p of cl.cells) this.board[p] = 0;
    this.score += points;
    this.lines += cl.lines;
    this.moves++;
    this.tray[i] = null;
    let refilled = false;
    if (this.tray.every((t) => !t)) { this.tray = this._tray(); refilled = true; }
    this.over = !this.tray.some((t) => t && fitsAnywhere(this.board, SHAPE[t]));
    return { placed, cleared: [...cl.cells], lines: cl.lines, points, combo: this.combo, refilled, over: this.over, clears: cl };
  }

  // Replace the remaining pieces with fresh ones (limited power-up).
  shuffle() {
    if (this.shuffles <= 0) return false;
    this.shuffles--;
    const fresh = this._tray();
    this.tray = this.tray.map((t, k) => (t ? fresh[k] : null));
    if (this.tray.every((t) => !t)) this.tray = fresh;
    this.over = !this.tray.some((t) => t && fitsAnywhere(this.board, SHAPE[t]));
    return true;
  }

  toJSON() {
    const { seed, mode, rngState, board, score, combo, bestCombo, lines, moves, shuffles, over, tray } = this;
    return { seed, mode, rngState, board, score, combo, bestCombo, lines, moves, shuffles, over, tray };
  }

  static fromJSON(j) {
    const g = new Game({ seed: j.seed, mode: j.mode });
    Object.assign(g, j);
    g.board = j.board.slice();
    g.tray = j.tray.slice();
    return g;
  }
}
