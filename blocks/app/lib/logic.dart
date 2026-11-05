// Dart port of blocks/web/js/logic.js. Keep both in sync.
import 'dart:math';

const int n = 9;

class Shape {
  final String name;
  final int color;
  final double weight;
  final List<(int, int)> cells;
  final int h, w;
  Shape(this.name, this.color, this.weight, List<String> rows)
      : cells = [
          for (var r = 0; r < rows.length; r++)
            for (var c = 0; c < rows[r].length; c++)
              if (rows[r][c] == '#') (r, c)
        ],
        h = rows.length,
        w = rows.map((x) => x.length).reduce(max);
}

final List<Shape> shapes = [
  Shape('dot', 1, 3, ['#']),
  Shape('i2', 2, 4, ['##']), Shape('i2v', 2, 4, ['#', '#']),
  Shape('i3', 3, 4, ['###']), Shape('i3v', 3, 4, ['#', '#', '#']),
  Shape('i4', 4, 3, ['####']), Shape('i4v', 4, 3, ['#', '#', '#', '#']),
  Shape('i5', 5, 2, ['#####']), Shape('i5v', 5, 2, ['#', '#', '#', '#', '#']),
  Shape('o2', 6, 4, ['##', '##']),
  Shape('o3', 7, 1.5, ['###', '###', '###']),
  Shape('r23', 6, 2, ['###', '###']), Shape('r32', 6, 2, ['##', '##', '##']),
  Shape('c3a', 1, 3, ['##', '#.']), Shape('c3b', 1, 3, ['##', '.#']), Shape('c3c', 1, 3, ['#.', '##']), Shape('c3d', 1, 3, ['.#', '##']),
  Shape('l4a', 2, 2, ['#.', '#.', '##']), Shape('l4b', 2, 2, ['###', '#..']), Shape('l4c', 2, 2, ['##', '.#', '.#']), Shape('l4d', 2, 2, ['..#', '###']),
  Shape('j4a', 3, 2, ['.#', '.#', '##']), Shape('j4b', 3, 2, ['#..', '###']), Shape('j4c', 3, 2, ['##', '#.', '#.']), Shape('j4d', 3, 2, ['###', '..#']),
  Shape('t4a', 4, 2, ['###', '.#.']), Shape('t4b', 4, 2, ['.#', '##', '.#']), Shape('t4c', 4, 2, ['.#.', '###']), Shape('t4d', 4, 2, ['#.', '##', '#.']),
  Shape('s4a', 5, 1.5, ['.##', '##.']), Shape('s4b', 5, 1.5, ['#.', '##', '.#']),
  Shape('z4a', 7, 1.5, ['##.', '.##']), Shape('z4b', 7, 1.5, ['.#', '##', '#.']),
  Shape('v5a', 5, 1.5, ['#..', '#..', '###']), Shape('v5b', 5, 1.5, ['###', '#..', '#..']),
  Shape('v5c', 5, 1.5, ['###', '..#', '..#']), Shape('v5d', 5, 1.5, ['..#', '..#', '###']),
  Shape('plus', 4, 1, ['.#.', '###', '.#.']),
  Shape('d2a', 3, 1, ['#.', '.#']), Shape('d2b', 3, 1, ['.#', '#.']),
];
final Map<String, Shape> shapeByName = {for (final s in shapes) s.name: s};

/// mulberry32 single step: returns the value for [state].
double mulberryAt(int state) {
  var a = (state + 0x6d2b79f5) & 0xffffffff;
  var t = a;
  t = _imul(t ^ (t >>> 15), t | 1);
  t ^= (t + _imul(t ^ (t >>> 7), t | 61)) & 0xffffffff;
  return ((t ^ (t >>> 14)) & 0xffffffff) / 4294967296;
}

int _imul(int a, int b) => ((a & 0xffffffff) * (b & 0xffffffff)) & 0xffffffff;

List<int> emptyBoard() => List.filled(n * n, 0);

bool canPlaceOn(List<int> board, Shape s, int r, int c) {
  for (final (dr, dc) in s.cells) {
    final rr = r + dr, cc = c + dc;
    if (rr < 0 || cc < 0 || rr >= n || cc >= n) return false;
    if (board[rr * n + cc] != 0) return false;
  }
  return true;
}

bool fitsAnywhere(List<int> board, Shape s) {
  for (var r = 0; r <= n - s.h; r++) {
    for (var c = 0; c <= n - s.w; c++) {
      if (canPlaceOn(board, s, r, c)) return true;
    }
  }
  return false;
}

class Clears {
  final List<int> rows, cols, boxes;
  final Set<int> cells;
  Clears(this.rows, this.cols, this.boxes, this.cells);
  int get lines => rows.length + cols.length + boxes.length;
}

Clears findClears(List<int> board) {
  final rows = <int>[], cols = <int>[], boxes = <int>[];
  for (var i = 0; i < n; i++) {
    var rf = true, cf = true, bf = true;
    final br = (i ~/ 3) * 3, bc = (i % 3) * 3;
    for (var j = 0; j < n; j++) {
      if (board[i * n + j] == 0) rf = false;
      if (board[j * n + i] == 0) cf = false;
      if (board[(br + j ~/ 3) * n + bc + j % 3] == 0) bf = false;
    }
    if (rf) rows.add(i);
    if (cf) cols.add(i);
    if (bf) boxes.add(i);
  }
  final cells = <int>{};
  for (final r in rows) {
    for (var j = 0; j < n; j++) {
      cells.add(r * n + j);
    }
  }
  for (final c in cols) {
    for (var j = 0; j < n; j++) {
      cells.add(j * n + c);
    }
  }
  for (final b in boxes) {
    final br = (b ~/ 3) * 3, bc = (b % 3) * 3;
    for (var j = 0; j < n; j++) {
      cells.add((br + j ~/ 3) * n + bc + j % 3);
    }
  }
  return Clears(rows, cols, boxes, cells);
}

