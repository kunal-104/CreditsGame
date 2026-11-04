import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart' hide Step;
import 'package:flutter/services.dart';

import 'board.dart';
import 'engine.dart';
import 'lesson_screen.dart';
import 'store.dart';

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});
  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _Snapshot {
  final List<int> grid, notes;
  _Snapshot(this.grid, this.notes);
}

class _GameScreenState extends State<GameScreen> with WidgetsBindingObserver {
  final store = AppStore.I;
  GameData get g => store.game!;
  late List<int> sol = g.sol;
  int selected = -1;
  bool notesMode = false;
  bool paused = false;
  Hint? hint;
  int hintIndex = 0;
  bool hintReveal = false;
  Set<int> flash = {};
  final List<_Snapshot> history = [];
  Timer? timer;
  final focus = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    selected = g.grid.indexWhere((v) => v == 0);
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (g.done || paused || !mounted) return;
      setState(() => g.time++);
      if (g.time % 5 == 0) store.saveGame();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    timer?.cancel();
    store.saveGame();
    focus.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && !g.done) {
      store.saveGame();
      if (!paused) setState(() => paused = true);
    }
  }

  void _snap() {
    history.add(_Snapshot(List.of(g.grid), List.of(g.notes)));
    if (history.length > 300) history.removeAt(0);
  }

  void _input(int d) {
    if (g.done || selected < 0 || g.given[selected]) return;
    _closeHint();
    setState(() {
      if (notesMode) {
        if (g.grid[selected] != 0) return;
        _snap();
        g.notes[selected] ^= 1 << d;
      } else {
        if (g.grid[selected] == d) return;
        _snap();
        g.grid[selected] = d;
        g.notes[selected] = 0;
        if (d != sol[selected]) {
          g.mistakes++;
          HapticFeedback.mediumImpact();
        } else if (store.autoRemoveNotes) {
          for (final p in peers[selected]) {
            g.notes[p] &= ~(1 << d);
          }
        }
      }
    });
    store.saveGame();
    _checkWin();
  }

  void _erase() {
    if (g.done || selected < 0 || g.given[selected]) return;
    if (g.grid[selected] == 0 && g.notes[selected] == 0) return;
    setState(() {
      _snap();
      g.grid[selected] = 0;
      g.notes[selected] = 0;
    });
    store.saveGame();
  }

  void _undo() {
    _closeHint();
    if (history.isEmpty) return _toast('Nothing to undo');
    final h = history.removeLast();
    setState(() {
      g.grid = h.grid;
      g.notes = h.notes;
    });
    store.saveGame();
  }

  void _autoNotes() {
    if (g.done) return;
    final s = makeState(g.grid);
    setState(() {
      _snap();
      for (var i = 0; i < 81; i++) {
        g.notes[i] = g.grid[i] != 0 ? 0 : s.cand[i];
      }
    });
    store.saveGame();
    _toast('All candidates filled in');
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));
  }

  void _checkWin() {
    if (g.grid.join() != sol.join()) return;
    g.done = true;
    final best = store.recordWin();
    final perfect = g.hints == 0 && g.mistakes == 0;
    Future.delayed(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: Text(perfect ? '🏆' : '🎉', style: const TextStyle(fontSize: 48)),
          title: Text(perfect ? 'Flawless!' : 'Solved!'),
          content: Text(
            '${levelInfo(g.level).name} · ${fmtTime(g.time)}${best ? ' · New best!' : ''}\n${g.mistakes} mistakes · ${g.hints} hints',
            textAlign: TextAlign.center,
          ),
          actions: [
            TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  Navigator.pop(context);
                },
                child: const Text('Home')),
            FilledButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  store.startGame(store.pickPuzzle(g.level, Random()));
                  Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const GameScreen()));
                },
                child: const Text('Next puzzle')),
          ],
        ),
      );
    });
    setState(() {});
  }

  // ---------------- hints ----------------
  void _openHint() {
    if (g.done) return;
    final h = computeHint(g.grid, sol);
    if (h.kind == 'solved') return;
    if (h.kind == 'stuck') return _toast('No logical step found');
    setState(() {
      hint = h;
      hintIndex = 0;
      hintReveal = h.kind == 'steps' && h.steps.first.step.tech == 'reveal';
      if (h.kind == 'steps') g.hints++;
    });
    store.saveGame();
  }

  void _closeHint() {
    if (hint != null) setState(() => hint = null);
  }

  void _applyHint() {
    _snap();
    final notesInUse = g.notes.any((n) => n != 0);
    setState(() {
      for (final hs in hint!.steps) {
        if (notesInUse) {
          for (final e in hs.step.elims) {
            g.notes[e[0]] &= ~(1 << e[1]);
          }
        }
        for (final p in hs.step.places) {
          g.grid[p[0]] = p[1];
          g.notes[p[0]] = 0;
          if (store.autoRemoveNotes) {
            for (final q in peers[p[0]]) {
              g.notes[q] &= ~(1 << p[1]);
            }
          }
          selected = p[0];
          flash = {p[0]};
        }
      }
      hint = null;
    });
    store.saveGame();
    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted) setState(() => flash = {});
    });
    _checkWin();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    final ch = e.character;
    if (ch != null && ch.length == 1 && '123456789'.contains(ch)) {
      _input(int.parse(ch));
      return KeyEventResult.handled;
    }
    int? dr, dc;
    if (k == LogicalKeyboardKey.arrowUp) dr = -1;
    if (k == LogicalKeyboardKey.arrowDown) dr = 1;
    if (k == LogicalKeyboardKey.arrowLeft) dc = -1;
    if (k == LogicalKeyboardKey.arrowRight) dc = 1;
    if (dr != null || dc != null) {
      final s = selected < 0 ? 0 : selected;
      setState(() => selected = ((rowOf(s) + (dr ?? 0) + 9) % 9) * 9 + (colOf(s) + (dc ?? 0) + 9) % 9);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.backspace || k == LogicalKeyboardKey.delete) {
      _erase();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.keyN) {
      setState(() => notesMode = !notesMode);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.keyH) {
      hint == null ? _openHint() : _closeHint();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.keyZ && HardwareKeyboard.instance.isControlPressed) {
      _undo();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final lvl = levelInfo(g.level);
    final cs = Theme.of(context).colorScheme;
    BoardOverlay? overlay;
    if (hint != null && hint!.kind == 'steps') {
      final hs = hint!.steps[hintIndex];
      overlay = BoardOverlay.fromStep(hs.step, hs.state.cand, hintReveal);
    }
    final model = BoardModel(
      grid: g.grid,
      notes: g.notes,
      given: g.given,
      selected: hint != null ? -1 : selected,
      solution: sol,
      showMistakes: store.showMistakes,
      highlightPeers: store.highlightPeers,
      highlightSame: store.highlightSame,
      overlay: overlay,
      flash: hint?.kind == 'mistake' ? hint!.cells.toSet() : flash,
    );
    final counts = List.filled(10, 0);
    for (var i = 0; i < 81; i++) {
      if (g.grid[i] != 0 && g.grid[i] == sol[i]) counts[g.grid[i]]++;
    }
    final modeLabel = g.mode == 'daily' ? 'Daily · ' : g.mode == 'practice' ? 'Practice · ' : '';

    final boardArea = Column(children: [
      Row(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(color: Color(lvl.color), borderRadius: BorderRadius.circular(99)),
          child: Text('$modeLabel${lvl.name}',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12)),
        ),
        const Spacer(),
        Text('✗ ${g.mistakes}   💡 ${g.hints}   ', style: TextStyle(color: cs.onSurfaceVariant)),
        if (store.showTimer)
          Text(fmtTime(g.time),
              style: TextStyle(color: cs.onSurfaceVariant, fontFeatures: const [FontFeature.tabularFigures()])),
        IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Pause',
            onPressed: () => setState(() => paused = true),
            icon: const Icon(Icons.pause_rounded)),
      ]),
      const SizedBox(height: 6),
      Stack(children: [
        SudokuBoard(
            model: model,
            onTap: (i) => setState(() {
                  selected = i;
                  hint = null;
                })),
        if (paused)
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(color: cs.surface, borderRadius: BorderRadius.circular(10)),
              child: Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Text('⏸', style: TextStyle(fontSize: 40)),
                  Text('Paused · ${fmtTime(g.time)}'),
                  const SizedBox(height: 12),
                  FilledButton(onPressed: () => setState(() => paused = false), child: const Text('Resume')),
                ]),
              ),
            ),
          ),
      ]),
    ]);

    final controls = Column(children: [
      const SizedBox(height: 12),
      Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
        _Tool(icon: Icons.undo_rounded, label: 'Undo', onTap: _undo),
        _Tool(icon: Icons.backspace_outlined, label: 'Erase', onTap: _erase),
        _Tool(
            icon: Icons.edit_outlined,
            label: notesMode ? 'Notes ON' : 'Notes',
            active: notesMode,
            onTap: () => setState(() => notesMode = !notesMode)),
        _Tool(icon: Icons.grid_view_rounded, label: 'Auto notes', onTap: _autoNotes),
        _Tool(
            icon: Icons.lightbulb_outline_rounded,
            label: 'Hint',
            active: hint != null,
            onTap: () => hint == null ? _openHint() : _closeHint()),
      ]),
      const SizedBox(height: 8),
      if (hint != null)
        _HintPanel(
          hint: hint!,
          index: hintIndex,
          reveal: hintReveal,
          onClose: _closeHint,
          onReveal: () => setState(() => hintReveal = true),
          onPrev: () => setState(() => hintIndex--),
          onNext: () => setState(() => hintIndex++),
          onApply: _applyHint,
          onFixMistakes: () {
            setState(() {
              _snap();
              for (final c in hint!.cells) {
                g.grid[c] = 0;
              }
              hint = null;
            });
            store.saveGame();
          },
        )
      else
        Row(children: [
          for (var d = 1; d <= 9; d++)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: _NumKey(
                  digit: d,
                  remaining: 9 - counts[d],
                  notesMode: notesMode,
                  onTap: counts[d] >= 9 || g.done ? null : () => _input(d),
                ),
              ),
            ),
        ]),
    ]);

    return Focus(
      focusNode: focus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: Scaffold(
        appBar: AppBar(title: const Text('Sudoku Sensei')),
        body: SafeArea(
          child: LayoutBuilder(builder: (context, c) {
            final wide = c.maxWidth > 820;
            final content = wide
                ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(child: boardArea),
                    const SizedBox(width: 24),
                    SizedBox(width: 320, child: controls),
                  ])
                : Column(children: [boardArea, controls]);
            return Align(
              alignment: Alignment.topCenter,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                child: ConstrainedBox(constraints: BoxConstraints(maxWidth: wide ? 900 : 520), child: content),
              ),
            );
          }),
        ),
      ),
    );
  }
}

