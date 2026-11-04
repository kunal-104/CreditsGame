import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Category {
  final String id, name, emoji;
  final Color color;
  Category(this.id, this.name, this.emoji, this.color);
}

class Country {
  final String code, name, continent;
  Country(this.code, this.name, this.continent);
}

class Fact {
  final String id, c, s, e, w;
  final List<String> r;
  final bool a;
  Fact.fromJson(Map<String, dynamic> j)
      : id = j['id'] as String,
        c = j['c'] as String,
        s = j['s'] as String,
        e = j['e'] as String,
        w = j['w'] as String,
        r = List<String>.from(j['r'] as List),
        a = j['a'] as bool;
}

class AnswerRecord {
  int ok, bad, last;
  bool? lastOk;
  AnswerRecord({this.ok = 0, this.bad = 0, this.last = 0, this.lastOk});
  Map<String, dynamic> toJson() => {'ok': ok, 'bad': bad, 'last': last, 'lastOk': lastOk};
  factory AnswerRecord.fromJson(Map<String, dynamic> j) =>
      AnswerRecord(ok: j['ok'] as int, bad: j['bad'] as int, last: j['last'] as int, lastOk: j['lastOk'] as bool?);
}

class SavedArticle {
  final String title, extract, url;
  final String? thumb;
  SavedArticle(this.title, this.extract, this.url, this.thumb);
  Map<String, dynamic> toJson() => {'title': title, 'extract': extract, 'url': url, 'thumb': thumb};
  factory SavedArticle.fromJson(Map<String, dynamic> j) =>
      SavedArticle(j['title'] as String, j['extract'] as String, j['url'] as String, j['thumb'] as String?);
}

String flagOf(String code) =>
    code == 'world' ? '🌐' : String.fromCharCodes(code.codeUnits.map((c) => 127397 + c));

Uri wikiUri(String title) => Uri.parse(
    'https://en.wikipedia.org/w/index.php?title=Special:Search&go=Go&search=${Uri.encodeQueryComponent(title)}');

String todayKey([DateTime? d]) {
  final t = d ?? DateTime.now();
  return '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
}

int hashStr(String s) {
  var h = 2166136261;
  for (final c in s.codeUnits) {
    h = ((h ^ c) * 16777619) & 0xffffffff;
  }
  return h;
}

const _titles = [
  (1, 'Curious'),
  (3, 'Explorer'),
  (6, 'Scholar'),
  (10, 'Sage'),
  (15, 'Polymath'),
  (25, 'Living Encyclopedia')
];
int xpFor(int lvl) => 50 * lvl * (lvl - 1);
int levelOf(int xp) {
  var l = 1;
  while (xp >= xpFor(l + 1)) {
    l++;
  }
  return l;
}

String titleOf(int lvl) => _titles.lastWhere((t) => lvl >= t.$1).$2;

class Curio extends ChangeNotifier {
  static late Curio I;
  late SharedPreferences _p;
  late List<Category> categories;
  late List<Country> countries;
  late List<Fact> facts;
  late Map<String, Category> cat;
  late Map<String, Country> country;

  String? home;
  List<String> interests = [];
  bool onboarded = false;
  int xp = 0, streak = 0, bestCombo = 0, wikiCount = 0;
  String? lastDay;
  ThemeMode themeMode = ThemeMode.system;
  Map<String, AnswerRecord> answers = {};
  List<String> savedFacts = [];
  List<SavedArticle> savedArticles = [];
  Map<String, String> daily = {}; // date -> "score/total"

  /// Set when the player levels up; the UI shows it once and clears it.
  String? levelUpMessage;

  static Future<Curio> load() async {
    final c = Curio();
    c._p = await SharedPreferences.getInstance();
    final j = jsonDecode(await rootBundle.loadString('assets/facts.json')) as Map<String, dynamic>;
    c.categories = [
      for (final x in j['categories'] as List)
        Category(x['id'] as String, x['name'] as String, x['emoji'] as String,
            Color(int.parse((x['color'] as String).substring(1), radix: 16) | 0xFF000000))
    ];
    c.countries = [
      for (final x in j['countries'] as List) Country(x['code'] as String, x['name'] as String, x['continent'] as String)
    ];
    c.facts = [for (final x in j['facts'] as List) Fact.fromJson(x as Map<String, dynamic>)];
    c.cat = {for (final x in c.categories) x.id: x};
    c.country = {for (final x in c.countries) x.code: x};
    c._read();
    I = c;
    return c;
  }

  void _read() {
    final p = _p;
    home = p.getString('home');
    interests = p.getStringList('interests') ?? [];
    onboarded = p.getBool('onboarded') ?? false;
    xp = p.getInt('xp') ?? 0;
    streak = p.getInt('streak') ?? 0;
    bestCombo = p.getInt('bestCombo') ?? 0;
    wikiCount = p.getInt('wiki') ?? 0;
    lastDay = p.getString('lastDay');
    themeMode = ThemeMode.values[p.getInt('theme') ?? 0];
    final a = p.getString('answers');
    if (a != null) {
      answers = (jsonDecode(a) as Map<String, dynamic>)
          .map((k, v) => MapEntry(k, AnswerRecord.fromJson(v as Map<String, dynamic>)));
    }
    savedFacts = p.getStringList('savedFacts') ?? [];
    final sa = p.getString('savedArticles');
    if (sa != null) {
      savedArticles = [for (final x in jsonDecode(sa) as List) SavedArticle.fromJson(x as Map<String, dynamic>)];
    }
    final d = p.getString('daily');
    if (d != null) daily = Map<String, String>.from(jsonDecode(d) as Map);
  }