int scoreFor(int placed, int lines, int combo) {
  if (lines == 0) return placed;
  final base = lines * 18 + (lines - 1) * lines * 9;
  return placed + base + (combo - 1) * 10 * lines;
}

const praise = ['', 'Nice!', 'Great!', 'Amazing!', 'Incredible!', 'Unstoppable!'];

class PlaceResult {
  final List<int> placed, cleared;
  final int lines, points, combo;
  final bool over;
  PlaceResult(this.placed, this.cleared, this.lines, this.points, this.combo, this.over);
}

class Preview {
  final List<int> cells;
  final Clears clears;
  Preview(this.cells, this.clears);
}

class Game {
  int seed, rngState;
  String mode;
  List<int> board = emptyBoard();
  List<String?> tray = [];
  int score = 0, combo = 0, bestCombo = 0, lines = 0, moves = 0, shuffles = 1;
  bool over = false;
  String? dayKey;

  Game({int? seed, this.mode = 'classic'})
      : seed = seed ?? Random().nextInt(1 << 32),
        rngState = 0 {
    rngState = this.seed;
    tray = _makeTray();
  }

  double _rng() {
    final v = mulberryAt(rngState);
    rngState = (rngState + 0x6d2b79f5) & 0xffffffff;
    return v;
  }

  Shape _pick() {
    final empty = board.where((v) => v == 0).length;
    final crowd = 1 - empty / (n * n);
    var total = 0.0;
    final ws = shapes.map((s) {
      final w = s.weight * (s.cells.length <= 3 ? 1 + crowd : (s.cells.length >= 5 ? 1 - crowd * 0.6 : 1));
      total += w;
      return w;
    }).toList();
    var x = _rng() * total;
    for (var i = 0; i < shapes.length; i++) {
      x -= ws[i];
      if (x <= 0) return shapes[i];
    }
    return shapes.first;
  }

  List<String?> _makeTray() {
    var t = <Shape>[];
    for (var attempt = 0; attempt < 25; attempt++) {
      t = [_pick(), _pick(), _pick()];
      if (t.any((s) => fitsAnywhere(board, s))) break;
    }
    return <String?>[for (final s in t) s.name];
  }

  Shape? shape(int i) => tray[i] == null ? null : shapeByName[tray[i]];

  bool canPlace(int i, int r, int c) {
    final s = shape(i);
    return s != null && !over && canPlaceOn(board, s, r, c);
  }

  bool fits(int i) {
    final s = shape(i);
    return s != null && fitsAnywhere(board, s);
  }

  Preview? preview(int i, int r, int c) {
    final s = shape(i);
    if (s == null || !canPlaceOn(board, s, r, c)) return null;
    final b = List<int>.of(board);
    final cells = [for (final (dr, dc) in s.cells) (r + dr) * n + c + dc];
    for (final p in cells) {
      b[p] = s.color;
    }
    return Preview(cells, findClears(b));
  }

  PlaceResult? place(int i, int r, int c) {
    final s = shape(i);
    if (s == null || over || !canPlaceOn(board, s, r, c)) return null;
    final placed = [for (final (dr, dc) in s.cells) (r + dr) * n + c + dc];
    for (final p in placed) {
      board[p] = s.color;
    }
    final cl = findClears(board);
    if (cl.lines > 0) {
      combo++;
      bestCombo = max(bestCombo, combo);
    } else {
      combo = 0;
    }
    final points = scoreFor(s.cells.length, cl.lines, max(1, combo));
    for (final p in cl.cells) {
      board[p] = 0;
    }
    score += points;
    lines += cl.lines;
    moves++;
    tray[i] = null;
    if (tray.every((t) => t == null)) tray = _makeTray();
    over = !tray.any((t) => t != null && fitsAnywhere(board, shapeByName[t]!));
    return PlaceResult(placed, cl.cells.toList(), cl.lines, points, combo, over);
  }

  bool shuffle() {
    if (shuffles <= 0) return false;
    shuffles--;
    final fresh = _makeTray();
    tray = [for (var k = 0; k < 3; k++) tray[k] != null ? fresh[k] : null];
    if (tray.every((t) => t == null)) tray = fresh;
    over = !tray.any((t) => t != null && fitsAnywhere(board, shapeByName[t]!));
    return true;
  }

  Map<String, dynamic> toJson() => {
        'seed': seed,
        'rngState': rngState,
        'mode': mode,
        'board': board,
        'tray': tray,
        'score': score,
        'combo': combo,
        'bestCombo': bestCombo,
        'lines': lines,
        'moves': moves,
        'shuffles': shuffles,
        'over': over,
        'dayKey': dayKey,
      };

  static Game fromJson(Map<String, dynamic> j) {
    final g = Game(seed: j['seed'] as int, mode: j['mode'] as String);
    g
      ..rngState = j['rngState'] as int
      ..board = List<int>.from(j['board'] as List)
      ..tray = List<String?>.from(j['tray'] as List)
      ..score = j['score'] as int
      ..combo = j['combo'] as int
      ..bestCombo = j['bestCombo'] as int
      ..lines = j['lines'] as int
      ..moves = j['moves'] as int
      ..shuffles = j['shuffles'] as int
      ..over = j['over'] as bool
      ..dayKey = j['dayKey'] as String?;
    return g;
  }
}
