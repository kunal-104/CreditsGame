import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart' hide Step;
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'engine.dart';

class LessonStage {
  final int level;
  final String name, tagline;
  LessonStage(this.level, this.name, this.tagline);
}

class Lesson {
  final String id, title, summary, keyIdea, tip;
  final String? tech, task;
  final int level;
  final List<String> body;
  Lesson.fromJson(Map<String, dynamic> j)
      : id = j['id'] as String,
        title = j['title'] as String,
        summary = j['summary'] as String,
        keyIdea = j['keyIdea'] as String,
        tip = j['tip'] as String,
        tech = j['tech'] as String?,
        task = j['task'] as String?,
        level = j['level'] as int,
        body = List<String>.from(j['body'] as List);
}

class Example {
  final List<int> grid, cand;
  final Step step;
  Example.fromJson(Map<String, dynamic> j)
      : grid = parseGrid(j['grid'] as String),
        cand = List<int>.from(j['cand'] as List),
        step = Step.fromJson(j['step'] as Map<String, dynamic>);
}

class PuzzleSpec {
  final String puzzle, solution;
  final int level;
  PuzzleSpec(this.puzzle, this.solution, this.level);
}

class LevelStats {
  int played = 0, won = 0, total = 0, flawless = 0;
  int? best;
  LevelStats();
  LevelStats.fromJson(Map<String, dynamic> j)
      : played = j['played'] as int? ?? 0,
        won = j['won'] as int? ?? 0,
        total = j['total'] as int? ?? 0,
        flawless = j['flawless'] as int? ?? 0,
        best = j['best'] as int?;
  Map<String, dynamic> toJson() => {'played': played, 'won': won, 'total': total, 'flawless': flawless, 'best': best};
}

class GameData {
  String puzzle, solution, mode;
  int level, time = 0, mistakes = 0, hints = 0;
  String? lesson, day;
  late List<int> grid, notes;
  late List<bool> given;
  bool done = false;

  GameData(this.puzzle, this.solution, this.level, this.mode, {this.lesson, this.day}) {
    grid = parseGrid(puzzle);
    given = grid.map((v) => v != 0).toList();
    notes = List.filled(81, 0);
  }

  List<int> get sol => parseGrid(solution);

  Map<String, dynamic> toJson() => {
        'puzzle': puzzle,
        'solution': solution,
        'mode': mode,
        'level': level,
        'time': time,
        'mistakes': mistakes,
        'hints': hints,
        'lesson': lesson,
        'day': day,
        'grid': grid,
        'notes': notes,
        'done': done,
      };

  static GameData fromJson(Map<String, dynamic> j) {
    final g = GameData(j['puzzle'] as String, j['solution'] as String, j['level'] as int, j['mode'] as String,
        lesson: j['lesson'] as String?, day: j['day'] as String?);
    g.time = j['time'] as int;
    g.mistakes = j['mistakes'] as int;
    g.hints = j['hints'] as int;
    g.grid = List<int>.from(j['grid'] as List);
    g.notes = List<int>.from(j['notes'] as List);
    g.done = j['done'] as bool;
    return g;
  }
}

String todayKey([DateTime? d]) {
  final t = (d ?? DateTime.now());
  return '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
}

String fmtTime(int s) {
  final h = s ~/ 3600, m = (s % 3600) ~/ 60, x = s % 60;
  final mm = h > 0 ? m.toString().padLeft(2, '0') : '$m';
  return '${h > 0 ? '$h:' : ''}$mm:${x.toString().padLeft(2, '0')}';
}

class AppStore extends ChangeNotifier {
  static late AppStore I;

  late SharedPreferences _prefs;
  late Map<String, dynamic> _bank;
  late List<LessonStage> stages;
  late List<Lesson> lessons;
  final Map<String, List<Example>> _examples = {};

  // settings
  ThemeMode themeMode = ThemeMode.system;
  bool highlightPeers = true, highlightSame = true, showMistakes = true, autoRemoveNotes = true, showTimer = true;

  Map<String, LevelStats> stats = {};
  Set<String> academy = {};
  Map<String, int> dailyDone = {};
  int streak = 0;
  String? lastDaily;
  GameData? game;

  static Future<AppStore> load() async {
    final s = AppStore();
    s._prefs = await SharedPreferences.getInstance();
    s._bank = jsonDecode(await rootBundle.loadString('assets/bank.json')) as Map<String, dynamic>;
    final l = jsonDecode(await rootBundle.loadString('assets/lessons.json')) as Map<String, dynamic>;
    s.stages = [
      for (final st in l['stages'] as List)
        LessonStage(st['level'] as int, st['name'] as String, st['tagline'] as String)
    ];
    s.lessons = [for (final x in l['lessons'] as List) Lesson.fromJson(x as Map<String, dynamic>)];
    s._read();
    I = s;
    return s;
  }

