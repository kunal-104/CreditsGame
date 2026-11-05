import 'dart:convert';
import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'logic.dart';

// ------------------------------------------------------------------ themes
class Palette {
  final String name;
  final Color bg1, bg2, text, muted, surface, board, cell, cellAlt, accent, accentInk;
  final List<Color> blocks;
  final Brightness brightness;
  const Palette(this.name, this.bg1, this.bg2, this.text, this.muted, this.surface, this.board, this.cell, this.cellAlt,
      this.accent, this.accentInk, this.blocks, this.brightness);
}

const palettes = [
  Palette('Aurora', Color(0xFF1B1640), Color(0xFF3B1D6E), Color(0xFFF4F1FF), Color(0xFFB9B1E0), Color(0x1AFFFFFF),
      Color(0xFF241D52), Color(0xFF2E2665), Color(0xFF352C73), Color(0xFFFFCF4D), Color(0xFF2B2100), [
    Color(0xFFFF6B6B), Color(0xFFFFA94D), Color(0xFFFFD43B), Color(0xFF69DB7C), Color(0xFF4DABF7), Color(0xFF9775FA), Color(0xFFF783AC)
  ], Brightness.dark),
  Palette('Daylight', Color(0xFFE9F1FF), Color(0xFFFDF2FF), Color(0xFF1D2140), Color(0xFF5D6385), Color(0xC0FFFFFF),
      Color(0xFFC9D4EE), Color(0xFFE7EDFB), Color(0xFFDBE3F6), Color(0xFF5B5BF7), Colors.white, [
    Color(0xFFF03E3E), Color(0xFFFD7E14), Color(0xFFFAB005), Color(0xFF37B24D), Color(0xFF1C7ED6), Color(0xFF7048E8), Color(0xFFE64980)
  ], Brightness.light),
  Palette('Ocean', Color(0xFF062A3A), Color(0xFF0B4F63), Color(0xFFEAFCFF), Color(0xFF9CCBD6), Color(0x1AFFFFFF),
      Color(0xFF07394A), Color(0xFF0B4659), Color(0xFF0E5064), Color(0xFF3EE6C1), Color(0xFF00261D), [
    Color(0xFFFF8787), Color(0xFFFFC078), Color(0xFFFFE066), Color(0xFF63E6BE), Color(0xFF74C0FC), Color(0xFFB197FC), Color(0xFFFAA2C1)
  ], Brightness.dark),
  Palette('Candy', Color(0xFFFFE3F1), Color(0xFFE3F4FF), Color(0xFF43203A), Color(0xFF8A5C7E), Color(0xB3FFFFFF),
      Color(0xFFF7C6DD), Color(0xFFFFF0F7), Color(0xFFFFE4F1), Color(0xFFFF4D9D), Colors.white, [
    Color(0xFFFF5C8A), Color(0xFFFF9F43), Color(0xFFFECA57), Color(0xFF1DD1A1), Color(0xFF54A0FF), Color(0xFFA55EEA), Color(0xFFFF6BCB)
  ], Brightness.light),
];

// ------------------------------------------------------------------ store
const achievementsList = [
  ('first', '🧱', 'First Steps', 'Finish your first game'),
  ('clear1', '✨', 'Clean Sweep', 'Clear your first line'),
  ('multi3', '💥', 'Triple Threat', 'Clear 3 lines with one piece'),
  ('combo3', '🔥', 'On Fire', 'Reach a 3× combo'),
  ('combo6', '🌋', 'Volcanic', 'Reach a 6× combo'),
  ('s500', '🥉', 'Rising Star', 'Score 500 in one game'),
  ('s1500', '🥈', 'Block Master', 'Score 1,500 in one game'),
  ('s3000', '🥇', 'Legend', 'Score 3,000 in one game'),
  ('lines100', '📏', 'Line Collector', 'Clear 100 lines in total'),
  ('games25', '🎮', 'Regular', 'Play 25 games'),
  ('daily1', '📅', 'Daily Player', 'Finish a Daily Challenge'),
  ('daily7', '🏆', 'Weekly Warrior', 'Daily Challenge 7 days in a row'),
];

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

String fmt(int v) => v.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');

class Store extends ChangeNotifier {
  static late Store I;
  late SharedPreferences p;
  int theme = 0;
  bool haptics = true, sound = true, seenHowTo = false;
  int games = 0, best = 0, total = 0, lines = 0, bestCombo = 0, maxLines = 0, dailyStreak = 0;
  String? lastDaily;
  Map<String, int> daily = {};
  Map<String, int> achievements = {};
  String? pendingToast;

  static Future<void> load() async {
    final s = Store()..p = await SharedPreferences.getInstance();
    final p = s.p;
    s.theme = (p.getInt('theme') ?? 0).clamp(0, palettes.length - 1);
    s.haptics = p.getBool('haptics') ?? true;
    s.sound = p.getBool('sound') ?? true;
    s.seenHowTo = p.getBool('seenHowTo') ?? false;
    final st = p.getString('stats');
    if (st != null) {
      final j = jsonDecode(st) as Map<String, dynamic>;
      s.games = j['games'] as int;
      s.best = j['best'] as int;
      s.total = j['total'] as int;
      s.lines = j['lines'] as int;
      s.bestCombo = j['bestCombo'] as int;
      s.maxLines = j['maxLines'] as int;
      s.dailyStreak = j['dailyStreak'] as int;
      s.lastDaily = j['lastDaily'] as String?;
      s.daily = Map<String, int>.from(j['daily'] as Map);
    }
    final a = p.getString('achievements');
    if (a != null) s.achievements = Map<String, int>.from(jsonDecode(a) as Map);
    I = s;
  }

