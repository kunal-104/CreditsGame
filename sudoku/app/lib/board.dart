import 'package:flutter/material.dart' hide Step;

import 'engine.dart';

class BoardOverlay {
  final List<int>? cand;
  final List<int> unitIds, cells;
  final List<Mark> marks;
  final List<List<int>> places, elims;
  final bool reveal;
  const BoardOverlay({
    this.cand,
    this.unitIds = const [],
    this.cells = const [],
    this.marks = const [],
    this.places = const [],
    this.elims = const [],
    this.reveal = false,
  });

  factory BoardOverlay.fromStep(Step s, List<int>? cand, bool reveal) => BoardOverlay(
      cand: cand, unitIds: s.unitIds, cells: s.cells, marks: s.marks, places: s.places, elims: s.elims, reveal: reveal);
}

class BoardModel {
  final List<int> grid, notes;
  final List<bool> given;
  final int selected;
  final List<int>? solution;
  final bool showMistakes, highlightPeers, highlightSame;
  final BoardOverlay? overlay;
  final Set<int> flash;
  const BoardModel({
    required this.grid,
    required this.notes,
    required this.given,
    this.selected = -1,
    this.solution,
    this.showMistakes = false,
    this.highlightPeers = true,
    this.highlightSame = true,
    this.overlay,
    this.flash = const {},
  });
}

class BoardPalette {
  final Color surface, line, lineStrong, given, entered, peer, same, selected, wrong, wrongBg, unit, pattern, place,
      key, alt, elim, muted;
  const BoardPalette({
    required this.surface,
    required this.line,
    required this.lineStrong,
    required this.given,
    required this.entered,
    required this.peer,
    required this.same,
    required this.selected,
    required this.wrong,
    required this.wrongBg,
    required this.unit,
    required this.pattern,
    required this.place,
    required this.key,
    required this.alt,
    required this.elim,
    required this.muted,
  });

  static BoardPalette of(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return dark
        ? const BoardPalette(
            surface: Color(0xFF181B28),
            line: Color(0xFF2F3450),
            lineStrong: Color(0xFF8B91B5),
            given: Color(0xFFE8EAF4),
            entered: Color(0xFFA5A0FF),
            peer: Color(0xFF1F2236),
            same: Color(0xFF34306B),
            selected: Color(0xFF4A4499),
            wrong: Color(0xFFFF6B7D),
            wrongBg: Color(0xFF3A1B24),
            unit: Color(0xFF2F2A14),
            pattern: Color(0xFF173226),
            place: Color(0xFF1D4A30),
            key: Color(0xFF22C55E),
            alt: Color(0xFF3B82F6),
            elim: Color(0xFFFF6B7D),
            muted: Color(0xFF9AA0BD))
        : const BoardPalette(
            surface: Colors.white,
            line: Color(0xFFD6D9E6),
            lineStrong: Color(0xFF2A2E45),
            given: Color(0xFF1C1F2E),
            entered: Color(0xFF4F46E5),
            peer: Color(0xFFEEF0FB),
            same: Color(0xFFD4D1FB),
            selected: Color(0xFFBDB7FA),
            wrong: Color(0xFFE0364B),
            wrongBg: Color(0xFFFDE8EB),
            unit: Color(0xFFFFF6D6),
            pattern: Color(0xFFE2F5EA),
            place: Color(0xFFBFECCD),
            key: Color(0xFF138A4A),
            alt: Color(0xFF2563EB),
            elim: Color(0xFFE0364B),
            muted: Color(0xFF646A85));
  }
}

class SudokuBoard extends StatelessWidget {
  final BoardModel model;
  final ValueChanged<int>? onTap;
  const SudokuBoard({super.key, required this.model, this.onTap});

  @override
  Widget build(BuildContext context) {
    final pal = BoardPalette.of(context);
    return AspectRatio(
      aspectRatio: 1,
      child: LayoutBuilder(builder: (context, c) {
        final size = c.maxWidth;
        return GestureDetector(
          onTapDown: (d) {
            final cell = size / 9;
            final col = (d.localPosition.dx / cell).floor().clamp(0, 8);
            final row = (d.localPosition.dy / cell).floor().clamp(0, 8);
            onTap?.call(row * 9 + col);
          },
          child: Semantics(
            label: 'Sudoku board',
            child: Container(
              decoration: BoxDecoration(
                color: pal.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: pal.lineStrong, width: 2),
              ),
              clipBehavior: Clip.antiAlias,
              child: CustomPaint(size: Size.square(size), painter: _BoardPainter(model, pal)),
            ),
          ),
        );
      }),
    );
  }
}

class _BoardPainter extends CustomPainter {
  final BoardModel m;
  final BoardPalette p;
  _BoardPainter(this.m, this.p);

