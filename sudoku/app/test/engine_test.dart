import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:sudoku_sensei/engine.dart';

void main() {
  final bank = jsonDecode(File('assets/bank.json').readAsStringSync()) as Map<String, dynamic>;
  final levelsMap = bank['levels'] as Map<String, dynamic>;

  test('Dart solver grades bank puzzles exactly like the JS generator', () {
    for (final entry in levelsMap.entries) {
      final lvl = int.parse(entry.key);
      final list = entry.value as List;
      for (final p in list.take(40)) {
        final grid = parseGrid(p[0] as String);
        final res = logicalSolve(grid);
        expect(res.solved, isTrue, reason: 'unsolved ${p[0]}');
        expect(res.level, lvl, reason: 'level mismatch ${p[0]}');
      }
    }
  });

  test('hints never contradict the solution, even on transformed puzzles', () {
    final rng = Random(1);
    for (final entry in levelsMap.entries) {
      for (final p in (entry.value as List).take(8)) {
        final t = transformPuzzle(p[0] as String, p[1] as String, rng);
        final sol = parseGrid(t.solution);
        final grid = parseGrid(t.puzzle);
        var guard = 0;
        while (grid.contains(0) && guard++ < 200) {
          final h = computeHint(grid, sol);
          expect(h.kind, 'steps');
          for (final hs in h.steps) {
            for (final e in hs.step.elims) {
              expect(sol[e[0]] != e[1], isTrue);
            }
            for (final pl in hs.step.places) {
              expect(sol[pl[0]], pl[1]);
              grid[pl[0]] = pl[1];
            }
          }
        }
        expect(grid.join(), sol.join());
      }
    }
  });

  test('lesson examples deserialize', () {
    final ex = bank['examples'] as Map<String, dynamic>;
    for (final list in ex.values) {
      for (final e in list as List) {
        Step.fromJson((e as Map<String, dynamic>)['step'] as Map<String, dynamic>);
      }
    }
  });
}