  Palette get pal => palettes[theme];

  void saveSettings() {
    p
      ..setInt('theme', theme)
      ..setBool('haptics', haptics)
      ..setBool('sound', sound)
      ..setBool('seenHowTo', seenHowTo);
    notifyListeners();
  }

  void saveStats() {
    p.setString(
        'stats',
        jsonEncode({
          'games': games,
          'best': best,
          'total': total,
          'lines': lines,
          'bestCombo': bestCombo,
          'maxLines': maxLines,
          'dailyStreak': dailyStreak,
          'lastDaily': lastDaily,
          'daily': daily,
        }));
    notifyListeners();
  }

  /// Returns the achievement's display text if newly unlocked.
  String? unlock(String id) {
    if (achievements.containsKey(id)) return null;
    achievements[id] = DateTime.now().millisecondsSinceEpoch;
    p.setString('achievements', jsonEncode(achievements));
    final a = achievementsList.firstWhere((x) => x.$1 == id);
    return '${a.$2} Achievement unlocked: ${a.$3}';
  }

  int get currentDailyStreak {
    final y = todayKey(DateTime.now().subtract(const Duration(days: 1)));
    return lastDaily == todayKey() || lastDaily == y ? dailyStreak : 0;
  }

  Game? savedGame() {
    final s = p.getString('game');
    if (s == null) return null;
    try {
      final g = Game.fromJson(jsonDecode(s) as Map<String, dynamic>);
      return g.over ? null : g;
    } catch (_) {
      return null;
    }
  }

  void saveGame(Game? g) => g == null || g.mode == 'daily' ? p.remove('game') : p.setString('game', jsonEncode(g.toJson()));

  void resetStats() {
    games = best = total = lines = bestCombo = maxLines = dailyStreak = 0;
    lastDaily = null;
    daily = {};
    achievements = {};
    p.remove('achievements');
    p.remove('game');
    saveStats();
  }
}

void buzz([HapticFeedbackType t = HapticFeedbackType.light]) {
  if (!Store.I.haptics) return;
  switch (t) {
    case HapticFeedbackType.light:
      HapticFeedback.lightImpact();
    case HapticFeedbackType.medium:
      HapticFeedback.mediumImpact();
    case HapticFeedbackType.heavy:
      HapticFeedback.heavyImpact();
  }
}

enum HapticFeedbackType { light, medium, heavy }

void click() {
  if (Store.I.sound) SystemSound.play(SystemSoundType.click);
}

// ------------------------------------------------------------------ app
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Store.load();
  runApp(const BlockoraApp());
}

class BlockoraApp extends StatelessWidget {
  const BlockoraApp({super.key});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Store.I,
        builder: (context, _) {
          final pal = Store.I.pal;
          return MaterialApp(
            title: 'Blockora',
            debugShowCheckedModeBanner: false,
            theme: ThemeData(
              brightness: pal.brightness,
              colorScheme: ColorScheme.fromSeed(seedColor: pal.accent, brightness: pal.brightness),
              scaffoldBackgroundColor: Colors.transparent,
              textTheme: Typography.material2021().black.apply(bodyColor: pal.text, displayColor: pal.text),
              dialogTheme: DialogThemeData(backgroundColor: Color.lerp(pal.bg1, pal.bg2, .5)),
            ),
            home: const HomeScreen(),
          );
        },
      );
}

class Backdrop extends StatelessWidget {
  final Widget child;
  const Backdrop({super.key, required this.child});
  @override
  Widget build(BuildContext context) {
    final pal = Store.I.pal;
    return DecoratedBox(
      decoration: BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [pal.bg1, pal.bg2])),
      child: DefaultTextStyle.merge(style: TextStyle(color: pal.text), child: child),
    );
  }
}

class Block extends StatelessWidget {
  final Color color;
  final double size;
  final double radius;
  const Block(this.color, this.size, {super.key, this.radius = 6});
  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color.lerp(color, Colors.white, .3)!, color, color, Color.lerp(color, Colors.black, .22)!],
            stops: const [0, .12, .82, 1],
          ),
        ),
      );
}

Widget pill(String text, Palette pal, {VoidCallback? onTap, bool primary = false, bool big = false}) => Material(
      color: primary ? pal.accent : pal.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 18, vertical: big ? 18 : 13),
          child: Center(
            child: Text(text,
                style: TextStyle(
                    fontWeight: FontWeight.w800, fontSize: big ? 20 : 15, color: primary ? pal.accentInk : pal.text)),
          ),
        ),
      ),
    );

Future<T?> sheet<T>(BuildContext context, List<Widget> children, {bool dismissible = true}) {
  final pal = Store.I.pal;
  return showDialog<T>(
    context: context,
    barrierDismissible: dismissible,
    builder: (ctx) => Dialog(
      backgroundColor: Color.lerp(pal.bg1, pal.bg2, .4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(22),
          child: DefaultTextStyle.merge(
            style: TextStyle(color: pal.text),
            textAlign: TextAlign.center,
            child: Column(mainAxisSize: MainAxisSize.min, children: children),
          ),
        ),
      ),
    ),
  );
}

