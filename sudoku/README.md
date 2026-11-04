# Sudoku Sensei

Sudoku that teaches. Every hint names the technique, highlights the pattern and explains the logic, and the Academy walks through 24 lessons in 7 stages (Beginner → Grandmaster).

## Features
- **7 difficulty levels**, graded by the hardest human technique each puzzle needs (not by clue count)
- **Step-by-step hints**: first a nudge ("there's an X-Wing in the highlighted area"), then the full explanation with colour-coded candidates, then Apply
- **Academy**: 24 lessons. Each has a real example position where you must find the move, plus practice puzzles that require that technique
- Daily challenge and streak, notes and auto-notes, undo, mistake checking, stats, dark mode, keyboard support, offline

## Techniques (22)
Full House, Hidden Single (box / line), Naked Single, Pointing, Claiming, Naked & Hidden Pairs/Triples, Naked Quad, X-Wing, Skyscraper, 2-String Kite, XY-Wing, XYZ-Wing, Swordfish, Jellyfish, Simple Coloring, Unique Rectangle, BUG+1, XY-Chain.

## How it fits together
- `web/js/engine.js`: the solver, generator and grader (the source of truth). `app/lib/engine.dart` is a Dart port. `app/test/engine_test.dart` checks the port grades the bank exactly like the JS engine and that hints never contradict the solution.
- `tools/build-bank.mjs` generates `bank.json` (1,750 graded puzzles, per-technique practice sets and verified lesson examples) into both `web/data` and `app/assets`. Puzzles are relabelled and shuffled at play time, so each one looks new.

```bash
node sudoku/tools/build-bank.mjs 30000
```

- `web/data/lessons.json` is the Academy curriculum. Copy it to `app/assets/lessons.json` after editing.
