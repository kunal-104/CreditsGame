// Dart port of sudoku/web/js/engine.js: board model and the human-style
// logical solver that powers hints. Keep both files in sync.
import 'dart:math';

const int kAll = 0x3fe;
int rowOf(int i) => i ~/ 9;
int colOf(int i) => i % 9;
int boxOf(int i) => (rowOf(i) ~/ 3) * 3 + colOf(i) ~/ 3;
int bit(int d) => 1 << d;

int popcount(int m) {
  var n = 0;
  while (m != 0) {
    m &= m - 1;
    n++;
  }
  return n;
}

List<int> digitsOf(int mask) => [for (var d = 1; d <= 9; d++) if (mask & (1 << d) != 0) d];

class Unit {
  final String type;
  final int index;
  final List<int> cells;
  const Unit(this.type, this.index, this.cells);
}

final List<Unit> units = () {
  final u = <Unit>[];
  for (var r = 0; r < 9; r++) {
    u.add(Unit('row', r, [for (var c = 0; c < 9; c++) r * 9 + c]));
  }
  for (var c = 0; c < 9; c++) {
    u.add(Unit('column', c, [for (var r = 0; r < 9; r++) r * 9 + c]));
  }
  for (var b = 0; b < 9; b++) {
    final r0 = (b ~/ 3) * 3, c0 = (b % 3) * 3;
    u.add(Unit('box', b, [
      for (var r = 0; r < 3; r++)
        for (var c = 0; c < 3; c++) (r0 + r) * 9 + c0 + c
    ]));
  }
  return u;
}();

final List<List<int>> cellUnits = [for (var i = 0; i < 81; i++) [rowOf(i), 9 + colOf(i), 18 + boxOf(i)]];
final List<List<int>> peers = [
  for (var i = 0; i < 81; i++)
    {
      for (final u in cellUnits[i])
        for (final c in units[u].cells)
          if (c != i) c
    }.toList()
];
final List<Set<int>> _peerSet = [for (final p in peers) p.toSet()];
bool sees(int a, int b) => a != b && _peerSet[a].contains(b);

String cellName(int i) => 'R${rowOf(i) + 1}C${colOf(i) + 1}';
String unitName(int u) => '${units[u].type} ${units[u].index + 1}';
String _cap(String s) => s[0].toUpperCase() + s.substring(1);
String _list(List<String> a) => a.length <= 1 ? a.join() : '${a.sublist(0, a.length - 1).join(', ')} and ${a.last}';
String _cells(Iterable<int> cs) => _list(cs.map(cellName).toList());

List<int> parseGrid(String s) => [
      for (var i = 0; i < 81; i++) (s.codeUnitAt(i) >= 49 && s.codeUnitAt(i) <= 57) ? s.codeUnitAt(i) - 48 : 0
    ];

class Technique {
  final String name;
  final int level;
  const Technique(this.name, this.level);
}

const Map<String, Technique> techniques = {
  'full_house': Technique('Full House', 1),
  'hidden_single_box': Technique('Hidden Single (Box)', 1),
  'hidden_single_line': Technique('Hidden Single (Row/Column)', 2),
  'naked_single': Technique('Naked Single', 2),
  'pointing': Technique('Pointing Pair/Triple', 3),
  'claiming': Technique('Box/Line Claiming', 3),
  'naked_pair': Technique('Naked Pair', 4),
  'hidden_pair': Technique('Hidden Pair', 4),
  'naked_triple': Technique('Naked Triple', 4),
  'hidden_triple': Technique('Hidden Triple', 4),
  'x_wing': Technique('X-Wing', 5),
  'skyscraper': Technique('Skyscraper', 5),
  'two_string_kite': Technique('2-String Kite', 5),
  'xy_wing': Technique('XY-Wing', 5),
  'naked_quad': Technique('Naked Quad', 5),
  'xyz_wing': Technique('XYZ-Wing', 6),
  'swordfish': Technique('Swordfish', 6),
  'simple_coloring': Technique('Simple Coloring', 6),
  'unique_rectangle': Technique('Unique Rectangle', 6),
  'bug_plus_one': Technique('BUG+1', 6),
  'xy_chain': Technique('XY-Chain', 7),
  'jellyfish': Technique('Jellyfish', 7),
  'reveal': Technique('Reveal a Cell', 0),
};

class Level {
  final int id;
  final String name;
  final int color;
  const Level(this.id, this.name, this.color);
}

const List<Level> levels = [
  Level(1, 'Beginner', 0xFF2FB380),
  Level(2, 'Easy', 0xFF4CAF50),
  Level(3, 'Medium', 0xFFE0A400),
  Level(4, 'Hard', 0xFFF07B2A),
  Level(5, 'Expert', 0xFFE04848),
  Level(6, 'Master', 0xFFA24AD8),
  Level(7, 'Grandmaster', 0xFF3A3AD8),
];
Level levelInfo(int id) => levels[id - 1];

