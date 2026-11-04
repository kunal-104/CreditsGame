import 'package:flutter/material.dart' hide Step;

import 'board.dart';
import 'engine.dart';
import 'game_screen.dart';
import 'store.dart';

class AcademyScreen extends StatelessWidget {
  const AcademyScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final store = AppStore.I;
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Sudoku Academy')),
      body: ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          var n = 0;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
            children: [
              Text(
                  'Seven stages from complete beginner to grandmaster. Each lesson explains one technique, lets you find it in a real puzzle, and gives you practice puzzles that need it.',
                  style: TextStyle(color: cs.onSurfaceVariant)),
              for (final st in store.stages) ...[
                const SizedBox(height: 20),
                Row(children: [
                  CircleAvatar(
                      radius: 13,
                      backgroundColor: Color(levelInfo(st.level).color),
                      child: Text('${st.level}',
                          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold))),
                  const SizedBox(width: 10),
                  Text(st.name, style: Theme.of(context).textTheme.titleLarge),
                ]),
                Padding(
                  padding: const EdgeInsets.only(top: 2, bottom: 8),
                  child: Text(st.tagline, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
                ),
                for (final l in store.lessons.where((l) => l.level == st.level))
                  Builder(builder: (context) {
                    n++;
                    final done = store.academy.contains(l.id);
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: done ? Colors.green : cs.surfaceContainerHighest,
                          foregroundColor: done ? Colors.white : cs.onSurface,
                          child: done ? const Icon(Icons.check) : Text('$n'),
                        ),
                        title: Text(l.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text(l.summary),
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => LessonScreen(lesson: l))),
                      ),
                    );
                  }),
              ],
            ],
          );
        },
      ),
    );
  }
}

class LessonScreen extends StatefulWidget {
  final Lesson lesson;
  const LessonScreen({super.key, required this.lesson});
  @override
  State<LessonScreen> createState() => _LessonScreenState();
}

class _LessonScreenState extends State<LessonScreen> {
  final store = AppStore.I;
  late final List<Example> examples = widget.lesson.tech == null ? [] : store.examplesFor(widget.lesson.tech!);
  int ex = 0, wrongTries = 0, sel = -1;
  bool solved = false, correct = false;
  String feedback = '';

  Lesson get l => widget.lesson;

  Set<int> get _targets {
    final s = examples[ex].step;
    return s.places.isNotEmpty ? s.places.map((p) => p[0]).toSet() : s.elims.map((e) => e[0]).toSet();
  }

  void _tap(int i) {
    if (solved) return;
    setState(() {
      sel = i;
      if (_targets.contains(i)) {
        solved = true;
        correct = true;
        feedback = 'Correct! 🎉';
        store.markLesson(l.id);
      } else {
        wrongTries++;
        feedback = wrongTries >= 2
            ? 'Not this one. Tap "Show me" if you need help.'
            : 'Not quite. Look at the highlighted area again.';
      }
    });
  }

  void _load(int i) => setState(() {
        ex = i;
        solved = false;
        correct = false;
        wrongTries = 0;
        sel = -1;
        feedback = '';
      });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final idx = store.lessons.indexOf(l);
    final next = idx + 1 < store.lessons.length ? store.lessons[idx + 1] : null;
    final prev = idx > 0 ? store.lessons[idx - 1] : null;

    Widget? tryIt;
    if (examples.isNotEmpty) {
      final e = examples[ex];
      final showCands = techniques[l.tech]!.level >= 3;
      final cand = [
        for (var i = 0; i < 81; i++) (showCands || (solved && e.step.cells.contains(i))) ? e.cand[i] : 0
      ];
      tryIt = Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text('Try it', style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              Text('Example ${ex + 1} of ${examples.length}', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
            ]),
            const SizedBox(height: 4),
            Text(l.task ?? 'Find the move.'),
            const SizedBox(height: 10),
            SudokuBoard(
              model: BoardModel(
                grid: e.grid,
                notes: List.filled(81, 0),
                given: e.grid.map((v) => v != 0).toList(),
                selected: sel,
                highlightPeers: false,
                highlightSame: false,
                overlay: BoardOverlay.fromStep(e.step, cand, solved),
              ),
              onTap: _tap,
            ),
            const SizedBox(height: 10),
            if (feedback.isNotEmpty)
              Text(feedback,
                  style: TextStyle(fontWeight: FontWeight.w700, color: correct ? Colors.green : cs.error)),
            if (solved) ...[const SizedBox(height: 6), Text(e.step.text)],
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              OutlinedButton(onPressed: solved ? null : () => setState(() => solved = true), child: const Text('Show me')),
              OutlinedButton(onPressed: () => _load((ex + 1) % examples.length), child: const Text('Another example')),
              FilledButton.icon(
                icon: const Icon(Icons.play_arrow_rounded),
                onPressed: () {
                  store.startGame(store.practicePuzzle(l.tech!), mode: 'practice', lesson: l.id);
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const GameScreen()));
                },
                label: const Text('Practice puzzle'),
              ),
            ]),
          ]),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(l.title)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
            children: [
              Text('Stage ${l.level} · ${levelInfo(l.level).name}', style: TextStyle(color: cs.onSurfaceVariant)),
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    for (final p in l.body)
                      Padding(padding: const EdgeInsets.only(bottom: 10), child: Text(p, style: const TextStyle(height: 1.45))),
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.symmetric(vertical: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: cs.primaryContainer,
                        border: Border(left: BorderSide(color: cs.primary, width: 4)),
                      ),
                      child: Text(l.keyIdea, style: TextStyle(fontWeight: FontWeight.w700, color: cs.onPrimaryContainer)),
                    ),
                    Text('💡 ${l.tip}', style: TextStyle(color: cs.onSurfaceVariant)),
                  ]),
                ),
              ),
              if (tryIt != null)
                tryIt
              else
                FilledButton(
                  onPressed: () {
                    store.markLesson(l.id);
                    if (next != null) {
                      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => LessonScreen(lesson: next)));
                    } else {
                      Navigator.pop(context);
                    }
                  },
                  child: const Text('Mark as complete'),
                ),
              const SizedBox(height: 12),
              Row(children: [
                if (prev != null)
                  Flexible(
                    child: TextButton(
                      onPressed: () =>
                          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => LessonScreen(lesson: prev))),
                      child: Text('← ${prev.title}', overflow: TextOverflow.ellipsis),
                    ),
                  ),
                const Spacer(),
                if (next != null)
                  Flexible(
                    child: TextButton(
                      onPressed: () =>
                          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => LessonScreen(lesson: next))),
                      child: Text('${next.title} →', overflow: TextOverflow.ellipsis),
                    ),
                  ),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}
