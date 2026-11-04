import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'data.dart';

const good = Color(0xFF16A34A), bad = Color(0xFFE11D48), accent = Color(0xFFFF6B3D);

class PlayScreen extends StatefulWidget {
  final String title, kind;
  final List<Fact> facts;
  final List<Fact> Function()? replayPool;
  const PlayScreen({super.key, required this.title, required this.facts, this.kind = 'mix', this.replayPool});
  @override
  State<PlayScreen> createState() => _PlayScreenState();
}

class _PlayScreenState extends State<PlayScreen> {
  final c = Curio.I;
  late List<Fact> facts = widget.facts;
  int i = 0, score = 0, combo = 0, xpEarned = 0, newFacts = 0, lastGain = 0;
  bool? lastCorrect; // null = not answered yet
  double drag = 0;
  final results = <(Fact, bool)>[];
  bool finished = false;

  void _answer(bool said) {
    if (lastCorrect != null) return;
    final f = facts[i];
    final correct = said == f.a;
    if (!c.answers.containsKey(f.id)) newFacts++;
    final gain = correct ? 10 + min(combo, 5) * 2 : 3;
    combo = correct ? combo + 1 : 0;
    c.recordAnswer(f, correct, combo);
    c.addXp(gain);
    if (correct) score++;
    xpEarned += gain;
    results.add((f, correct));
    correct ? HapticFeedback.lightImpact() : HapticFeedback.heavyImpact();
    setState(() {
      lastCorrect = correct;
      lastGain = gain;
      drag = 0;
    });
    final msg = c.levelUpMessage;
    if (msg != null) {
      c.levelUpMessage = null;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  void _next() {
    setState(() {
      i++;
      lastCorrect = null;
      if (i >= facts.length) _finish();
    });
  }

  void _finish() {
    finished = true;
    if (widget.kind == 'daily' && results.length == facts.length) c.recordDaily(score, results.length);
  }

  void _again() {
    final pool = widget.replayPool?.call() ?? c.facts;
    setState(() {
      facts = c.buildSession(pool);
      i = score = combo = xpEarned = newFacts = 0;
      lastCorrect = null;
      results.clear();
      finished = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => results.isNotEmpty && !finished ? setState(_finish) : Navigator.pop(context),
        ),
        title: finished
            ? Text(widget.title)
            : ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: LinearProgressIndicator(value: i / facts.length, minHeight: 10, color: accent),
              ),
        actions: [
          if (!finished)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: Text(combo >= 2 ? '🔥×$combo' : '${i + 1}/${facts.length}',
                    style: const TextStyle(fontWeight: FontWeight.w800, color: accent)),
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: finished ? _summary(context) : _card(context),
          ),
        ),
      ),
    );
  }

  Widget _card(BuildContext context) {
    final f = facts[i];
    final cat = c.cat[f.c]!;
    final cs = Theme.of(context).colorScheme;
    final answered = lastCorrect != null;
    final card = Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(26), side: BorderSide(color: cat.color.withValues(alpha: .5), width: 2)),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            Chip(
              label: Text('${cat.emoji} ${cat.name}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
              backgroundColor: cat.color.withValues(alpha: .15),
              side: BorderSide.none,
              visualDensity: VisualDensity.compact,
            ),
            const SizedBox(width: 8),
            Text(f.r.map(flagOf).join(' '), style: const TextStyle(fontSize: 18)),
            const Spacer(),
            if (answered) Text('+$lastGain XP', style: const TextStyle(color: accent, fontWeight: FontWeight.w900)),
          ]),
          const SizedBox(height: 14),
          Text(f.s, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, height: 1.35)),
          const SizedBox(height: 20),
          if (!answered) ...[
            Row(children: [
              Expanded(child: _bigButton('✗  Myth', bad, () => _answer(false))),
              const SizedBox(width: 12),
              Expanded(child: _bigButton('✓  Fact', good, () => _answer(true))),
            ]),
            const SizedBox(height: 10),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('← swipe', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
              Text('swipe →', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
            ]),
          ] else ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                  color: (lastCorrect! ? good : bad).withValues(alpha: .12), borderRadius: BorderRadius.circular(16)),
              child: Row(children: [
                Text(lastCorrect! ? '✓ Correct!' : '✗ Not quite',
                    style: TextStyle(color: lastCorrect! ? good : bad, fontWeight: FontWeight.w800, fontSize: 16)),
                const Spacer(),
                Text(f.a ? 'It’s a FACT' : 'It’s a MYTH', style: const TextStyle(fontWeight: FontWeight.w700)),
              ]),
            ),
            const SizedBox(height: 12),
            Text(f.e, style: const TextStyle(fontSize: 16, height: 1.5)),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: accent, padding: const EdgeInsets.all(14)),
                  onPressed: _next,
                  child: Text(i + 1 < facts.length ? 'Next →' : 'See results'),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                  onPressed: () => launchUrl(wikiUri(f.w), mode: LaunchMode.externalApplication),
                  child: const Text('Learn more ↗')),
              IconButton(
                tooltip: 'Save',
                onPressed: () => setState(() => c.toggleSaveFact(f.id)),
                icon: Icon(c.isSaved(f.id) ? Icons.star_rounded : Icons.star_outline_rounded, color: accent),
              ),
            ]),
          ],
        ]),
      ),
    );

    return ListView(padding: const EdgeInsets.all(16), children: [
      GestureDetector(
        onHorizontalDragUpdate: answered ? null : (d) => setState(() => drag += d.delta.dx),
        onHorizontalDragEnd: answered
            ? null
            : (_) {
                if (drag.abs() > 90) {
                  _answer(drag > 0);
                } else {
                  setState(() => drag = 0);
                }
              },
        child: Stack(children: [
          AnimatedContainer(
            duration: Duration(milliseconds: drag == 0 ? 220 : 0),
            transform: Matrix4.translationValues(drag, 0, 0)..rotateZ(drag / 900),
            child: card,
          ),
          if (drag.abs() > 20)
            Positioned(
              top: 70,
              left: drag < 0 ? 24 : null,
              right: drag > 0 ? 24 : null,
              child: Opacity(
                opacity: min(1, drag.abs() / 90),
                child: Transform.rotate(
                  angle: drag > 0 ? .2 : -.2,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                        border: Border.all(color: drag > 0 ? good : bad, width: 4),
                        borderRadius: BorderRadius.circular(12)),
                    child: Text(drag > 0 ? 'FACT' : 'MYTH',
                        style: TextStyle(color: drag > 0 ? good : bad, fontWeight: FontWeight.w900, fontSize: 22)),
                  ),
                ),
              ),
            ),
        ]),
      ),
    ]);
  }

  Widget _bigButton(String label, Color color, VoidCallback onTap) => FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: color.withValues(alpha: .14),
          foregroundColor: color,
          padding: const EdgeInsets.symmetric(vertical: 18),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
        ),
        onPressed: onTap,
        child: Text(label),
      );

  Widget _summary(BuildContext context) {
    final total = results.length;
    final pct = total == 0 ? 0 : score / total;
    final msg = pct == 1
        ? 'Perfect round! 🏆'
        : pct >= .7
            ? 'Impressive! 🎉'
            : pct >= .4
                ? 'Nice, and you learned something new! 📚'
                : 'Every wrong answer is a new fact learned. 🌱';
    final cs = Theme.of(context).colorScheme;
    return ListView(padding: const EdgeInsets.all(16), children: [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(children: [
            Text('$score/$total', style: const TextStyle(fontSize: 52, fontWeight: FontWeight.w900)),
            Text(msg, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text('+$xpEarned XP · $newFacts new facts · best streak 🔥${c.bestCombo}',
                style: TextStyle(color: cs.onSurfaceVariant)),
          ]),
        ),
      ),
      Card(
        child: Column(children: [
          for (final (f, ok) in results)
            ListTile(
              leading: CircleAvatar(
                radius: 14,
                backgroundColor: (ok ? good : bad).withValues(alpha: .15),
                child: Text(ok ? '✓' : '✗', style: TextStyle(color: ok ? good : bad, fontWeight: FontWeight.w900)),
              ),
              title: Text('${f.a ? 'Fact' : 'Myth'}: ${f.s}'),
              subtitle: Text(f.e),
            ),
        ]),
      ),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Home'))),
        const SizedBox(width: 10),
        Expanded(
            child: FilledButton(
                style: FilledButton.styleFrom(backgroundColor: accent),
                onPressed: _again,
                child: const Text('Play another'))),
      ]),
    ]);
  }
}