void toast(BuildContext context, String msg) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 2), behavior: SnackBarBehavior.floating));
}

Future<void> showHowTo(BuildContext context) {
  final pal = Store.I.pal;
  Widget step(int k, String t) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          CircleAvatar(
              radius: 16,
              backgroundColor: pal.accent,
              child: Text('$k', style: TextStyle(color: pal.accentInk, fontWeight: FontWeight.w900))),
          const SizedBox(width: 12),
          Expanded(child: Text(t, textAlign: TextAlign.left)),
        ]),
      );
  return sheet(context, [
    const Text('🧩', style: TextStyle(fontSize: 48)),
    const Text('How to play', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900)),
    const SizedBox(height: 10),
    step(1, 'Drag a piece from the tray onto the board. You can also tap a piece, then tap where it should go.'),
    step(2, 'Fill a whole row, column or 3×3 square to clear it.'),
    step(3, 'Clear several at once, or on back-to-back moves, for big combo points.'),
    step(4, 'The game ends when none of your pieces fit. You get one free 🔀 Shuffle per game.'),
    const SizedBox(height: 14),
    Builder(
        builder: (ctx) => pill('Got it!', pal, primary: true, onTap: () {
              Store.I
                ..seenHowTo = true
                ..saveSettings();
              Navigator.pop(ctx);
            })),
  ]);
}

// ------------------------------------------------------------------ home
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    if (!Store.I.seenHowTo) WidgetsBinding.instance.addPostFrameCallback((_) => showHowTo(context));
  }

  Future<void> _play({String mode = 'classic', Game? resume}) async {
    await Navigator.push(context, PageRouteBuilder(
      pageBuilder: (_, _, _) => GameScreen(mode: mode, resume: resume),
      transitionsBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child),
    ));
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final s = Store.I;
    final pal = s.pal;
    final g = s.savedGame();
    final dailyScore = s.daily[todayKey()];
    final now = DateTime.now();
    const months = ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'];
    Widget stat(String v, String l) => Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 5),
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(color: pal.surface, borderRadius: BorderRadius.circular(16)),
            child: Column(children: [
              Text(v, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
              Text(l, style: TextStyle(fontSize: 11, color: pal.muted, letterSpacing: .8)),
            ]),
          ),
        );
    const logo = [1, 0, 2, 3, 4, 0, 5, 6, 7];
    return Backdrop(
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Column(children: [
                  SizedBox(
                    width: 3 * 30,
                    child: Wrap(spacing: 4, runSpacing: 4, children: [
                      for (final k in logo) k == 0 ? const SizedBox(width: 26, height: 26) : Block(pal.blocks[k - 1], 26),
                    ]),
                  ),
                  const SizedBox(height: 10),
                  const Text('Blockora', style: TextStyle(fontSize: 44, fontWeight: FontWeight.w900, letterSpacing: -1.2)),
                  Text('Drop. Clear. Combo.', style: TextStyle(color: pal.muted)),
                  const SizedBox(height: 18),
                  Row(children: [stat(fmt(s.best), 'BEST'), stat('${s.games}', 'GAMES'), stat('${s.bestCombo}×', 'TOP COMBO')]),
                  const SizedBox(height: 16),
                  if (g != null) ...[
                    pill('▶  Continue · ${fmt(g.score)}', pal, primary: true, big: true, onTap: () => _play(resume: g)),
                    const SizedBox(height: 10),
                    pill('New game', pal, onTap: () async {
                      final ok = await sheet<bool>(context, [
                        const Text('New game?', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
                        const SizedBox(height: 6),
                        Text('Your current game (${fmt(g.score)} points) will be lost.', style: TextStyle(color: pal.muted)),
                        const SizedBox(height: 16),
                        Builder(
                            builder: (ctx) => Row(children: [
                                  Expanded(child: pill('Cancel', pal, onTap: () => Navigator.pop(ctx, false))),
                                  const SizedBox(width: 10),
                                  Expanded(child: pill('New game', pal, primary: true, onTap: () => Navigator.pop(ctx, true))),
                                ])),
                      ]);
                      if (ok == true) _play();
                    }),
                  ] else
                    pill('▶  Play', pal, primary: true, big: true, onTap: () => _play()),
                  const SizedBox(height: 12),
                  Material(
                    color: pal.surface,
                    borderRadius: BorderRadius.circular(20),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () => _play(mode: 'daily'),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Row(children: [
                          Container(
                            width: 54,
                            height: 54,
                            decoration: BoxDecoration(color: pal.accent, borderRadius: BorderRadius.circular(14)),
                            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                              Text('${now.day}',
                                  style: TextStyle(color: pal.accentInk, fontWeight: FontWeight.w900, fontSize: 20, height: 1)),
                              Text(months[now.month - 1],
                                  style: TextStyle(color: pal.accentInk, fontWeight: FontWeight.w800, fontSize: 10)),
                            ]),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              const Text('Daily Challenge', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                              Text(
                                  '${dailyScore != null ? "Today's best: ${fmt(dailyScore)}" : 'Same pieces for everyone today'} · 🔥 ${s.currentDailyStreak} day streak',
                                  style: TextStyle(color: pal.muted, fontSize: 13)),
                            ]),
                          ),
                        ]),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    for (var k = 0; k < palettes.length; k++)
                      GestureDetector(
                        onTap: () => (s..theme = k).saveSettings(),
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 6),
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: k == s.theme ? pal.text : Colors.transparent, width: 3),
                            gradient: LinearGradient(colors: [palettes[k].bg1, palettes[k].accent]),
                          ),
                        ),
                      ),
                  ]),
                  const SizedBox(height: 16),
                  Row(children: [
                    Expanded(
                        child: pill('🏅 ${s.achievements.length}/${achievementsList.length}', pal,
                            onTap: () => _achievements(context))),
                    const SizedBox(width: 8),
                    Expanded(child: pill('❓ How to play', pal, onTap: () => showHowTo(context))),
                    const SizedBox(width: 8),
                    pill('⚙️', pal, onTap: () => _settings(context)),
                  ]),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _achievements(BuildContext context) {
    final s = Store.I;
    final pal = s.pal;
    Widget row(Widget a, String t, String sub, {bool locked = false, Widget? trail}) => Opacity(
          opacity: locked ? .45 : 1,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(children: [
              a,
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(t, style: const TextStyle(fontWeight: FontWeight.w800)),
                  if (sub.isNotEmpty) Text(sub, style: TextStyle(color: pal.muted, fontSize: 12)),
                ]),
              ),
              ?trail,
            ]),
          ),
        );
    sheet(context, [
      const Text('Achievements', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
      const SizedBox(height: 10),
      for (final a in achievementsList)
        row(
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: pal.surface, borderRadius: BorderRadius.circular(12)),
            child: Text(a.$2, style: const TextStyle(fontSize: 20)),
          ),
          a.$3,
          a.$4,
          locked: !s.achievements.containsKey(a.$1),
          trail: s.achievements.containsKey(a.$1) ? const Text('✓') : null,
        ),
      const Divider(),
      row(const SizedBox(), 'Total lines cleared', '', trail: Text(fmt(s.lines), style: const TextStyle(fontWeight: FontWeight.w900))),
      row(const SizedBox(), 'Average score', '',
          trail: Text(s.games == 0 ? '0' : fmt(s.total ~/ s.games), style: const TextStyle(fontWeight: FontWeight.w900))),
      row(const SizedBox(), 'Most lines in one move', '',
          trail: Text('${s.maxLines}', style: const TextStyle(fontWeight: FontWeight.w900))),
      const SizedBox(height: 10),
      Builder(builder: (ctx) => pill('Close', pal, primary: true, onTap: () => Navigator.pop(ctx))),
    ]);
  }

  void _settings(BuildContext context) {
    sheet(context, [
      StatefulBuilder(builder: (ctx, set) {
        final s = Store.I;
        final pal = s.pal;
        return Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Settings', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
          SwitchListTile(
            title: Text('🔊 Sounds', style: TextStyle(color: pal.text)),
            value: s.sound,
            onChanged: (v) => set(() => (s..sound = v).saveSettings()),
          ),
          SwitchListTile(
            title: Text('📳 Vibration', style: TextStyle(color: pal.text)),
            value: s.haptics,
            onChanged: (v) => set(() => (s..haptics = v).saveSettings()),
          ),
          const SizedBox(height: 10),
          pill('Reset statistics', pal, onTap: () {
            s.resetStats();
            Navigator.pop(ctx);
            toast(context, 'Statistics reset');
            setState(() {});
          }),
          const SizedBox(height: 10),
          pill('Done', pal, primary: true, onTap: () => Navigator.pop(ctx)),
        ]);
      }),
    ]);
  }
}