class _Tool extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _Tool({required this.icon, required this.label, required this.onTap, this.active = false});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = active ? cs.primary : cs.onSurfaceVariant;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Column(children: [
          Icon(icon, color: color),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(fontSize: 11, color: color)),
        ]),
      ),
    );
  }
}

class _NumKey extends StatelessWidget {
  final int digit, remaining;
  final bool notesMode;
  final VoidCallback? onTap;
  const _NumKey({required this.digit, required this.remaining, required this.notesMode, this.onTap});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Opacity(
      opacity: onTap == null ? .25 : 1,
      child: Material(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(children: [
              Text('$digit',
                  style: TextStyle(fontSize: 26, color: notesMode ? cs.onSurfaceVariant : cs.primary, height: 1.1)),
              Text(remaining > 0 ? '$remaining' : '', style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant)),
            ]),
          ),
        ),
      ),
    );
  }
}

class _HintPanel extends StatelessWidget {
  final Hint hint;
  final int index;
  final bool reveal;
  final VoidCallback onClose, onReveal, onPrev, onNext, onApply, onFixMistakes;
  const _HintPanel({
    required this.hint,
    required this.index,
    required this.reveal,
    required this.onClose,
    required this.onReveal,
    required this.onPrev,
    required this.onNext,
    required this.onApply,
    required this.onFixMistakes,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final pal = BoardPalette.of(context);
    Widget body;
    if (hint.kind == 'mistake') {
      final n = hint.cells.length;
      body = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Check these cells', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 6),
        Text(
            '${n == 1 ? 'One of your digits is' : '$n of your digits are'} wrong (${hint.cells.map(cellName).join(', ')}). Fix ${n == 1 ? 'it' : 'them'} before continuing.'),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: OutlinedButton(onPressed: onClose, child: const Text('Close'))),
          const SizedBox(width: 10),
          Expanded(child: FilledButton(onPressed: onFixMistakes, child: Text('Remove ${n == 1 ? 'it' : 'them'}'))),
        ]),
      ]);
    } else {
      final step = hint.steps[index].step;
      final t = techniques[step.tech]!;
      final last = index == hint.steps.length - 1;
      final lesson = AppStore.I.lessonForTech(step.tech);
      body = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(99)),
            child: Text(t.name, style: TextStyle(color: cs.onPrimaryContainer, fontWeight: FontWeight.w700, fontSize: 12)),
          ),
          const SizedBox(width: 8),
          if (hint.steps.length > 1)
            Text('Step ${index + 1} of ${hint.steps.length}', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
        ]),
        const SizedBox(height: 8),
        if (!reveal) ...[
          Text.rich(TextSpan(children: [
            const TextSpan(text: "There's a "),
            TextSpan(text: t.name, style: const TextStyle(fontWeight: FontWeight.bold)),
            const TextSpan(text: ' in the highlighted area. Can you spot it?'),
          ])),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: OutlinedButton(onPressed: onClose, child: const Text("I'll find it"))),
            const SizedBox(width: 10),
            Expanded(child: FilledButton(onPressed: onReveal, child: const Text('Show me'))),
          ]),
        ] else ...[
          Text(step.text),
          const SizedBox(height: 8),
          Wrap(spacing: 12, children: [
            _legend(pal.key, 'key'),
            _legend(pal.alt, 'linked'),
            _legend(pal.elim, 'remove'),
            _legend(pal.place, 'solve'),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            if (index > 0) ...[OutlinedButton(onPressed: onPrev, child: const Text('Back')), const SizedBox(width: 10)],
            Expanded(
                child: last
                    ? FilledButton(onPressed: onApply, child: const Text('Apply'))
                    : FilledButton(onPressed: onNext, child: const Text('Next step'))),
          ]),
          if (lesson != null)
            TextButton(
              onPressed: () =>
                  Navigator.push(context, MaterialPageRoute(builder: (_) => LessonScreen(lesson: lesson))),
              child: Text('Learn ${t.name} in the Academy →'),
            ),
        ],
      ]);
    }
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(padding: const EdgeInsets.all(16), child: body),
    );
  }

  Widget _legend(Color c, String label) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 12, height: 12, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 12)),
      ]);
}