/// A mark on a candidate: kind is 'key' or 'alt'.
class Mark {
  final int cell, digit;
  final String kind;
  const Mark(this.cell, this.digit, this.kind);
}

class Step {
  final String tech;
  final List<List<int>> places; // [cell, digit]
  final List<List<int>> elims; // [cell, digit]
  final List<int> cells;
  final List<int> unitIds;
  final List<Mark> marks;
  final String text;
  Step(this.tech,
      {this.places = const [],
      this.elims = const [],
      this.cells = const [],
      this.unitIds = const [],
      this.marks = const [],
      required this.text});

  factory Step.fromJson(Map<String, dynamic> j) => Step(
        j['tech'] as String,
        places: [for (final p in j['places'] as List) List<int>.from(p as List)],
        elims: [for (final p in j['elims'] as List) List<int>.from(p as List)],
        cells: List<int>.from(j['cells'] as List),
        unitIds: List<int>.from(j['units'] as List),
        marks: [for (final m in j['marks'] as List) Mark(m[0] as int, m[1] as int, m[2] as String)],
        text: j['text'] as String,
      );
}

class SolverState {
  final List<int> grid;
  final List<int> cand;
  SolverState(this.grid, this.cand);
  SolverState clone() => SolverState(List.of(grid), List.of(cand));
  bool get solved => !grid.contains(0);
}

SolverState makeState(List<int> grid) {
  final g = List<int>.of(grid);
  final cand = List<int>.filled(81, 0);
  for (var i = 0; i < 81; i++) {
    if (g[i] != 0) continue;
    var m = kAll;
    for (final p in peers[i]) {
      if (g[p] != 0) m &= ~(1 << g[p]);
    }
    cand[i] = m;
  }
  return SolverState(g, cand);
}

void applyStep(SolverState s, Step step) {
  for (final p in step.places) {
    final c = p[0], d = p[1];
    s.grid[c] = d;
    s.cand[c] = 0;
    for (final q in peers[c]) {
      s.cand[q] &= ~(1 << d);
    }
  }
  for (final e in step.elims) {
    s.cand[e[0]] &= ~(1 << e[1]);
  }
}

List<int> _where(SolverState s, int u, int d) => [for (final c in units[u].cells) if (s.cand[c] & (1 << d) != 0) c];
bool _unitHas(SolverState s, int u, int d) => units[u].cells.any((c) => s.grid[c] == d);

List<List<T>> _combos<T>(List<T> arr, int k) {
  final out = <List<T>>[];
  void rec(int start, List<T> acc) {
    if (acc.length == k) {
      out.add(List.of(acc));
      return;
    }
    for (var i = start; i < arr.length; i++) {
      acc.add(arr[i]);
      rec(i + 1, acc);
      acc.removeLast();
    }
  }

  rec(0, []);
  return out;
}

// ---------------- techniques ----------------
Step? _fullHouse(SolverState s) {
  for (var u = 0; u < 27; u++) {
    final empty = units[u].cells.where((c) => s.grid[c] == 0).toList();
    if (empty.length != 1) continue;
    final c = empty[0];
    final ds = digitsOf(s.cand[c]);
    if (ds.length != 1) continue;
    final d = ds[0];
    return Step('full_house',
        places: [
          [c, d]
        ],
        unitIds: [u],
        cells: [c],
        text:
            '${_cap(unitName(u))} has only one empty cell left, ${cellName(c)}. The only digit missing from the ${units[u].type} is $d, so ${cellName(c)} = $d.');
  }
  return null;
}

final _boxUnits = [for (var i = 0; i < 9; i++) 18 + i];
final _lineUnits = [for (var i = 0; i < 18; i++) i];

Step? _hiddenSingle(SolverState s, List<int> kinds, String tech) {
  for (final u in kinds) {
    for (var d = 1; d <= 9; d++) {
      if (_unitHas(s, u, d)) continue;
      final w = _where(s, u, d);
      if (w.length != 1) continue;
      final c = w[0];
      return Step(tech,
          places: [
            [c, d]
          ],
          unitIds: [u],
          cells: [c],
          marks: [Mark(c, d, 'key')],
          text:
              'In ${unitName(u)}, the digit $d can only go in one place: ${cellName(c)}. Every other empty cell of the ${units[u].type} already sees a $d in its row, column or box. So ${cellName(c)} = $d.');
    }
  }
  return null;
}

Step? _nakedSingle(SolverState s) {
  for (var c = 0; c < 81; c++) {
    if (s.grid[c] != 0 || popcount(s.cand[c]) != 1) continue;
    final d = digitsOf(s.cand[c])[0];
    return Step('naked_single',
        places: [
          [c, d]
        ],
        cells: [c],
        unitIds: cellUnits[c],
        marks: [Mark(c, d, 'key')],
        text:
            'Look at ${cellName(c)}: its row, column and box already contain every digit except $d. With only one candidate left, ${cellName(c)} = $d.');
  }
  return null;
}

