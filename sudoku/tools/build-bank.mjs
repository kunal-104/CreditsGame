// Builds the puzzle bank shared by the website and the Flutter app.
//   node sudoku/tools/build-bank.mjs [ladders=30000] [seed=2026]
// Output: sudoku/web/data/bank.json and sudoku/app/assets/bank.json
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import * as E from '../web/js/engine.js';

const root = path.dirname(fileURLToPath(import.meta.url));
const LADDERS = +(process.argv[2] || 30000);
const SEED = +(process.argv[3] || 2026);
const PER_LEVEL = 250;
const PER_TECH_PRACTICE = 40;
const EXAMPLES_PER_TECH = 4;

const rng = E.mulberry32(SEED);
const techIds = Object.keys(E.TECHNIQUES);
const byLevel = { 1: [], 2: [], 3: [], 4: [], 5: [], 6: [], 7: [] };
const practice = Object.fromEntries(techIds.map((t) => [t, []]));
const examples = Object.fromEntries(techIds.map((t) => [t, []]));

function verify(step, sol) {
  for (const [c, d] of step.places) if (sol[c] !== d) throw new Error('bad placement ' + step.tech);
  for (const [c, d] of step.elims) if (sol[c] === d) throw new Error('bad elimination ' + step.tech);
}

function collectExamples(p) {
  const need = Object.keys(p.techniques).filter((t) => E.TECHNIQUES[t].level >= 3 && examples[t].length < EXAMPLES_PER_TECH);
  if (!need.length) return;
  const sol = p.solution.split('').map(Number);
  const res = E.logicalSolve(E.parse(p.puzzle), { record: true });
  const seen = new Set();
  for (const { step, before } of res.steps) {
    verify(step, sol);
    if (!need.includes(step.tech) || seen.has(step.tech)) continue;
    seen.add(step.tech);
    // Prefer compact, readable examples.
    if (step.elims.length > 6) continue;
    examples[step.tech].push({
      grid: E.stringify(before.grid),
      cand: before.cand,
      step,
    });
  }
}

// Beginner/Easy examples come from the first steps of easy puzzles.
function collectEasyExamples(p) {
  const need = Object.keys(p.techniques).filter((t) => E.TECHNIQUES[t].level < 3 && examples[t].length < EXAMPLES_PER_TECH);
  if (!need.length) return;
  const res = E.logicalSolve(E.parse(p.puzzle), { record: true });
  // take a step from the middle of the solve so the grid is not too empty
  const mid = res.steps.slice((res.steps.length / 3) | 0);
  for (const t of need) {
    const hit = mid.find((x) => x.step.tech === t);
    if (hit) examples[t].push({ grid: E.stringify(hit.before.grid), cand: hit.before.cand, step: hit.step });
  }
}

const t0 = Date.now();
let count = 0;
for (let k = 0; k < LADDERS; k++) {
  for (const p of E.generateLadder(rng)) {
    count++;
    const list = byLevel[p.level];
    const techIdx = Object.keys(p.techniques).map((t) => techIds.indexOf(t));
    const entry = [p.puzzle, p.solution, techIdx];
    if (list.length < PER_LEVEL) list.push(entry);
    for (const t of Object.keys(p.techniques)) {
      if (E.TECHNIQUES[t].level === p.level && practice[t].length < PER_TECH_PRACTICE) practice[t].push(entry);
    }
    collectEasyExamples(p);
    collectExamples(p);
  }
  if (k % 2000 === 0) process.stdout.write(`\r${k}/${LADDERS} ladders, ${count} puzzles, ${((Date.now() - t0) / 1000) | 0}s   `);
}
console.log();

for (const l of Object.keys(byLevel)) console.log(`level ${l}: ${byLevel[l].length} puzzles`);
for (const t of techIds) console.log(`${t.padEnd(20)} practice ${String(practice[t].length).padStart(3)}  examples ${examples[t].length}`);

const out = {
  version: 1,
  generated: new Date().toISOString().slice(0, 10),
  techniques: techIds,
  levels: byLevel,
  practice: {},
  examples,
};
// practice entries reference puzzles inside levels when possible, otherwise inline them
for (const t of techIds) {
  const lvl = E.TECHNIQUES[t].level;
  out.practice[t] = practice[t].map((e) => {
    const i = byLevel[lvl].indexOf(e);
    return i >= 0 ? i : e;
  });
}

const json = JSON.stringify(out);
for (const dest of ['../web/data/bank.json', '../app/assets/bank.json']) {
  const file = path.join(root, dest);
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, json);
}
console.log(`wrote bank.json (${(json.length / 1024) | 0} KB)`);
