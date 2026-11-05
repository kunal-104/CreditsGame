// Plays thousands of games with a simple bot and checks game invariants.
//   node blocks/tools/test-logic.mjs
import assert from 'node:assert/strict';
import { Game, SHAPE, SHAPES, N, findClears, fitsAnywhere, canPlace, emptyBoard, scoreFor } from '../web/js/logic.js';

// shapes are well-formed and unique
const keys = new Set();
for (const s of SHAPES) {
  assert.ok(s.cells.length > 0 && s.cells.every(([r, c]) => r < s.h && c < s.w), s.name);
  const k = s.cells.map((x) => x.join(',')).sort().join(';');
  assert.ok(!keys.has(k), 'duplicate shape ' + s.name);
  keys.add(k);
}

// clears: row, column, box and overlap
{
  const b = emptyBoard();
  for (let c = 0; c < N; c++) b[4 * N + c] = 1;
  for (let r = 0; r < N; r++) b[r * N + 2] = 1;
  for (let r = 6; r < 9; r++) for (let c = 6; c < 9; c++) b[r * N + c] = 1;
  const cl = findClears(b);
  assert.deepEqual(cl.rows, [4]);
  assert.deepEqual(cl.cols, [2]);
  assert.deepEqual(cl.boxes, [8]);
  assert.equal(cl.cells.size, 9 + 9 - 1 + 9 - 0); // row & col overlap at (4,2); box disjoint
}
assert.equal(scoreFor(4, 0, 0), 4);
assert.equal(scoreFor(3, 1, 1), 21);
assert.ok(scoreFor(3, 2, 1) > 2 * scoreFor(3, 1, 1) - 6);

// persistence round-trip keeps the RNG stream
{
  const a = new Game({ seed: 42 });
  const b = Game.fromJSON(JSON.parse(JSON.stringify(a)));
  assert.deepEqual(a.tray, b.tray);
  assert.equal(a._rng(), b._rng());
}
// same seed -> same game (daily challenge)
assert.deepEqual(new Game({ seed: 7 }).tray, new Game({ seed: 7 }).tray);

let games = 0, totalScore = 0, maxScore = 0, totalMoves = 0;
for (let g = 0; g < 2000; g++) {
  const game = new Game({ seed: g + 1 });
  let guard = 0;
  while (!game.over && guard++ < 5000) {
    // bot: try all moves, prefer most lines cleared, then random
    let best = null;
    for (let i = 0; i < 3; i++) {
      const s = game.shape(i);
      if (!s) continue;
      for (let r = 0; r < N; r++) for (let c = 0; c < N; c++) {
        const p = game.preview(i, r, c);
        if (!p) continue;
        const v = p.clears.lines * 10 + Math.random();
        if (!best || v > best.v) best = { i, r, c, v };
      }
    }
    assert.ok(best, 'game not over but no move exists');
    const before = game.score, filled = game.board.filter(Boolean).length;
    const s = game.shape(best.i);
    const res = game.place(best.i, best.r, best.c);
    assert.ok(res);
    assert.ok(game.score > before);
    assert.equal(game.board.filter(Boolean).length, filled + s.cells.length - res.cleared.length);
    assert.equal(findClears(game.board).lines, 0, 'no full line may remain');
    assert.ok(game.board.every((v) => v >= 0 && v <= 7));
    assert.ok(game.tray.some(Boolean));
    if (game.over) assert.ok(!game.tray.some((t) => t && fitsAnywhere(game.board, SHAPE[t])));
    else assert.ok(game.tray.some((t) => t && fitsAnywhere(game.board, SHAPE[t])));
    if (g % 50 === 0 && game.shuffles && Math.random() < 0.05) { assert.ok(game.shuffle()); assert.equal(game.shuffles, 0); }
  }
  assert.ok(game.over);
  assert.equal(game.place(0, 0, 0), null, 'no moves after game over');
  games++; totalScore += game.score; maxScore = Math.max(maxScore, game.score); totalMoves += game.moves;
}
// canPlace rejects out-of-bounds
assert.equal(canPlace(emptyBoard(), SHAPE.i5, 0, 5), false);
assert.equal(canPlace(emptyBoard(), SHAPE.i5, 0, 4), true);
console.log(`OK: ${games} bot games, avg score ${(totalScore / games) | 0}, max ${maxScore}, avg moves ${(totalMoves / games) | 0}`);