Step? _pointing(SolverState s) {
  for (var b = 0; b < 9; b++) {
    final u = 18 + b;
    for (var d = 1; d <= 9; d++) {
      final w = _where(s, u, d);
      if (w.length < 2 || w.length > 3) continue;
      for (final isRow in [true, false]) {
        int idx(int c) => isRow ? rowOf(c) : colOf(c);
        final l0 = idx(w[0]);
        if (!w.every((c) => idx(c) == l0)) continue;
        final line = (isRow ? 0 : 9) + l0;
        final elims = [
          for (final c in units[line].cells)
            if (boxOf(c) != b && s.cand[c] & bit(d) != 0) [c, d]
        ];
        if (elims.isEmpty) continue;
        return Step('pointing',
            elims: elims,
            cells: w,
            unitIds: [u, line],
            marks: [for (final c in w) Mark(c, d, 'key')],
            text:
                'In box ${b + 1}, the digit $d can only go in ${_cells(w)}, which all lie in ${unitName(line)}. Whichever of them gets the $d, ${unitName(line)} gets its $d inside box ${b + 1}. So $d can be removed from the rest of ${unitName(line)}: ${_cells(elims.map((e) => e[0]))}.');
      }
    }
  }
  return null;
}

Step? _claiming(SolverState s) {
  for (var line = 0; line < 18; line++) {
    for (var d = 1; d <= 9; d++) {
      final w = _where(s, line, d);
      if (w.length < 2 || w.length > 3) continue;
      final b = boxOf(w[0]);
      if (!w.every((c) => boxOf(c) == b)) continue;
      final u = 18 + b;
      final elims = [
        for (final c in units[u].cells)
          if (!w.contains(c) && s.cand[c] & bit(d) != 0) [c, d]
      ];
      if (elims.isEmpty) continue;
      return Step('claiming',
          elims: elims,
          cells: w,
          unitIds: [line, u],
          marks: [for (final c in w) Mark(c, d, 'key')],
          text:
              'In ${unitName(line)}, the digit $d can only go in ${_cells(w)}, all inside box ${b + 1}. The ${units[line].type} must place its $d in box ${b + 1}, so no other cell of box ${b + 1} can be $d. Remove $d from ${_cells(elims.map((e) => e[0]))}.');
    }
  }
  return null;
}

const _subsetName = {2: 'pair', 3: 'triple', 4: 'quad'};

Step? _nakedSubset(SolverState s, int n, String tech) {
  for (var u = 0; u < 27; u++) {
    final cells = [
      for (final c in units[u].cells)
        if (s.grid[c] == 0 && popcount(s.cand[c]) >= 2 && popcount(s.cand[c]) <= n) c
    ];
    if (cells.length < n) continue;
    for (final combo in _combos(cells, n)) {
      var m = 0;
      for (final c in combo) {
        m |= s.cand[c];
      }
      if (popcount(m) != n) continue;
      final ds = digitsOf(m);
      final elims = <List<int>>[];
      for (final c in units[u].cells) {
        if (combo.contains(c) || s.grid[c] != 0) continue;
        for (final d in ds) {
          if (s.cand[c] & bit(d) != 0) elims.add([c, d]);
        }
      }
      if (elims.isEmpty) continue;
      return Step(tech,
          elims: elims,
          cells: combo,
          unitIds: [u],
          marks: [
            for (final c in combo)
              for (final d in digitsOf(s.cand[c])) Mark(c, d, 'key')
          ],
          text:
              'In ${unitName(u)}, the $n cells ${_cells(combo)} together contain only the $n candidates ${_list(ds.map((e) => '$e').toList())}. These $n digits must fill these $n cells (a naked ${_subsetName[n]}), so they cannot appear anywhere else in the ${units[u].type}. Remove them from ${_cells(elims.map((e) => e[0]).toSet())}.');
    }
  }
  return null;
}

Step? _hiddenSubset(SolverState s, int n, String tech) {
  for (var u = 0; u < 27; u++) {
    final ds = <int>[];
    for (var d = 1; d <= 9; d++) {
      if (_unitHas(s, u, d)) continue;
      final k = _where(s, u, d).length;
      if (k >= 1 && k <= n) ds.add(d);
    }
    if (ds.length < n) continue;
    for (final combo in _combos(ds, n)) {
      final cellSet = <int>{};
      for (final d in combo) {
        cellSet.addAll(_where(s, u, d));
      }
      if (cellSet.length != n) continue;
      final cells = cellSet.toList()..sort();
      final keep = combo.fold<int>(0, (m, d) => m | bit(d));
      final elims = [
        for (final c in cells)
          for (final d in digitsOf(s.cand[c] & ~keep)) [c, d]
      ];
      if (elims.isEmpty) continue;
      return Step(tech,
          elims: elims,
          cells: cells,
          unitIds: [u],
          marks: [
            for (final c in cells)
              for (final d in combo)
                if (s.cand[c] & bit(d) != 0) Mark(c, d, 'key')
          ],
          text:
              'In ${unitName(u)}, the digits ${_list(combo.map((e) => '$e').toList())} can only go in the $n cells ${_cells(cells)} (a hidden ${_subsetName[n]}). Those cells must hold exactly these digits, so every other candidate in them can be removed.');
    }
  }
  return null;
}

