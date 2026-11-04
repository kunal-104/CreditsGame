import 'dart:math';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'data.dart';
import 'play.dart' show accent, good, bad;
import 'wiki.dart' as wiki;

Widget _offline(VoidCallback retry) => Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('📡', style: TextStyle(fontSize: 48)),
          const SizedBox(height: 8),
          const Text("Couldn't reach Wikipedia. Check your connection and try again.", textAlign: TextAlign.center),
          const SizedBox(height: 12),
          FilledButton(onPressed: retry, child: const Text('Retry')),
        ]),
      ),
    );

class TimeMachineScreen extends StatefulWidget {
  const TimeMachineScreen({super.key});
  @override
  State<TimeMachineScreen> createState() => _TimeMachineScreenState();
}

class _TimeMachineScreenState extends State<TimeMachineScreen> {
  static const rounds = 8;
  final rnd = Random();
  DateTime day = DateTime.now();
  List<wiki.WikiEvent>? events;
  bool error = false;
  int round = 0, score = 0;
  late (wiki.WikiEvent, wiki.WikiEvent) pair;
  int? picked;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      events = null;
      error = false;
    });
    try {
      final e = await wiki.onThisDay(day.month, day.day);
      if (e.length < 4) throw Exception('few events');
      if (!mounted) return;
      setState(() {
        events = e;
        round = 0;
        score = 0;
        _newPair();
      });
    } catch (_) {
      if (mounted) setState(() => error = true);
    }
  }

  void _newPair() {
    final e = events!;
    for (var t = 0; t < 60; t++) {
      final a = e[rnd.nextInt(e.length)], b = e[rnd.nextInt(e.length)];
      if (a != b && (a.year - b.year).abs() >= 3) {
        pair = (a, b);
        picked = null;
        return;
      }
    }
    pair = (e[0], e[1]);
    picked = null;
  }

  void _pick(int k) {
    if (picked != null) return;
    final (a, b) = pair;
    final earlier = a.year <= b.year ? 0 : 1;
    final ok = k == earlier;
    if (ok) score++;
    Curio.I.addXp(ok ? 8 : 2);
    setState(() => picked = k);
  }

  String _yr(int y) => y < 0 ? '${-y} BC' : '$y';

  @override
  Widget build(BuildContext context) {
    final label = MaterialLocalizations.of(context).formatMediumDate(day).split(',').first;
    Widget body;
    if (error) {
      body = _offline(_load);
    } else if (events == null) {
      body = const Center(child: CircularProgressIndicator());
    } else if (round >= rounds) {
      body = Center(
        child: Card(
          margin: const EdgeInsets.all(16),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('$score/$rounds', style: const TextStyle(fontSize: 52, fontWeight: FontWeight.w900)),
              Text(score >= 6 ? 'You really know your timeline! 🕰️' : 'History is full of surprises. 📜'),
              const SizedBox(height: 16),
              Row(mainAxisSize: MainAxisSize.min, children: [
                OutlinedButton(
                    onPressed: () {
                      day = DateTime(2024, 1 + rnd.nextInt(12), 1 + rnd.nextInt(28));
                      _load();
                    },
                    child: const Text('🎲 Random date')),
                const SizedBox(width: 10),
                FilledButton(
                    onPressed: () => setState(() {
                          round = 0;
                          score = 0;
                          _newPair();
                        }),
                    child: const Text('Play again')),
              ]),
            ]),
          ),
        ),
      );
    } else {
      final (a, b) = pair;
      final earlier = a.year <= b.year ? 0 : 1;
      Widget option(wiki.WikiEvent e, int k) {
        Color? border;
        if (picked != null) {
          if (k == earlier) border = good;
          if (k == picked && k != earlier) border = bad;
        }
        return Card(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: BorderSide(color: border ?? Colors.transparent, width: 2)),
          color: border?.withValues(alpha: .12),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () => _pick(k),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (e.thumb != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.network(e.thumb!, width: 64, height: 64, fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => const SizedBox(width: 64, height: 64)),
                    ),
                  ),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    if (picked != null)
                      Text(_yr(e.year), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                    Text(e.text, style: const TextStyle(fontSize: 16)),
                  ]),
                ),
              ]),
            ),
          ),
        );
      }

      body = ListView(padding: const EdgeInsets.all(16), children: [
        Text.rich(TextSpan(children: [
          const TextSpan(text: 'On '),
          TextSpan(text: label, style: const TextStyle(fontWeight: FontWeight.bold)),
          const TextSpan(text: '… which of these happened '),
          const TextSpan(text: 'first', style: TextStyle(fontWeight: FontWeight.bold)),
          const TextSpan(text: '?'),
        ])),
        const SizedBox(height: 12),
        option(a, 0),
        const Center(child: Text('or', style: TextStyle(fontWeight: FontWeight.w800))),
        option(b, 1),
        if (picked != null) ...[
          const SizedBox(height: 8),
          Text("${picked == earlier ? '✓ Correct!' : '✗ Not this time.'} They're ${(a.year - b.year).abs()} years apart.",
              style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, children: [
            for (final e in [a, b])
              if (e.pageUrl != null)
                ActionChip(
                    label: Text('${e.pageTitle} ↗'),
                    onPressed: () => launchUrl(Uri.parse(e.pageUrl!), mode: LaunchMode.externalApplication)),
          ]),
          const SizedBox(height: 12),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: accent, padding: const EdgeInsets.all(14)),
            onPressed: () => setState(() {
              round++;
              if (round < rounds) _newPair();
            }),
            child: Text(round + 1 < rounds ? 'Next →' : 'Results'),
          ),
        ],
      ]);
    }
    return Scaffold(
      appBar: AppBar(title: Text(round < rounds && events != null ? 'Time Machine · ${round + 1}/$rounds' : 'Time Machine')),
      body: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 600), child: body)),
    );
  }
}

