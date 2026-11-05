import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:blockora/logic.dart';

// Expected values produced by the JS engine (blocks/web/js/logic.js) so the
// Daily Challenge is identical on web and in the app.
const parity = r'''{"1":["l4c,dot,c3c",356,"j4d,i3,j4b"],"7":["dot,i2,plus",254,"c3c,c3d,l4c"],"123456":["o3,t4c,d2b",284,"c3c,o2,r32"],"4294967295":["z4b,i3v,j4c",317,"c3a,i3v,c3b"]}''';

void main() {
  test('same seeds produce the same games as the JS engine', () {
    final exp = jsonDecode(parity) as Map<String, dynamic>;
    for (final e in exp.entries) {
      final g = Game(seed: int.parse(e.key));
      final seq = <Object>[g.tray.join(',')];
      for (var m = 0; m < 30 && !g.over; m++) {
        var done = false;
        for (var k = 0; k < 3 && !done; k++) {
          if (g.tray[k] == null) continue;
          for (var r = 0; r < 9 && !done; r++) {
            for (var c = 0; c < 9 && !done; c++) {
              if (g.canPlace(k, r, c)) {
                g.place(k, r, c);
                done = true;
              }
            }
          }
        }
      }
      seq..add(g.score)..add(g.tray.map((t) => t ?? '').join(','));
      expect(seq, e.value, reason: 'seed ${e.key}');
    }
  });

  test('bot games keep every invariant', () {
    final rnd = Random(3);
    for (var gi = 0; gi < 300; gi++) {
      final g = Game(seed: gi + 1);
      var guard = 0;
      while (!g.over && guard++ < 3000) {
        final moves = <(int, int, int)>[];
        for (var k = 0; k < 3; k++) {
          for (var r = 0; r < 9; r++) {
            for (var c = 0; c < 9; c++) {
              if (g.canPlace(k, r, c)) moves.add((k, r, c));
            }
          }
        }
        expect(moves, isNotEmpty);
        final (k, r, c) = moves[rnd.nextInt(moves.length)];
        final before = g.score, filled = g.board.where((v) => v != 0).length, size = g.shape(k)!.cells.length;
        final res = g.place(k, r, c)!;
        expect(g.score, greaterThan(before));
        expect(g.board.where((v) => v != 0).length, filled + size - res.cleared.length);
        expect(findClears(g.board).lines, 0);
        expect(g.over, !g.tray.any((t) => t != null && fitsAnywhere(g.board, shapeByName[t]!)));
      }
      expect(g.place(0, 0, 0), isNull);
      final copy = Game.fromJson(jsonDecode(jsonEncode(g.toJson())) as Map<String, dynamic>);
      expect(copy.score, g.score);
      expect(copy.board, g.board);
    }
  });

  test('clears rows, columns and boxes together', () {
    final b = emptyBoard();
    for (var c = 0; c < n; c++) {
      b[4 * n + c] = 1;
    }
    for (var r = 0; r < n; r++) {
      b[r * n + 2] = 1;
    }
    for (var r = 6; r < 9; r++) {
      for (var c = 6; c < 9; c++) {
        b[r * n + c] = 1;
      }
    }
    final cl = findClears(b);
    expect(cl.rows, [4]);
    expect(cl.cols, [2]);
    expect(cl.boxes, [8]);
    expect(cl.cells.length, 26);
  });
}