const _fishName = {2: 'X-Wing', 3: 'Swordfish', 4: 'Jellyfish'};

class _Base {
  final int l, m;
  final List<int> w;
  _Base(this.l, this.m, this.w);
}

Step? _fish(SolverState s, int n, String tech) {
  for (var d = 1; d <= 9; d++) {
    for (final baseRows in [true, false]) {
      final bases = <_Base>[];
      for (var l = 0; l < 9; l++) {
        final u = baseRows ? l : 9 + l;
        if (_unitHas(s, u, d)) continue;
        final w = _where(s, u, d);
        if (w.length < 2 || w.length > n) continue;
        var m = 0;
        for (final c in w) {
          m |= 1 << (baseRows ? colOf(c) : rowOf(c));
        }
        bases.add(_Base(l, m, w));
      }
      if (bases.length < n) continue;
      for (final combo in _combos(bases, n)) {
        var m = 0;
        for (final b in combo) {
          m |= b.m;
        }
        if (popcount(m) != n) continue;
        final baseIdx = combo.map((b) => b.l).toSet();
        final elims = <List<int>>[];
        final cover = <int>[];
        for (var x = 0; x < 9; x++) {
          if (m & (1 << x) == 0) continue;
          final cu = baseRows ? 9 + x : x;
          cover.add(cu);
          for (final c in units[cu].cells) {
            final bl = baseRows ? rowOf(c) : colOf(c);
            if (!baseIdx.contains(bl) && s.cand[c] & bit(d) != 0) elims.add([c, d]);
          }
        }
        if (elims.isEmpty) continue;
        final cells = [for (final b in combo) ...b.w];
        final bt = baseRows ? 'rows' : 'columns', ct = baseRows ? 'columns' : 'rows';
        return Step(tech,
            elims: elims,
            cells: cells,
            unitIds: [for (final b in combo) baseRows ? b.l : 9 + b.l],
            marks: [for (final c in cells) Mark(c, d, 'key')],
            text:
                '${_fishName[n]} on $d: in $bt ${_list(combo.map((b) => '${b.l + 1}').toList())}, the digit $d can only go in $ct ${_list(cover.map((cu) => '${units[cu].index + 1}').toList())}. These $n $bt need $n ${d}s and they must take up all $n of those $ct, so no other cell in those $ct can be $d. Remove $d from ${_cells(elims.map((e) => e[0]))}.');
      }
    }
  }
  return null;
}

Step? _skyscraper(SolverState s) {
  for (var d = 1; d <= 9; d++) {
    for (final rowsBase in [true, false]) {
      final lines = <MapEntry<int, List<int>>>[];
      for (var l = 0; l < 9; l++) {
        final u = rowsBase ? l : 9 + l;
        if (_unitHas(s, u, d)) continue;
        final w = _where(s, u, d);
        if (w.length == 2) lines.add(MapEntry(u, w));
      }
      int cross(int c) => rowsBase ? colOf(c) : rowOf(c);
      for (var i = 0; i < lines.length; i++) {
        for (var j = i + 1; j < lines.length; j++) {
          final a = lines[i].value, b = lines[j].value;
          for (var ai = 0; ai < 2; ai++) {
            for (var bi = 0; bi < 2; bi++) {
              if (cross(a[ai]) != cross(b[bi])) continue;
              final ta = a[1 - ai], tb = b[1 - bi];
              if (cross(ta) == cross(tb)) continue;
              final elims = <List<int>>[];
              for (var c = 0; c < 81; c++) {
                if (c == ta || c == tb || s.cand[c] & bit(d) == 0) continue;
                if (sees(c, ta) && sees(c, tb)) elims.add([c, d]);
              }
              if (elims.isEmpty) continue;
              return Step('skyscraper',
                  elims: elims,
                  cells: [a[ai], b[bi], ta, tb],
                  unitIds: [lines[i].key, lines[j].key],
                  marks: [Mark(a[ai], d, 'alt'), Mark(b[bi], d, 'alt'), Mark(ta, d, 'key'), Mark(tb, d, 'key')],
                  text:
                      'Skyscraper on $d: ${_cap(unitName(lines[i].key))} and ${unitName(lines[j].key)} each have exactly two places for $d. Their bases ${cellName(a[ai])} and ${cellName(b[bi])} line up, and at most one of the bases can be $d. So at least one of the tops, ${cellName(ta)} or ${cellName(tb)}, must be $d. Any cell that sees both tops cannot be $d: remove it from ${_cells(elims.map((e) => e[0]))}.');
            }
          }
        }
      }
    }
  }
  return null;
}

