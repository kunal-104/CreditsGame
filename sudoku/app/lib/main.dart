import 'dart:math';

import 'package:flutter/material.dart';

import 'engine.dart';
import 'game_screen.dart';
import 'lesson_screen.dart';
import 'store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppStore.load();
  runApp(const SudokuSenseiApp());
}

const _levelDesc = {
  1: 'Singles only, great for learning',
  2: 'Row and column scanning',
  3: 'Pointing and claiming',
  4: 'Pairs and triples',
  5: 'X-Wings and XY-Wings',
  6: 'Colouring, Swordfish, UR',
  7: 'XY-Chains, the hardest level',
};

class SudokuSenseiApp extends StatelessWidget {
  const SudokuSenseiApp({super.key});
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppStore.I,
      builder: (context, _) => MaterialApp(
        title: 'Sudoku Sensei',
        debugShowCheckedModeBanner: false,
        themeMode: AppStore.I.themeMode,
        theme: ThemeData(
          colorSchemeSeed: const Color(0xFF4F46E5),
          scaffoldBackgroundColor: const Color(0xFFF6F7FB),
          cardTheme: const CardThemeData(elevation: 0, color: Colors.white),
        ),
        darkTheme: ThemeData(
          colorSchemeSeed: const Color(0xFF4F46E5),
          brightness: Brightness.dark,
          scaffoldBackgroundColor: const Color(0xFF0F111A),
          cardTheme: const CardThemeData(elevation: 0, color: Color(0xFF181B28)),
        ),
        home: const HomeScreen(),
      ),
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  void _play(BuildContext context) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => const GameScreen()));

  Future<void> _startLevel(BuildContext context, int level) async {
    final store = AppStore.I;
    final g = store.game;
    final inProgress = g != null && !g.done && List.generate(81, (i) => i).any((i) => g.grid[i] != 0 && !g.given[i]);
    if (inProgress) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Start a new game?'),
          content: const Text('Your current game will be lost.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('New game')),
          ],
        ),
      );
      if (ok != true) return;
    }
    store.startGame(store.pickPuzzle(level, Random()));
    if (context.mounted) _play(context);
  }

  @override
  Widget build(BuildContext context) {
    final store = AppStore.I;
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text.rich(TextSpan(children: [
          TextSpan(text: 'Sudoku '),
          TextSpan(text: 'Sensei', style: TextStyle(color: Color(0xFF6D64F2), fontWeight: FontWeight.w800)),
        ])),
        actions: [
          IconButton(
              tooltip: 'Statistics',
              icon: const Icon(Icons.bar_chart_rounded),
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const StatsScreen()))),
          IconButton(
              tooltip: 'Settings',
              icon: const Icon(Icons.settings_outlined),
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()))),
        ],
      ),
      body: ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          final g = store.game;
          final doneToday = store.dailyDone[todayKey()];
          final learned = store.lessons.where((l) => store.academy.contains(l.id)).length;
          final total = store.lessons.length;
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                children: [
                  Text('Learn it. Master it.',
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text('Every puzzle can be solved by logic, and every hint teaches you the technique behind it.',
                      style: TextStyle(color: cs.onSurfaceVariant)),
                  const SizedBox(height: 16),
                  if (g != null && !g.done)
                    Card(
                      child: ListTile(
                        title: const Text('Continue game', style: TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text('${levelInfo(g.level).name} · ${fmtTime(g.time)}'),
                        trailing: FilledButton(onPressed: () => _play(context), child: const Text('Resume')),
                      ),
                    ),
                  Container(
                    margin: const EdgeInsets.only(bottom: 12, top: 4),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      gradient: const LinearGradient(colors: [Color(0xFF4F46E5), Color(0xFF8B5CF6)]),
                    ),
                    child: Row(children: [
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const Text('Daily Challenge',
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
                          Text(levelInfo(store.dailyLevel).name, style: const TextStyle(color: Colors.white70)),
                          Text('🔥 ${store.currentStreak} day streak', style: const TextStyle(color: Colors.white)),
                        ]),
                      ),
                      FilledButton(
                        style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: const Color(0xFF3730A3)),
                        onPressed: () {
                          if (doneToday != null) {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                content: Text('Solved today in ${fmtTime(doneToday)}. Come back tomorrow!')));
                            return;
                          }
                          store.startGame(store.dailyPuzzle(), mode: 'daily', day: todayKey());
                          _play(context);
                        },
                        child: Text(doneToday != null ? 'Done ✓' : 'Play'),
                      ),
                    ]),
                  ),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          const Expanded(
                              child: Text('Sudoku Academy', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
                          Text('$learned/$total lessons', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
                        ]),
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(99),
                          child: LinearProgressIndicator(value: learned / total, minHeight: 8),
                        ),
                        const SizedBox(height: 10),
                        Text(
                            '$total lessons, from your first digit to XY-Chains. Each one has real examples to try and practice puzzles.',
                            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: () =>
                                Navigator.push(context, MaterialPageRoute(builder: (_) => const AcademyScreen())),
                            child: Text(learned > 0 ? 'Continue learning' : 'Start learning'),
                          ),
                        ),
                      ]),
                    ),
                  ),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('New game', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                        const SizedBox(height: 10),
                        GridView.count(
                          crossAxisCount: 2,
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          mainAxisSpacing: 10,
                          crossAxisSpacing: 10,
                          childAspectRatio: 2.0,
                          children: [
                            for (final lv in levels)
                              Material(
                                color: cs.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(12),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(12),
                                  onTap: () => _startLevel(context, lv.id),
                                  child: Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                      Row(children: [
                                        CircleAvatar(radius: 5, backgroundColor: Color(lv.color)),
                                        const SizedBox(width: 6),
                                        Text(lv.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                                      ]),
                                      const SizedBox(height: 2),
                                      Text(_levelDesc[lv.id]!,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
                                    ]),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ]),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class StatsScreen extends StatelessWidget {
  const StatsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final store = AppStore.I;
    final cs = Theme.of(context).colorScheme;
    final won = store.stats.values.fold<int>(0, (a, s) => a + s.won);
    final learned = store.lessons.where((l) => store.academy.contains(l.id)).length;
    Widget tile(String big, String small) => Expanded(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Column(children: [
                Text(big, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                Text(small, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
              ]),
            ),
          ),
        );
    return Scaffold(
      appBar: AppBar(title: const Text('Statistics')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Row(children: [
          tile('$won', 'solved'),
          tile('🔥 ${store.currentStreak}', 'daily streak'),
          tile('$learned/${store.lessons.length}', 'lessons'),
        ]),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: DataTable(
              columnSpacing: 14,
              horizontalMargin: 8,
              columns: const [
                DataColumn(label: Text('Level')),
                DataColumn(label: Text('Won'), numeric: true),
                DataColumn(label: Text('Best'), numeric: true),
                DataColumn(label: Text('Avg'), numeric: true),
                DataColumn(label: Text('Flawless'), numeric: true),
              ],
              rows: [
                for (final lv in levels)
                  () {
                    final s = store.stats['${lv.id}'] ?? LevelStats();
                    return DataRow(cells: [
                      DataCell(Text(lv.name)),
                      DataCell(Text('${s.won}/${s.played}')),
                      DataCell(Text(s.best != null ? fmtTime(s.best!) : '–')),
                      DataCell(Text(s.won > 0 ? fmtTime(s.total ~/ s.won) : '–')),
                      DataCell(Text('${s.flawless}')),
                    ]);
                  }(),
              ],
            ),
          ),
        ),
      ]),
    );
  }
}

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final s = AppStore.I;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListenableBuilder(
        listenable: s,
        builder: (context, _) => ListView(padding: const EdgeInsets.all(16), children: [
          Card(
            child: Column(children: [
              SwitchListTile(
                title: const Text('Highlight row, column and box'),
                value: s.highlightPeers,
                onChanged: (v) => (s..highlightPeers = v).saveSettings(),
              ),
              SwitchListTile(
                title: const Text('Highlight matching digits'),
                value: s.highlightSame,
                onChanged: (v) => (s..highlightSame = v).saveSettings(),
              ),
              SwitchListTile(
                title: const Text('Show mistakes immediately'),
                value: s.showMistakes,
                onChanged: (v) => (s..showMistakes = v).saveSettings(),
              ),
              SwitchListTile(
                title: const Text('Auto-remove notes'),
                subtitle: const Text('Placing a digit removes it from notes in the same row, column and box'),
                value: s.autoRemoveNotes,
                onChanged: (v) => (s..autoRemoveNotes = v).saveSettings(),
              ),
              SwitchListTile(
                title: const Text('Show timer'),
                value: s.showTimer,
                onChanged: (v) => (s..showTimer = v).saveSettings(),
              ),
              ListTile(
                title: const Text('Theme'),
                trailing: DropdownButton<ThemeMode>(
                  value: s.themeMode,
                  onChanged: (v) => (s..themeMode = v!).saveSettings(),
                  items: const [
                    DropdownMenuItem(value: ThemeMode.system, child: Text('System')),
                    DropdownMenuItem(value: ThemeMode.light, child: Text('Light')),
                    DropdownMenuItem(value: ThemeMode.dark, child: Text('Dark')),
                  ],
                ),
              ),
            ]),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Reset everything?'),
                  content: const Text('Statistics, lessons, streak and your current game will be deleted.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                    FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Reset')),
                  ],
                ),
              );
              if (ok == true) s.resetAll();
            },
            child: const Text('Reset all progress'),
          ),
        ]),
      ),
    );
  }
}