  void _saveProfile() {
    _p
      ..setInt('xp', xp)
      ..setInt('streak', streak)
      ..setInt('bestCombo', bestCombo)
      ..setInt('wiki', wikiCount)
      ..setInt('theme', themeMode.index)
      ..setBool('onboarded', onboarded)
      ..setStringList('interests', interests);
    if (lastDay != null) _p.setString('lastDay', lastDay!);
    if (home != null) _p.setString('home', home!);
    notifyListeners();
  }

  void setHome(String? code) {
    home = code;
    _saveProfile();
  }

  void finishOnboarding(List<String> picks) {
    interests = picks;
    onboarded = true;
    _saveProfile();
  }

  void setTheme(ThemeMode m) {
    themeMode = m;
    _saveProfile();
  }

  int get currentStreak {
    final y = todayKey(DateTime.now().subtract(const Duration(days: 1)));
    return lastDay == todayKey() || lastDay == y ? streak : 0;
  }

  void addXp(int n) {
    final before = levelOf(xp);
    xp += n;
    final t = todayKey();
    if (lastDay != t) {
      final y = todayKey(DateTime.now().subtract(const Duration(days: 1)));
      streak = lastDay == y ? streak + 1 : 1;
      lastDay = t;
    }
    final after = levelOf(xp);
    if (after > before) levelUpMessage = 'Level $after! You are now: ${titleOf(after)} ✨';
    _saveProfile();
  }

  void countWiki() {
    wikiCount++;
    addXp(2);
  }

  void recordAnswer(Fact f, bool correct, int combo) {
    final a = answers.putIfAbsent(f.id, AnswerRecord.new);
    correct ? a.ok++ : a.bad++;
    a.last = DateTime.now().millisecondsSinceEpoch;
    a.lastOk = correct;
    if (combo > bestCombo) bestCombo = combo;
    _p.setString('answers', jsonEncode(answers.map((k, v) => MapEntry(k, v.toJson()))));
  }

  void recordDaily(int score, int total) {
    daily[todayKey()] = '$score/$total';
    _p.setString('daily', jsonEncode(daily));
    notifyListeners();
  }

  bool isSaved(String id) => savedFacts.contains(id);
  bool toggleSaveFact(String id) {
    isSaved(id) ? savedFacts.remove(id) : savedFacts.insert(0, id);
    _p.setStringList('savedFacts', savedFacts);
    notifyListeners();
    return isSaved(id);
  }

  bool isArticleSaved(String title) => savedArticles.any((a) => a.title == title);
  bool toggleSaveArticle(SavedArticle a) {
    if (isArticleSaved(a.title)) {
      savedArticles.removeWhere((x) => x.title == a.title);
    } else {
      savedArticles.insert(0, a);
    }
    _p.setString('savedArticles', jsonEncode(savedArticles.map((e) => e.toJson()).toList()));
    notifyListeners();
    return isArticleSaved(a.title);
  }

  Future<void> resetAll() async {
    await _p.clear();
    answers = {};
    savedFacts = [];
    savedArticles = [];
    daily = {};
    xp = 0;
    streak = 0;
    bestCombo = 0;
    wikiCount = 0;
    lastDay = null;
    home = null;
    interests = [];
    onboarded = false;
    notifyListeners();
  }

  // ---------------- sessions ----------------
  /// Prioritises unseen facts, mistakes due for review, facts from beyond the
  /// home country and the player's interests, and balances myths vs facts.
  List<Fact> buildSession(List<Fact> pool, {int size = 10, int? seed}) {
    final r = seed == null ? Random() : Random(seed);
    final now = DateTime.now().millisecondsSinceEpoch;
    final scored = pool.map((f) {
      final a = answers[f.id];
      var p = r.nextDouble() * 1.5;
      if (a == null) {
        p += 4;
      } else if (a.bad > a.ok || (a.lastOk == false && now - a.last > 3600000)) {
        p += 3;
      } else {
        p -= 2 + (now - a.last < 86400000 ? 2 : 0);
      }
      if (home != null && !f.r.contains(home) && !f.r.contains('world')) p += 1.2;
      if (interests.contains(f.c)) p += 0.8;
      return (f: f, p: p);
    }).toList()
      ..sort((a, b) => b.p.compareTo(a.p));
    final n = min(size, pool.length);
    final myths = scored.where((x) => !x.f.a).toList(), truths = scored.where((x) => x.f.a).toList();
    final wantMyths = min(myths.length, (n * (0.35 + r.nextDouble() * 0.15)).round());
    final pick = [...myths.take(wantMyths), ...truths.take(n - wantMyths)];
    if (pick.length < n) pick.addAll(scored.where((x) => !pick.contains(x)).take(n - pick.length));
    final out = pick.map((x) => x.f).toList()..shuffle(r);
    for (var i = 2; i < out.length; i++) {
      if (out[i].c == out[i - 1].c && out[i].c == out[i - 2].c) {
        final j = out.indexWhere((x) => x.c != out[i].c, i + 1);
        if (j > 0) {
          final t = out[i];
          out[i] = out[j];
          out[j] = t;
        }
      }
    }
    return out;
  }

  Fact factOfTheDay() {
    final pool = facts.where((f) => f.a && !(home != null && f.r.contains(home))).toList();
    return pool[hashStr('fotd${todayKey()}') % pool.length];
  }

  ({int seen, int total}) progressWhere(bool Function(Fact) test) {
    final list = facts.where(test).toList();
    return (seen: list.where((f) => answers.containsKey(f.id)).length, total: list.length);
  }

  List<Fact> mistakes() => facts.where((f) => answers[f.id]?.lastOk == false).toList();
}