Step? _twoStringKite(SolverState s) {
  for (var d = 1; d <= 9; d++) {
    final rowPairs = <MapEntry<int, List<int>>>[], colPairs = <MapEntry<int, List<int>>>[];
    for (var l = 0; l < 9; l++) {
      if (!_unitHas(s, l, d)) {
        final w = _where(s, l, d);
        if (w.length == 2) rowPairs.add(MapEntry(l, w));
      }
      if (!_unitHas(s, 9 + l, d)) {
        final w = _where(s, 9 + l, d);
        if (w.length == 2) colPairs.add(MapEntry(9 + l, w));
      }
    }
    for (final r in rowPairs) {
      for (final col in colPairs) {
        for (var ri = 0; ri < 2; ri++) {
          for (var ci = 0; ci < 2; ci++) {
            final rb = r.value[ri], cb = col.value[ci];
            final re = r.value[1 - ri], ce = col.value[1 - ci];
            if (rb == cb || re == ce || rb == ce || cb == re) continue;
            if (boxOf(rb) != boxOf(cb)) continue;
            if (boxOf(re) == boxOf(rb) || boxOf(ce) == boxOf(cb)) continue;
            final target = rowOf(ce) * 9 + colOf(re);
            if (s.cand[target] & bit(d) == 0 || target == re || target == ce) continue;
            return Step('two_string_kite',
                elims: [
                  [target, d]
                ],
                cells: [rb, cb, re, ce],
                unitIds: [r.key, col.key, 18 + boxOf(rb)],
                marks: [Mark(rb, d, 'alt'), Mark(cb, d, 'alt'), Mark(re, d, 'key'), Mark(ce, d, 'key')],
                text:
                    '2-String Kite on $d: ${unitName(r.key)} has $d only in ${cellName(rb)} and ${cellName(re)}, and ${unitName(col.key)} has $d only in ${cellName(cb)} and ${cellName(ce)}. ${cellName(rb)} and ${cellName(cb)} share box ${boxOf(rb) + 1}, so at most one of them is $d. That means ${cellName(re)} or ${cellName(ce)} must be $d. ${cellName(target)} sees both, so it cannot be $d.');
          }
        }
      }
    }
  }
  return null;
}

Step? _xyWing(SolverState s) {
  final biv = [for (var c = 0; c < 81; c++) if (s.grid[c] == 0 && popcount(s.cand[c]) == 2) c];
  for (final p in biv) {
    final xy = digitsOf(s.cand[p]);
    final x = xy[0], y = xy[1];
    final wings = biv.where((c) => sees(c, p)).toList();
    for (final a in wings) {
      if (s.cand[a] & bit(x) == 0 || s.cand[a] & bit(y) != 0) continue;
      final z = digitsOf(s.cand[a] & ~bit(x))[0];
      for (final b in wings) {
        if (b == a || s.cand[b] != (bit(y) | bit(z))) continue;
        final elims = <List<int>>[];
        for (var c = 0; c < 81; c++) {
          if (c == a || c == b || c == p || s.cand[c] & bit(z) == 0) continue;
          if (sees(c, a) && sees(c, b)) elims.add([c, z]);
        }
        if (elims.isEmpty) continue;
        return Step('xy_wing',
            elims: elims,
            cells: [p, a, b],
            marks: [
              Mark(p, x, 'alt'),
              Mark(p, y, 'alt'),
              Mark(a, x, 'alt'),
              Mark(b, y, 'alt'),
              Mark(a, z, 'key'),
              Mark(b, z, 'key')
            ],
            text:
                'XY-Wing: the pivot ${cellName(p)} is $x or $y. If it is $x, then ${cellName(a)} ($x/$z) must be $z. If it is $y, then ${cellName(b)} ($y/$z) must be $z. Either way one of the two wings is $z, so any cell that sees both wings cannot be $z: remove $z from ${_cells(elims.map((e) => e[0]))}.');
      }
    }
  }
  return null;
}