class RabbitHoleScreen extends StatefulWidget {
  const RabbitHoleScreen({super.key});
  @override
  State<RabbitHoleScreen> createState() => _RabbitHoleScreenState();
}

class _RabbitHoleScreenState extends State<RabbitHoleScreen> {
  final queue = <wiki.WikiArticle>[];
  wiki.WikiArticle? current;
  bool error = false, filling = false;
  int count = 0;

  @override
  void initState() {
    super.initState();
    _show();
  }

  Future<void> _fill() async {
    if (filling) return;
    filling = true;
    try {
      while (mounted && queue.length < 3) {
        final a = await wiki.randomArticle();
        if (a != null) queue.add(a);
      }
    } catch (_) {
      // network issue; _show handles an empty queue
    } finally {
      filling = false;
    }
  }

  Future<void> _show() async {
    setState(() {
      error = false;
      current = null;
    });
    if (queue.isEmpty) await _fill();
    if (!mounted) return;
    if (queue.isEmpty) return setState(() => error = true);
    setState(() => current = queue.removeAt(0));
    _fill();
  }

  @override
  Widget build(BuildContext context) {
    final c = Curio.I;
    final a = current;
    Widget body;
    if (error) {
      body = _offline(_show);
    } else if (a == null) {
      body = const Center(child: CircularProgressIndicator());
    } else {
      final saved = c.isArticleSaved(a.title);
      body = ListView(padding: const EdgeInsets.all(16), children: [
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (a.thumb != null)
              Image.network(a.thumb!,
                  height: 220, width: double.infinity, fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox()),
            Padding(
              padding: const EdgeInsets.all(18),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(a.title, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                if (a.description.isNotEmpty)
                  Text(a.description, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                const SizedBox(height: 10),
                Text(a.extract, style: const TextStyle(fontSize: 16, height: 1.5)),
                const SizedBox(height: 14),
                Wrap(spacing: 8, children: [
                  OutlinedButton(
                      onPressed: () => launchUrl(Uri.parse(a.url), mode: LaunchMode.externalApplication),
                      child: const Text('Read full article ↗')),
                  OutlinedButton.icon(
                    onPressed: () => setState(() => c.toggleSaveArticle(SavedArticle(a.title, a.extract, a.url, a.thumb))),
                    icon: Icon(saved ? Icons.star_rounded : Icons.star_outline_rounded),
                    label: Text(saved ? 'Saved' : 'Save'),
                  ),
                ]),
              ]),
            ),
          ]),
        ),
        const SizedBox(height: 8),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: accent, padding: const EdgeInsets.all(16)),
          onPressed: () {
            count++;
            c.countWiki();
            _show();
          },
          child: const Text('Next rabbit hole →'),
        ),
      ]);
    }
    return Scaffold(
      appBar: AppBar(title: Text('Rabbit Hole · 🕳️ $count')),
      body: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 600), child: body)),
    );
  }
}