// ------------------------------------------------------------------ game
class GameScreen extends StatefulWidget {
  final String mode;
  final Game? resume;
  const GameScreen({super.key, this.mode = 'classic', this.resume});
  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _Drag {
  final int k;
  final Shape shape;
  final double lift;
  final bool centred;
  Offset pos;
  (int, int)? target;
  _Drag(this.k, this.shape, this.lift, this.centred, this.pos);
}

class _GameScreenState extends State<GameScreen> with WidgetsBindingObserver {
  final store = Store.I;
  late Game game;
  late bool isDaily;
  late int startBest;
  bool celebrated = false;
  final boardKey = GlobalKey();
  final stackKey = GlobalKey();
  _Drag? drag;
  Preview? preview;
  int selected = -1;
  Map<int, int> clearing = {};
  Set<int> placedNow = {};
  int fxId = 0;
  String? popupPoints, popupText;
  int confettiId = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.resume != null) {
      game = widget.resume!;
    } else if (widget.mode == 'daily') {
      game = Game(seed: hashStr('daily${todayKey()}'), mode: 'daily')..dayKey = todayKey();
    } else {
      game = Game();
    }
    isDaily = game.mode == 'daily';
    startBest = best;
    store.saveGame(game);
    if (game.over) WidgetsBinding.instance.addPostFrameCallback((_) => _stuck());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (!game.over) store.saveGame(game);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s != AppLifecycleState.resumed && !game.over) store.saveGame(game);
  }

  int get best => isDaily ? (store.daily[game.dayKey ?? todayKey()] ?? 0) : store.best;

  // ---- geometry
  ({Offset origin, double pitch, double cell})? _metrics() {
    final box = boardKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return null;
    const pad = 6.0, gap = 3.0;
    final inner = box.size.width - pad * 2;
    final pitch = (inner + gap) / n;
    return (origin: box.localToGlobal(const Offset(pad, pad)), pitch: pitch, cell: pitch - gap);
  }

  Offset _ghostTopLeft(_Drag d, double pitch) {
    final gw = d.shape.w * pitch, gh = d.shape.h * pitch;
    return d.centred ? d.pos - Offset(gw / 2, gh / 2) : d.pos - Offset(gw / 2, gh + d.lift);
  }

  void _startDrag(int k, DragStartDetails det) {
    final s = game.shape(k);
    final m = _metrics();
    if (s == null || m == null || game.over) return;
    final mouse = det.kind == PointerDeviceKind.mouse;
    click();
    setState(() => drag = _Drag(k, s, mouse ? 0 : max(60, m.pitch * 1.6), mouse, det.globalPosition));
    _updateTarget();
  }

  void _moveDrag(DragUpdateDetails det) {
    if (drag == null) return;
    drag!.pos = det.globalPosition;
    _updateTarget();
  }

  void _updateTarget() {
    final d = drag!, m = _metrics()!;
    final tl = _ghostTopLeft(d, m.pitch);
    final r = ((tl.dy - m.origin.dy) / m.pitch).round(), c = ((tl.dx - m.origin.dx) / m.pitch).round();
    final p = game.preview(d.k, r, c);
    setState(() {
      d.target = p == null ? null : (r, c);
      preview = p;
    });
  }

  void _endDrag() {
    final d = drag;
    if (d == null) return;
    setState(() {
      drag = null;
      preview = null;
    });
    if (d.target != null) {
      _place(d.k, d.target!.$1, d.target!.$2);
    } else {
      buzz();
    }
  }

  void _tapBoard(Offset global) {
    if (selected < 0 || drag != null) return;
    final m = _metrics()!;
    final s = game.shape(selected)!;
    final r0 = ((global.dy - m.origin.dy) / m.pitch).floor(), c0 = ((global.dx - m.origin.dx) / m.pitch).floor();
    final r = r0 - (s.h - 1) ~/ 2, c = c0 - (s.w - 1) ~/ 2;
    if (game.canPlace(selected, r, c)) {
      final k = selected;
      selected = -1;
      _place(k, r, c);
    } else {
      buzz(HapticFeedbackType.medium);
      toast(context, "That piece doesn't fit there");
    }
  }

  void _place(int k, int r, int c) {
    final before = List<int>.of(game.board);
    final s = game.shape(k)!;
    final res = game.place(k, r, c);
    if (res == null) return;
    for (final p in res.placed) {
      before[p] = s.color;
    }
    final msgs = <String>[];
    void ach(String id) {
      final m = store.unlock(id);
      if (m != null) msgs.add(m);
    }

    setState(() {
      selected = -1;
      clearing = {for (final p in res.cleared) p: before[p]};
      placedNow = res.placed.where((p) => !res.cleared.contains(p)).toSet();
      fxId++;
      if (res.lines > 0) {
        final word = praise[min(praise.length - 1, res.lines + max(0, res.combo - 1))];
        popupPoints = '+${res.points}';
        popupText = '${res.combo >= 2 ? 'Combo ×${res.combo}! ' : ''}$word';
        if (res.lines >= 3 || res.combo >= 4) confettiId++;
      } else {
        popupPoints = null;
      }
    });
    if (res.lines > 0) {
      buzz(res.lines > 1 ? HapticFeedbackType.heavy : HapticFeedbackType.medium);
      click();
      store.maxLines = max(store.maxLines, res.lines);
      ach('clear1');
      if (res.lines >= 3) ach('multi3');
      if (res.combo >= 3) ach('combo3');
      if (res.combo >= 6) ach('combo6');
    } else {
      buzz();
    }
    if (!celebrated && startBest > 0 && game.score > startBest) {
      celebrated = true;
      confettiId++;
      msgs.add('🏆 New best score!');
    }
    if (msgs.isNotEmpty) toast(context, msgs.join('\n'));
    store.saveGame(game);
    final id = fxId;
    Future.delayed(const Duration(milliseconds: 430), () {
      if (mounted && fxId == id) setState(() => clearing = {});
    });
    Future.delayed(const Duration(milliseconds: 1000), () {
      if (mounted && fxId == id) setState(() => popupPoints = null);
    });
    if (res.over) Future.delayed(const Duration(milliseconds: 650), () => mounted ? _stuck() : null);
  }

  Future<void> _stuck() async {
    final pal = store.pal;
    if (game.shuffles > 0) {
      final use = await sheet<bool>(context, [
        const Text('😮', style: TextStyle(fontSize: 48)),
        const Text('No moves left!', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
        const SizedBox(height: 6),
        Text('Use your free shuffle to get new pieces and keep going?', style: TextStyle(color: pal.muted)),
        const SizedBox(height: 16),
        Builder(
            builder: (ctx) => Row(children: [
                  Expanded(child: pill('End game', pal, onTap: () => Navigator.pop(ctx, false))),
                  const SizedBox(width: 10),
                  Expanded(child: pill('🔀 Shuffle', pal, primary: true, onTap: () => Navigator.pop(ctx, true))),
                ])),
      ], dismissible: false);
      if (!mounted) return;
      if (use == true) {
        _shuffle();
        return;
      }
      game.shuffles = 0;
    }
    _finish();
  }

  void _shuffle() {
    if (!game.shuffle()) return toast(context, 'No shuffles left this game');
    click();
    setState(() {});
    store.saveGame(game);
    if (game.over) Future.delayed(const Duration(milliseconds: 400), () => mounted ? _stuck() : null);
  }

  Future<void> _finish() async {
    final s = store;
    final pal = s.pal;
    s.games++;
    s.total += game.score;
    s.lines += game.lines;
    s.bestCombo = max(s.bestCombo, game.bestCombo);
    final day = game.dayKey ?? todayKey();
    final prevBest = isDaily ? (s.daily[day] ?? 0) : s.best;
    final newBest = game.score > prevBest;
    final msgs = <String?>[];
    if (isDaily) {
      if (!s.daily.containsKey(day)) {
        final y = todayKey(DateTime.now().subtract(const Duration(days: 1)));
        s.dailyStreak = s.lastDaily == y ? s.dailyStreak + 1 : (s.lastDaily == day ? s.dailyStreak : 1);
        s.lastDaily = day;
      }
      s.daily[day] = max(prevBest, game.score);
      msgs.add(s.unlock('daily1'));
      if (s.dailyStreak >= 7) msgs.add(s.unlock('daily7'));
    } else {
      s.best = max(s.best, game.score);
    }
    s.saveStats();
    s.saveGame(null);
    msgs.add(s.unlock('first'));
    if (game.score >= 500) msgs.add(s.unlock('s500'));
    if (game.score >= 1500) msgs.add(s.unlock('s1500'));
    if (game.score >= 3000) msgs.add(s.unlock('s3000'));
    if (s.lines >= 100) msgs.add(s.unlock('lines100'));
    if (s.games >= 25) msgs.add(s.unlock('games25'));
    final shown = msgs.whereType<String>().toList();
    if (shown.isNotEmpty) toast(context, shown.join('\n'));
    if (newBest && prevBest > 0) setState(() => confettiId++);
    buzz(HapticFeedbackType.heavy);
    final again = await sheet<bool>(context, [
      Text(newBest ? '🏆' : '🧱', style: const TextStyle(fontSize: 48)),
      Text(newBest ? (prevBest > 0 ? 'New best!' : 'Great game!') : 'Game over',
          style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900)),
      Text(fmt(game.score), style: const TextStyle(fontSize: 52, fontWeight: FontWeight.w900)),
      Text('${isDaily ? 'Daily best' : 'Best'} ${fmt(max(prevBest, game.score))} · ${game.lines} lines · top combo ×${game.bestCombo}',
          style: TextStyle(color: pal.muted)),
      const SizedBox(height: 16),
      Builder(
          builder: (ctx) => Row(children: [
                Expanded(child: pill('Home', pal, onTap: () => Navigator.pop(ctx, false))),
                const SizedBox(width: 10),
                Expanded(child: pill(isDaily ? 'Try again' : 'Play again', pal, primary: true, onTap: () => Navigator.pop(ctx, true))),
              ])),
    ], dismissible: false);
    if (!mounted) return;
    if (again == true) {
      Navigator.pushReplacement(context, PageRouteBuilder(pageBuilder: (_, _, _) => GameScreen(mode: game.mode)));
    } else {
      Navigator.pop(context);
    }
  }

  Future<void> _menu() async {
    final pal = store.pal;
    final r = await sheet<String>(context, [
      const Text('Paused', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900)),
      Text('${fmt(game.score)} points${isDaily ? ' · Daily Challenge' : ''}', style: TextStyle(color: pal.muted)),
      const SizedBox(height: 16),
      Builder(
          builder: (ctx) => Column(children: [
                pill('▶  Resume', pal, primary: true, onTap: () => Navigator.pop(ctx, 'resume')),
                const SizedBox(height: 10),
                pill('↻  Restart', pal, onTap: () => Navigator.pop(ctx, 'restart')),
                const SizedBox(height: 10),
                pill('🏠  Home${isDaily ? '' : ' (game is saved)'}', pal, onTap: () => Navigator.pop(ctx, 'home')),
              ])),
    ]);
    if (!mounted) return;
    if (r == 'restart') {
      Navigator.pushReplacement(context, PageRouteBuilder(pageBuilder: (_, _, _) => GameScreen(mode: game.mode)));
    } else if (r == 'home') {
      Navigator.pop(context);
    }
  }

  // ---- build
  @override
  Widget build(BuildContext context) {
    final pal = store.pal;
    return Backdrop(
      child: Scaffold(
        body: SafeArea(
          child: Stack(key: stackKey, children: [
            Center(
              child: SingleChildScrollView(
                physics: drag != null ? const NeverScrollableScrollPhysics() : null,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: Column(children: [
                    Row(children: [
                      _iconBtn('☰', _menu),
                      Expanded(
                        child: Column(children: [
                          TweenAnimationBuilder<double>(
                            key: ValueKey(game.score),
                            tween: Tween(begin: 1.15, end: 1),
                            duration: const Duration(milliseconds: 300),
                            builder: (_, v, child) => Transform.scale(scale: v, child: child),
                            child: Text(fmt(game.score),
                                style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w900, height: 1.05)),
                          ),
                          Text('${isDaily ? 'Daily · ' : ''}Best ${fmt(max(best, game.score))}',
                              style: TextStyle(color: pal.muted, fontSize: 13)),
                        ]),
                      ),
                      Opacity(
                        opacity: game.shuffles > 0 ? 1 : .4,
                        child: _iconBtn('🔀', () async {
                          if (game.shuffles <= 0) return toast(context, 'No shuffles left this game');
                          final ok = await sheet<bool>(context, [
                            const Text('Shuffle pieces?', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                            const SizedBox(height: 6),
                            Text('Swap your remaining pieces for new ones. You have 1 shuffle per game.',
                                style: TextStyle(color: pal.muted)),
                            const SizedBox(height: 16),
                            Builder(
                                builder: (ctx) => Row(children: [
                                      Expanded(child: pill('Cancel', pal, onTap: () => Navigator.pop(ctx, false))),
                                      const SizedBox(width: 10),
                                      Expanded(child: pill('🔀 Shuffle', pal, primary: true, onTap: () => Navigator.pop(ctx, true))),
                                    ])),
                          ]);
                          if (ok == true) _shuffle();
                        }),
                      ),
                    ]),
                    const SizedBox(height: 8),
                    Row(children: [
                      Text('Lines ${game.lines}', style: TextStyle(color: pal.muted)),
                      const Spacer(),
                      if (game.combo >= 2)
                        Text('🔥 Combo ×${game.combo}', style: TextStyle(color: pal.accent, fontWeight: FontWeight.w900)),
                    ]),
                    const SizedBox(height: 8),
                    Stack(clipBehavior: Clip.none, children: [
                      _board(pal),
                      if (popupPoints != null)
                        Positioned.fill(
                          child: IgnorePointer(
                            child: Center(
                              child: TweenAnimationBuilder<double>(
                                key: ValueKey(fxId),
                                tween: Tween(begin: 0, end: 1),
                                duration: const Duration(milliseconds: 950),
                                builder: (_, t, _) => Opacity(
                                  opacity: t < .2 ? t * 5 : (t > .8 ? (1 - t) * 5 : 1),
                                  child: Transform.translate(
                                    offset: Offset(0, 14 - 44 * t),
                                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                                      Text(popupPoints!,
                                          style: TextStyle(
                                              fontSize: 38,
                                              fontWeight: FontWeight.w900,
                                              color: pal.accent,
                                              shadows: const [Shadow(offset: Offset(0, 3), color: Colors.black26)])),
                                      Text(popupText ?? '',
                                          style: TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.w800,
                                              color: pal.text,
                                              shadows: const [Shadow(offset: Offset(0, 2), color: Colors.black26)])),
                                    ]),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ]),
                    const SizedBox(height: 16),
                    _tray(pal),
                  ]),
                ),
              ),
            ),
            if (drag != null) _ghost(pal),
            if (confettiId > 0) IgnorePointer(child: Confetti(key: ValueKey(confettiId), colors: pal.blocks)),
          ]),
        ),
      ),
    );
  }

  Widget _iconBtn(String t, VoidCallback onTap) => Material(
        color: store.pal.surface,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: SizedBox(width: 46, height: 46, child: Center(child: Text(t, style: TextStyle(fontSize: 20, color: store.pal.text)))),
        ),
      );

  Widget _board(Palette pal) {
    final pv = preview == null ? <int>{} : preview!.cells.toSet();
    final pvClear = preview?.clears.cells ?? <int>{};
    final pvColor = drag?.shape.color ?? 0;
    return AspectRatio(
      aspectRatio: 1,
      child: GestureDetector(
        onTapUp: (d) => _tapBoard(d.globalPosition),
        child: Container(
          key: boardKey,
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: pal.board,
            borderRadius: BorderRadius.circular(16),
            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 24, offset: Offset(0, 10))],
          ),
          child: LayoutBuilder(builder: (context, cons) {
            const gap = 3.0;
            final cell = (cons.maxWidth - gap * (n - 1)) / n;
            return Stack(children: [
              for (var i = 0; i < n * n; i++)
                Positioned(
                  left: (i % n) * (cell + gap),
                  top: (i ~/ n) * (cell + gap),
                  width: cell,
                  height: cell,
                  child: _cell(i, cell, pal, pv, pvClear, pvColor),
                ),
            ]);
          }),
        ),
      ),
    );
  }

  Widget _cell(int i, double size, Palette pal, Set<int> pv, Set<int> pvClear, int pvColor) {
    final r = i ~/ n, c = i % n;
    final alt = ((r ~/ 3) + (c ~/ 3)) % 2 == 1;
    final base = alt ? pal.cellAlt : pal.cell;
    final color = game.board[i];
    Widget w;
    if (clearing.containsKey(i)) {
      w = TweenAnimationBuilder<double>(
        key: ValueKey('c$fxId-$i'),
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeIn,
        builder: (_, t, child) =>
            Opacity(opacity: 1 - t, child: Transform.rotate(angle: t * .45, child: Transform.scale(scale: 1 - .8 * t, child: child))),
        child: Block(pal.blocks[clearing[i]! - 1], size),
      );
      w = Stack(children: [Container(decoration: BoxDecoration(color: base, borderRadius: BorderRadius.circular(6))), w]);
    } else if (color != 0) {
      final block = Block(pal.blocks[color - 1], size);
      w = placedNow.contains(i)
          ? TweenAnimationBuilder<double>(
              key: ValueKey('p$fxId-$i'),
              tween: Tween(begin: .7, end: 1),
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutBack,
              builder: (_, s, child) => Transform.scale(scale: s, child: child),
              child: block)
          : block;
    } else if (pv.contains(i)) {
      w = Container(
          decoration: BoxDecoration(
              color: Color.lerp(base, pal.blocks[pvColor - 1], .55), borderRadius: BorderRadius.circular(6)));
    } else {
      w = Container(decoration: BoxDecoration(color: base, borderRadius: BorderRadius.circular(6)));
    }
    if (pvClear.contains(i)) {
      w = DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: pal.accent, width: 2),
          boxShadow: [BoxShadow(color: pal.accent.withValues(alpha: .6), blurRadius: 10)],
        ),
        child: w,
      );
    }
    return w;
  }

  Widget _piece(Shape s, double cell, Palette pal, {double gap = 3}) => SizedBox(
        width: s.w * cell + (s.w - 1) * gap,
        height: s.h * cell + (s.h - 1) * gap,
        child: Stack(children: [
          for (final (r, c) in s.cells)
            Positioned(left: c * (cell + gap), top: r * (cell + gap), child: Block(pal.blocks[s.color - 1], cell, radius: cell * .25)),
        ]),
      );

  Widget _tray(Palette pal) => LayoutBuilder(builder: (context, cons) {
        final slotW = (cons.maxWidth - 16) / 3;
        final cell = ((slotW - 24) / 5 - 3).clamp(12.0, 24.0);
        return Row(children: [
          for (var k = 0; k < 3; k++) ...[
            if (k > 0) const SizedBox(width: 8),
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanStart: game.tray[k] == null ? null : (d) => _startDrag(k, d),
                onPanUpdate: _moveDrag,
                onPanEnd: (_) => _endDrag(),
                onPanCancel: () => setState(() {
                  drag = null;
                  preview = null;
                }),
                onTap: game.tray[k] == null
                    ? null
                    : () => setState(() {
                          selected = selected == k ? -1 : k;
                          click();
                        }),
                child: Container(
                  height: 116,
                  decoration: BoxDecoration(
                    color: pal.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: selected == k ? pal.accent : Colors.transparent, width: 3),
                  ),
                  alignment: Alignment.center,
                  child: game.tray[k] == null || drag?.k == k
                      ? null
                      : Opacity(
                          opacity: game.fits(k) ? 1 : .3,
                          child: _piece(game.shape(k)!, cell, pal),
                        ),
                ),
              ),
            ),
          ],
        ]);
      });

  Widget _ghost(Palette pal) {
    final d = drag!;
    final m = _metrics();
    final stackBox = stackKey.currentContext?.findRenderObject() as RenderBox?;
    if (m == null || stackBox == null) return const SizedBox();
    final tl = stackBox.globalToLocal(_ghostTopLeft(d, m.pitch));
    return Positioned(
      left: tl.dx,
      top: tl.dy,
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: const BoxDecoration(boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 16, offset: Offset(0, 8))]),
          child: _piece(d.shape, m.cell, pal, gap: m.pitch - m.cell),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ confetti