Step? _xyzWing(SolverState s) {
  for (var p = 0; p < 81; p++) {
    if (s.grid[p] != 0 || popcount(s.cand[p]) != 3) continue;
    final pm = s.cand[p];
    final wings = [
      for (final c in peers[p])
        if (s.grid[c] == 0 && popcount(s.cand[c]) == 2 && (s.cand[c] & pm) == s.cand[c]) c
    ];
    for (var i = 0; i < wings.length; i++) {
      for (var j = i + 1; j < wings.length; j++) {
        final a = wings[i], b = wings[j];
        if (s.cand[a] == s.cand[b]) continue;
        final zMask = s.cand[a] & s.cand[b];
        if (popcount(zMask) != 1) continue;
        final z = digitsOf(zMask)[0];
        final elims = <List<int>>[];
        for (var c = 0; c < 81; c++) {
          if (c == a || c == b || c == p || s.cand[c] & zMask == 0) continue;
          if (sees(c, a) && sees(c, b) && sees(c, p)) elims.add([c, z]);
        }
        if (elims.isEmpty) continue;
        return Step('xyz_wing',
            elims: elims,
            cells: [p, a, b],
            marks: [Mark(p, z, 'key'), Mark(a, z, 'key'), Mark(b, z, 'key')],
            text:
                'XYZ-Wing: the pivot ${cellName(p)} has candidates ${_list(digitsOf(pm).map((e) => '$e').toList())}, and the wings ${cellName(a)} and ${cellName(b)} each share two of them. Whatever the pivot turns out to be, one of these three cells must be $z. A cell that sees all three cannot be $z: remove it from ${_cells(elims.map((e) => e[0]))}.');
      }
    }
  }
  return null;
}

Step? _simpleColoring(SolverState s) {
  for (var d = 1; d <= 9; d++) {
    final adj = <int, Set<int>>{};
    for (var u = 0; u < 27; u++) {
      if (_unitHas(s, u, d)) continue;
      final w = _where(s, u, d);
      if (w.length != 2) continue;
      adj.putIfAbsent(w[0], () => {}).add(w[1]);
      adj.putIfAbsent(w[1], () => {}).add(w[0]);
    }
    final color = <int, int>{};
    for (final start in adj.keys) {
      if (color.containsKey(start)) continue;
      final comp = <int>[];
      color[start] = 0;
      final queue = [start];
      while (queue.isNotEmpty) {
        final c = queue.removeAt(0);
        comp.add(c);
        for (final n in adj[c]!) {
          if (!color.containsKey(n)) {
            color[n] = 1 - color[c]!;
            queue.add(n);
          }
        }
      }
      if (comp.length < 4) continue;
      final groups = [comp.where((c) => color[c] == 0).toList(), comp.where((c) => color[c] == 1).toList()];
      final marks = [for (final c in comp) Mark(c, d, color[c] == 0 ? 'key' : 'alt')];
      for (var k = 0; k < 2; k++) {
        final g = groups[k];
        List<int>? clash;
        for (var i = 0; i < g.length && clash == null; i++) {
          for (var j = i + 1; j < g.length; j++) {
            if (sees(g[i], g[j])) {
              clash = [g[i], g[j]];
              break;
            }
          }
        }
        if (clash == null) continue;
        return Step('simple_coloring',
            elims: [for (final c in g) [c, d]],
            cells: comp,
            marks: marks,
            text:
                'Simple Coloring on $d: link the cells where $d has exactly two places in a unit and colour them alternately. Exactly one colour is true. ${cellName(clash[0])} and ${cellName(clash[1])} have the same colour but see each other, so they cannot both be $d. That colour must be false: remove $d from every cell of that colour.');
      }
      final elims = <List<int>>[];
      for (var c = 0; c < 81; c++) {
        if (comp.contains(c) || s.cand[c] & bit(d) == 0) continue;
        if (groups[0].any((x) => sees(c, x)) && groups[1].any((x) => sees(c, x))) elims.add([c, d]);
      }
      if (elims.isNotEmpty) {
        final many = elims.length > 1;
        return Step('simple_coloring',
            elims: elims,
            cells: comp,
            marks: marks,
            text:
                'Simple Coloring on $d: link the cells where $d has exactly two places in a unit and colour them alternately (green / blue). One colour holds all the true ${d}s. ${_cells(elims.map((e) => e[0]))} ${many ? 'each see' : 'sees'} a green cell and a blue cell, so whichever colour is true, ${many ? 'they' : 'it'} cannot be $d.');
      }
    }
  }
  return null;
}