  @override
  void paint(Canvas canvas, Size size) {
    final cs = size.width / 9;
    final sel = m.selected;
    final selVal = sel >= 0 ? m.grid[sel] : 0;
    final peerSet = sel >= 0 && m.highlightPeers ? peers[sel].toSet() : <int>{};
    final conflicts = _conflicts(m.grid);
    final ov = m.overlay;
    final unitCells = <int>{};
    if (ov != null) {
      for (final u in ov.unitIds) {
        unitCells.addAll(units[u].cells);
      }
    }
    final reveal = ov?.reveal ?? false;
    final patternCells = reveal ? ov!.cells.toSet() : <int>{};
    final placeMap = {if (reveal) for (final pl in ov!.places) pl[0]: pl[1]};
    final elimSet = {if (reveal) for (final e in ov!.elims) e[0] * 10 + e[1]};
    final markMap = {if (reveal) for (final mk in ov!.marks) mk.cell * 10 + mk.digit: mk.kind};

    final fill = Paint();
    for (var i = 0; i < 81; i++) {
      final v = m.grid[i];
      Color? bg;
      if (sel == i) {
        bg = p.selected;
      } else if (peerSet.contains(i)) {
        bg = p.peer;
      }
      if (v != 0 && selVal != 0 && v == selVal && m.highlightSame && i != sel) bg = p.same;
      final isWrong = v != 0 && !m.given[i] && m.showMistakes && m.solution != null && m.solution![i] != v;
      if (isWrong) bg = p.wrongBg;
      if (unitCells.contains(i)) bg = p.unit;
      if (patternCells.contains(i)) bg = p.pattern;
      if (placeMap.containsKey(i) || m.flash.contains(i)) bg = p.place;
      if (bg != null) {
        canvas.drawRect(Rect.fromLTWH(colOf(i) * cs, rowOf(i) * cs, cs, cs), fill..color = bg);
      }

      final rect = Rect.fromLTWH(colOf(i) * cs, rowOf(i) * cs, cs, cs);
      if (v != 0) {
        final color = isWrong || conflicts.contains(i) ? p.wrong : (m.given[i] ? p.given : p.entered);
        _text(canvas, '$v', rect, cs * 0.6, color, m.given[i] ? FontWeight.w600 : FontWeight.w400);
      } else if (placeMap.containsKey(i)) {
        _text(canvas, '${placeMap[i]}', rect, cs * 0.6, p.key, FontWeight.w800);
      } else {
        final mask = ov?.cand != null ? ov!.cand![i] : m.notes[i];
        if (mask == 0) continue;
        final ns = cs / 3;
        for (var d = 1; d <= 9; d++) {
          if (mask & (1 << d) == 0) continue;
          final r = Rect.fromLTWH(rect.left + ((d - 1) % 3) * ns, rect.top + ((d - 1) ~/ 3) * ns, ns, ns);
          final key = i * 10 + d;
          var color = p.muted;
          var weight = FontWeight.w500;
          if (elimSet.contains(key)) {
            canvas.drawRRect(RRect.fromRectAndRadius(r.deflate(1), const Radius.circular(3)), fill..color = p.wrongBg);
            color = p.elim;
            weight = FontWeight.w800;
            _text(canvas, '$d', r, ns * 0.75, color, weight, strike: true);
            continue;
          } else if (markMap.containsKey(key)) {
            canvas.drawRRect(RRect.fromRectAndRadius(r.deflate(1), const Radius.circular(3)),
                fill..color = markMap[key] == 'key' ? p.key : p.alt);
            color = Colors.white;
            weight = FontWeight.w800;
          } else if (selVal != 0 && d == selVal && m.highlightSame) {
            color = p.entered;
            weight = FontWeight.w900;
          }
          _text(canvas, '$d', r, ns * 0.75, color, weight);
        }
      }
    }

    final thin = Paint()
      ..color = p.line
      ..strokeWidth = 1;
    final thick = Paint()
      ..color = p.lineStrong
      ..strokeWidth = 2;
    for (var k = 1; k < 9; k++) {
      final paint = k % 3 == 0 ? thick : thin;
      canvas.drawLine(Offset(k * cs, 0), Offset(k * cs, size.height), paint);
      canvas.drawLine(Offset(0, k * cs), Offset(size.width, k * cs), paint);
    }
  }

  void _text(Canvas c, String s, Rect r, double fontSize, Color color, FontWeight w, {bool strike = false}) {
    final tp = TextPainter(
      text: TextSpan(
          text: s,
          style: TextStyle(
              fontSize: fontSize,
              color: color,
              fontWeight: w,
              height: 1,
              decoration: strike ? TextDecoration.lineThrough : null,
              decorationColor: color,
              decorationThickness: 2)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(c, Offset(r.left + (r.width - tp.width) / 2, r.top + (r.height - tp.height) / 2));
  }

  static Set<int> _conflicts(List<int> g) {
    final out = <int>{};
    for (final u in units) {
      final seen = <int, int>{};
      for (final c in u.cells) {
        final v = g[c];
        if (v == 0) continue;
        if (seen.containsKey(v)) {
          out
            ..add(c)
            ..add(seen[v]!);
        } else {
          seen[v] = c;
        }
      }
    }
    return out;
  }

  @override
  bool shouldRepaint(covariant _BoardPainter old) => true;
}