  void _read() {
    final p = _prefs;
    themeMode = ThemeMode.values[p.getInt('theme') ?? 0];
    highlightPeers = p.getBool('highlightPeers') ?? true;
    highlightSame = p.getBool('highlightSame') ?? true;
    showMistakes = p.getBool('showMistakes') ?? true;
    autoRemoveNotes = p.getBool('autoRemoveNotes') ?? true;
    showTimer = p.getBool('showTimer') ?? true;
    final st = p.getString('stats');
    if (st != null) {
      stats = (jsonDecode(st) as Map<String, dynamic>)
          .map((k, v) => MapEntry(k, LevelStats.fromJson(v as Map<String, dynamic>)));
    }
    academy = (p.getStringList('academy') ?? []).toSet();
    final d = p.getString('daily');
    if (d != null) {
      final j = jsonDecode(d) as Map<String, dynamic>;
      dailyDone = Map<String, int>.from(j['done'] as Map);
      streak = j['streak'] as int;
      lastDaily = j['last'] as String?;
    }
    final g = p.getString('game');
    if (g != null) {
      try {
        game = GameData.fromJson(jsonDecode(g) as Map<String, dynamic>);
      } catch (_) {
        game = null;
      }
    }
  }

  void saveSettings() {
    _prefs
      ..setInt('theme', themeMode.index)
      ..setBool('highlightPeers', highlightPeers)
      ..setBool('highlightSame', highlightSame)
      ..setBool('showMistakes', showMistakes)
      ..setBool('autoRemoveNotes', autoRemoveNotes)
      ..setBool('showTimer', showTimer);
    notifyListeners();
  }

  void saveGame() {
    if (game == null) {
      _prefs.remove('game');
    } else {
      _prefs.setString('game', jsonEncode(game!.toJson()));
    }
  }

  void _saveStats() => _prefs.setString('stats', jsonEncode(stats.map((k, v) => MapEntry(k, v.toJson()))));

  LevelStats statsFor(int level) => stats.putIfAbsent('$level', LevelStats.new);

  void startGame(PuzzleSpec p, {String mode = 'classic', String? lesson, String? day}) {
    game = GameData(p.puzzle, p.solution, p.level, mode, lesson: lesson, day: day);
    statsFor(p.level).played++;
    _saveStats();
    saveGame();
    notifyListeners();
  }

  /// Returns true when the time is a new best.
  bool recordWin() {
    final g = game!;
    final s = statsFor(g.level);
    s.won++;
    s.total += g.time;
    if (g.hints == 0 && g.mistakes == 0) s.flawless++;
    final best = s.best == null || g.time < s.best!;
    if (best) s.best = g.time;
    _saveStats();
    if (g.mode == 'daily') _markDaily(g.time);
    if (g.mode == 'practice' && g.lesson != null) markLesson(g.lesson!);
    saveGame();
    notifyListeners();
    return best;
  }

  void _markDaily(int time) {
    final key = todayKey();
    if (dailyDone.containsKey(key)) return;
    dailyDone[key] = time;
    final y = todayKey(DateTime.now().subtract(const Duration(days: 1)));
    streak = lastDaily == y ? streak + 1 : 1;
    lastDaily = key;
    _prefs.setString('daily', jsonEncode({'done': dailyDone, 'streak': streak, 'last': lastDaily}));
  }

  int get currentStreak {
    if (lastDaily == todayKey() || lastDaily == todayKey(DateTime.now().subtract(const Duration(days: 1)))) {
      return streak;
    }
    return 0;
  }

  void markLesson(String id) {
    academy.add(id);
    _prefs.setStringList('academy', academy.toList());
    notifyListeners();
  }

  void resetAll() {
    for (final k in ['stats', 'academy', 'daily', 'game']) {
      _prefs.remove(k);
    }
    stats = {};
    academy = {};
    dailyDone = {};
    streak = 0;
    lastDaily = null;
    game = null;
    notifyListeners();
  }

  // ---------------- puzzles ----------------
  List<dynamic> _levelList(int level) => (_bank['levels'] as Map<String, dynamic>)['$level'] as List;

  PuzzleSpec pickPuzzle(int level, Random rng) {
    final list = _levelList(level);
    final e = list[rng.nextInt(list.length)] as List;
    final t = transformPuzzle(e[0] as String, e[1] as String, rng);
    return PuzzleSpec(t.puzzle, t.solution, level);
  }

  static int _hash(String s) {
    var h = 2166136261;
    for (final c in s.codeUnits) {
      h = ((h ^ c) * 16777619) & 0xffffffff;
    }
    return h;
  }

  int get dailyLevel => const [6, 2, 3, 3, 4, 4, 5][DateTime.now().weekday % 7];

  PuzzleSpec dailyPuzzle() => pickPuzzle(dailyLevel, Random(_hash('daily${todayKey()}')));

  PuzzleSpec practicePuzzle(String tech) {
    final lvl = techniques[tech]!.level;
    final rng = Random();
    final list = ((_bank['practice'] as Map<String, dynamic>)[tech] as List?) ?? [];
    List e;
    if (list.isNotEmpty) {
      final ref = list[rng.nextInt(list.length)];
      e = ref is int ? _levelList(lvl)[ref] as List : ref as List;
    } else {
      final l = _levelList(lvl);
      e = l[rng.nextInt(l.length)] as List;
    }
    final t = transformPuzzle(e[0] as String, e[1] as String, rng);
    return PuzzleSpec(t.puzzle, t.solution, lvl);
  }

  List<Example> examplesFor(String tech) => _examples.putIfAbsent(tech, () {
        final raw = ((_bank['examples'] as Map<String, dynamic>)[tech] as List?) ?? [];
        return [for (final e in raw) Example.fromJson(e as Map<String, dynamic>)];
      });

  Lesson? lessonForTech(String tech) {
    for (final l in lessons) {
      if (l.tech == tech) return l;
    }
    return null;
  }
}