Step? _uniqueRectangle(SolverState s) {
  for (var r1 = 0; r1 < 9; r1++) {
    for (var r2 = r1 + 1; r2 < 9; r2++) {
      for (var c1 = 0; c1 < 9; c1++) {
        for (var c2 = c1 + 1; c2 < 9; c2++) {
          final cells = [r1 * 9 + c1, r1 * 9 + c2, r2 * 9 + c1, r2 * 9 + c2];
          if (cells.map(boxOf).toSet().length != 2) continue;
          if (cells.any((c) => s.grid[c] != 0)) continue;
          final bivs = cells.where((c) => popcount(s.cand[c]) == 2).toList();
          if (bivs.length != 3) continue;
          final m = s.cand[bivs[0]];
          if (!bivs.every((c) => s.cand[c] == m)) continue;
          final t = cells.firstWhere((c) => !bivs.contains(c));
          if ((s.cand[t] & m) != m) continue;
          final ab = digitsOf(m);
          final a = ab[0], b = ab[1];
          return Step('unique_rectangle',
              elims: [
                [t, a],
                [t, b]
              ],
              cells: cells,
              marks: [
                for (final c in bivs) ...[Mark(c, a, 'alt'), Mark(c, b, 'alt')]
              ],
              text:
                  'Unique Rectangle: ${_cells(bivs)} all contain only $a/$b and form three corners of a rectangle across two boxes. If ${cellName(t)} were also $a or $b, the ${a}s and ${b}s could be swapped and the puzzle would have two solutions. A proper Sudoku has exactly one, so ${cellName(t)} cannot be $a or $b.');
        }
      }
    }
  }
  return null;
}

Step? _bugPlusOne(SolverState s) {
  var tri = -1;
  for (var c = 0; c < 81; c++) {
    if (s.grid[c] != 0) continue;
    final n = popcount(s.cand[c]);
    if (n == 2) continue;
    if (n == 3 && tri < 0) {
      tri = c;
      continue;
    }
    return null;
  }
  if (tri < 0) return null;
  for (final d in digitsOf(s.cand[tri])) {
    if (_where(s, rowOf(tri), d).length == 3) {
      return Step('bug_plus_one',
          places: [
            [tri, d]
          ],
          cells: [tri],
          unitIds: [rowOf(tri)],
          marks: [Mark(tri, d, 'key')],
          text:
              'BUG+1: every unsolved cell has exactly two candidates except ${cellName(tri)}. If all cells were two-candidate cells the puzzle would have two solutions (a "Bivalue Universal Grave"). The extra candidate must be true to avoid that. In ${cellName(tri)}, $d appears three times in its row, so it is the extra one: ${cellName(tri)} = $d.');
    }
  }
  return null;
}

Step? _xyChain(SolverState s) {
  final biv = [for (var c = 0; c < 81; c++) if (s.grid[c] == 0 && popcount(s.cand[c]) == 2) c];
  final bivSet = biv.toSet();
  final nbrs = {for (final c in biv) c: peers[c].where(bivSet.contains).toList()};
  for (var maxLen = 4; maxLen <= 8; maxLen++) {
    for (final start in biv) {
      for (final x in digitsOf(s.cand[start])) {
        final path = [start];
        final used = {start};
        List<List<int>>? dfs(int cell, int incoming) {
          final out = digitsOf(s.cand[cell] & ~bit(incoming))[0];
          if (path.length >= 3 && out == x && path.length == maxLen) {
            final elims = <List<int>>[];
            for (var c = 0; c < 81; c++) {
              if (used.contains(c) || s.cand[c] & bit(x) == 0) continue;
              if (sees(c, start) && sees(c, cell)) elims.add([c, x]);
            }
            if (elims.isNotEmpty) return elims;
          }
          if (path.length >= maxLen) return null;
          for (final n in nbrs[cell]!) {
            if (used.contains(n) || s.cand[n] & bit(out) == 0) continue;
            path.add(n);
            used.add(n);
            final r = dfs(n, out);
            if (r != null) return r;
            path.removeLast();
            used.remove(n);
          }
          return null;
        }

        final found = dfs(start, x);
        if (found != null) {
          final end = path.last;
          final marks = <Mark>[];
          var inc = x;
          for (final c in path) {
            final o = digitsOf(s.cand[c] & ~bit(inc))[0];
            marks
              ..add(Mark(c, inc, 'alt'))
              ..add(Mark(c, o, 'key'));
            inc = o;
          }
          return Step('xy_chain',
              elims: found,
              cells: List.of(path),
              marks: marks,
              text:
                  'XY-Chain on $x: follow the chain of two-candidate cells ${path.map(cellName).join(' → ')}. If ${cellName(start)} is not $x, each link forces the next cell, and the chain ends with ${cellName(end)} = $x. So either the start or the end of the chain is $x. Any cell that sees both ends cannot be $x: remove it from ${_cells(found.map((e) => e[0]))}.');
        }
      }
    }
  }
  return null;
}