class Confetti extends StatefulWidget {
  final List<Color> colors;
  const Confetti({super.key, required this.colors});
  @override
  State<Confetti> createState() => _ConfettiState();
}

class _ConfettiState extends State<Confetti> with SingleTickerProviderStateMixin {
  late final AnimationController ctl = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400))..forward();
  final rnd = Random();
  late final parts = List.generate(110, (_) => (
        x: (rnd.nextDouble() - .5) * .3,
        vx: (rnd.nextDouble() - .5) * 1.4,
        vy: -rnd.nextDouble() * 1.3 - .5,
        rot: rnd.nextDouble() * 6,
        vr: (rnd.nextDouble() - .5) * 12,
        size: 6 + rnd.nextDouble() * 8,
        color: widget.colors[rnd.nextInt(widget.colors.length)],
      ));

  @override
  void dispose() {
    ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: ctl,
        builder: (_, _) => ctl.isCompleted ? const SizedBox.shrink() : CustomPaint(size: Size.infinite, painter: _ConfettiPainter(parts, ctl.value)),
      );
}

class _ConfettiPainter extends CustomPainter {
  final List<({double x, double vx, double vy, double rot, double vr, double size, Color color})> parts;
  final double t;
  _ConfettiPainter(this.parts, this.t);
  @override
  void paint(Canvas canvas, Size size) {
    final time = t * 2.4;
    final paint = Paint();
    for (final p in parts) {
      final x = size.width * (.5 + p.x) + p.vx * size.width * .5 * time;
      final y = size.height * .35 + p.vy * size.height * .5 * time + .9 * size.height * time * time * .5;
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(p.rot + p.vr * time);
      paint.color = p.color.withValues(alpha: (1 - t).clamp(0, 1));
      canvas.drawRect(Rect.fromCenter(center: Offset.zero, width: p.size, height: p.size * .6), paint);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter old) => true;
}