final List<MapEntry<String, Step? Function(SolverState)>> strategies = [
  MapEntry('full_house', _fullHouse),
  MapEntry('hidden_single_box', (s) => _hiddenSingle(s, _boxUnits, 'hidden_single_box')),
  MapEntry('hidden_single_line', (s) => _hiddenSingle(s, _lineUnits, 'hidden_single_line')),
  MapEntry('naked_single', _nakedSingle),
  MapEntry('pointing', _pointing),
  MapEntry('claiming', _claiming),
  MapEntry('naked_pair', (s) => _nakedSubset(s, 2, 'naked_pair')),
  MapEntry('hidden_pair', (s) => _hiddenSubset(s, 2, 'hidden_pair')),
  MapEntry('naked_triple', (s) => _nakedSubset(s, 3, 'naked_triple')),
  MapEntry('hidden_triple', (s) => _hiddenSubset(s, 3, 'hidden_triple')),
  MapEntry('x_wing', (s) => _fish(s, 2, 'x_wing')),
  MapEntry('skyscraper', _skyscraper),
  MapEntry('two_string_kite', _twoStringKite),
  MapEntry('xy_wing', _xyWing),
  MapEntry('naked_quad', (s) => _nakedSubset(s, 4, 'naked_quad')),
  MapEntry('xyz_wing', _xyzWing),
  MapEntry('swordfish', (s) => _fish(s, 3, 'swordfish')),
  MapEntry('simple_coloring', _simpleColoring),
  MapEntry('unique_rectangle', _uniqueRectangle),
  MapEntry('bug_plus_one', _bugPlusOne),
  MapEntry('xy_chain', _xyChain),
  MapEntry('jellyfish', (s) => _fish(s, 4, 'jellyfish')),
];

Step? findStep(SolverState s) {
  for (final e in strategies) {
    final step = e.value(s);
    if (step != null) return step;
  }
  return null;
}

class HintStep {
  final Step step;
  final SolverState state;
  HintStep(this.step, this.state);
}

class Hint {
  final String kind; // mistake | steps | solved | stuck
  final List<int> cells;
  final List<HintStep> steps;
  Hint(this.kind, {this.cells = const [], this.steps = const []});
}

Hint computeHint(List<int> grid, List<int> solution) {
  final wrong = [for (var i = 0; i < 81; i++) if (grid[i] != 0 && grid[i] != solution[i]) i];
  if (wrong.isNotEmpty) return Hint('mistake', cells: wrong);
  final s = makeState(grid);
  if (s.solved) return Hint('solved');
  final steps = <HintStep>[];
  for (var guard = 0; guard < 40; guard++) {
    final step = findStep(s);
    if (step == null) break;
    steps.add(HintStep(step, s.clone()));
    if (step.places.isNotEmpty) return Hint('steps', steps: steps);
    applyStep(s, step);
  }
  // No technique applies from here (placements can destroy patterns an earlier
  // deduction relied on). Reveal the most constrained empty cell instead.
  var best = -1;
  for (var i = 0; i < 81; i++) {
    if (s.grid[i] == 0 && (best < 0 || popcount(s.cand[i]) < popcount(s.cand[best]))) best = i;
  }
  if (best < 0) return Hint('stuck');
  final d = solution[best];
  steps.add(HintStep(
      Step('reveal',
          places: [
            [best, d]
          ],
          cells: [best],
          unitIds: cellUnits[best],
          text:
              "None of the Academy techniques applies from this position. That can happen when digits placed earlier break up the patterns an advanced deduction relied on. Here's one cell from the solution to get you moving: ${cellName(best)} = $d."),
      s.clone()));
  return Hint('steps', steps: steps);
}

/// Logic-only solve used by tests to validate the port.
({bool solved, int level}) logicalSolve(List<int> grid) {
  final s = makeState(grid);
  var level = 0;
  while (!s.solved) {
    final step = findStep(s);
    if (step == null) return (solved: false, level: level);
    level = max(level, techniques[step.tech]!.level);
    applyStep(s, step);
  }
  return (solved: true, level: level);
}

// --------------- transforms ---------------
List<T> _shuffled<T>(List<T> a, Random r) => List.of(a)..shuffle(r);

({String puzzle, String solution}) transformPuzzle(String puzzle, String solution, Random rng) {
  final digits = _shuffled([1, 2, 3, 4, 5, 6, 7, 8, 9], rng);
  final bands = _shuffled([0, 1, 2], rng), stacks = _shuffled([0, 1, 2], rng);
  final rowMap = <int>[], colMap = <int>[];
  for (final b in bands) {
    for (final r in _shuffled([0, 1, 2], rng)) {
      rowMap.add(b * 3 + r);
    }
  }
  for (final b in stacks) {
    for (final c in _shuffled([0, 1, 2], rng)) {
      colMap.add(b * 3 + c);
    }
  }
  final flip = rng.nextBool();
  String map(String str) {
    final sb = StringBuffer();
    for (var r = 0; r < 9; r++) {
      for (var c = 0; c < 9; c++) {
        var sr = rowMap[r], sc = colMap[c];
        if (flip) {
          final t = sr;
          sr = sc;
          sc = t;
        }
        final ch = str.codeUnitAt(sr * 9 + sc);
        sb.write(ch >= 49 && ch <= 57 ? '${digits[ch - 49]}' : '.');
      }
    }
    return sb.toString();
  }

  return (puzzle: map(puzzle), solution: map(solution));
}
