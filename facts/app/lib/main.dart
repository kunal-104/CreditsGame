import 'dart:math';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'data.dart';
import 'live.dart';
import 'play.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Curio.load();
  runApp(const CurioApp());
}

class CurioApp extends StatelessWidget {
  const CurioApp({super.key});
  @override
  Widget build(BuildContext context) {
    ThemeData theme(Brightness b) => ThemeData(
          colorSchemeSeed: accent,
          brightness: b,
          scaffoldBackgroundColor: b == Brightness.light ? const Color(0xFFFBF7F2) : const Color(0xFF12111A),
          cardTheme: CardThemeData(
            elevation: 0,
            color: b == Brightness.light ? Colors.white : const Color(0xFF1C1B27),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          ),
        );
    return ListenableBuilder(
      listenable: Curio.I,
      builder: (context, _) => MaterialApp(
        title: 'Curio',
        debugShowCheckedModeBanner: false,
        themeMode: Curio.I.themeMode,
        theme: theme(Brightness.light),
        darkTheme: theme(Brightness.dark),
        home: Curio.I.onboarded ? const Shell() : const Onboarding(),
      ),
    );
  }
}

void play(BuildContext context, String title, List<Fact> facts,
    {String kind = 'mix', List<Fact> Function()? replayPool}) {
  if (facts.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nothing to play here yet')));
    return;
  }
  Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => PlayScreen(title: title, facts: facts, kind: kind, replayPool: replayPool)));
}

void push(BuildContext context, Widget w) => Navigator.push(context, MaterialPageRoute(builder: (_) => w));

// ------------------------------------------------------------------ onboarding
class Onboarding extends StatefulWidget {
  final bool homeOnly;
  const Onboarding({super.key, this.homeOnly = false});
  @override
  State<Onboarding> createState() => _OnboardingState();
}

class _OnboardingState extends State<Onboarding> {
  late int step = widget.homeOnly ? 1 : 0;
  String q = '';
  final picks = <String>{...Curio.I.interests};

  @override
  Widget build(BuildContext context) {
    final c = Curio.I;
    final cs = Theme.of(context).colorScheme;
    Widget body;
    if (step == 0) {
      body = Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Text('🧭', style: TextStyle(fontSize: 72)),
        const Text('Welcome to curio.', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900)),
        const SizedBox(height: 12),
        Text(
            "The world is full of things you've never heard of: laws, languages, wars, beliefs, inventions and everyday customs. A few minutes a day, one surprising fact at a time.",
            textAlign: TextAlign.center,
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 16)),
        const SizedBox(height: 16),
        const Text('Swipe right for Fact, left for Myth.', style: TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 28),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: accent, minimumSize: const Size.fromHeight(52)),
          onPressed: () => setState(() => step = 1),
          child: const Text('Let’s go'),
        ),
      ]);
    } else if (step == 1) {
      final list = [...c.countries]..sort((a, b) => a.name.compareTo(b.name));
      final shown = list.where((x) => x.name.toLowerCase().contains(q.toLowerCase())).toList();
      void done(String? code) {
        if (code != null) c.setHome(code);
        if (widget.homeOnly) {
          Navigator.pop(context);
        } else {
          setState(() => step = 2);
        }
      }

      body = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SizedBox(height: 16),
        const Text('Where are you from?', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900)),
        Text("We'll show you more facts from other parts of the world, the ones you're least likely to know.",
            style: TextStyle(color: cs.onSurfaceVariant)),
        const SizedBox(height: 12),
        TextField(
          decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search…', border: OutlineInputBorder()),
          onChanged: (v) => setState(() => q = v),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: shown.length,
            itemBuilder: (_, k) => ListTile(
              leading: Text(flagOf(shown[k].code), style: const TextStyle(fontSize: 26)),
              title: Text(shown[k].name),
              selected: shown[k].code == c.home,
              onTap: () => done(shown[k].code),
            ),
          ),
        ),
        TextButton(onPressed: () => done(null), child: const Text('Skip')),
      ]);
    } else {
      body = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SizedBox(height: 16),
        const Text('What sparks your curiosity?', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900)),
        Text("Pick a few. You'll still see a bit of everything.", style: TextStyle(color: cs.onSurfaceVariant)),
        const SizedBox(height: 12),
        Expanded(
          child: SingleChildScrollView(
            child: Wrap(spacing: 8, runSpacing: 8, children: [
              for (final cat in c.categories)
                FilterChip(
                  label: Text('${cat.emoji} ${cat.name}'),
                  selected: picks.contains(cat.id),
                  onSelected: (v) => setState(() => v ? picks.add(cat.id) : picks.remove(cat.id)),
                ),
            ]),
          ),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: accent, minimumSize: const Size.fromHeight(52)),
          onPressed: () => c.finishOnboarding(picks.toList()),
          child: const Text('Start exploring'),
        ),
      ]);
    }
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Padding(padding: const EdgeInsets.all(24), child: body)),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ shell
class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int tab = 0;
  @override
  Widget build(BuildContext context) {
    final c = Curio.I;
    final pages = [const TodayTab(), const ExploreTab(), const PassportTab(), const LiveTab(), const MeTab()];
    return Scaffold(
      appBar: AppBar(
        title: const Text.rich(TextSpan(children: [
          TextSpan(text: 'curio', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 24)),
          TextSpan(text: '.', style: TextStyle(color: accent, fontWeight: FontWeight.w900, fontSize: 24)),
        ])),
        actions: [
          Chip(label: Text('🔥 ${c.currentStreak}'), visualDensity: VisualDensity.compact),
          const SizedBox(width: 6),
          Chip(label: Text('⭐ ${c.xp}'), visualDensity: VisualDensity.compact),
          const SizedBox(width: 12),
        ],
      ),
      body: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 640), child: pages[tab])),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (i) => setState(() => tab = i),
        destinations: const [
          NavigationDestination(icon: Text('☀️', style: TextStyle(fontSize: 22)), label: 'Today'),
          NavigationDestination(icon: Text('🧭', style: TextStyle(fontSize: 22)), label: 'Explore'),
          NavigationDestination(icon: Text('🛂', style: TextStyle(fontSize: 22)), label: 'Passport'),
          NavigationDestination(icon: Text('📡', style: TextStyle(fontSize: 22)), label: 'Live'),
          NavigationDestination(icon: Text('👤', style: TextStyle(fontSize: 22)), label: 'Me'),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  final String emoji, title, sub;
  final VoidCallback onTap;
  const _Tile(this.emoji, this.title, this.sub, this.onTap);
  @override
  Widget build(BuildContext context) => Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(emoji, style: const TextStyle(fontSize: 28)),
              const SizedBox(height: 4),
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text(sub, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ]),
          ),
        ),
      );
}

// ------------------------------------------------------------------ today
class TodayTab extends StatelessWidget {
  const TodayTab({super.key});
  @override
  Widget build(BuildContext context) {
    final c = Curio.I;
    final cs = Theme.of(context).colorScheme;
    final lvl = levelOf(c.xp);
    final into = c.xp - xpFor(lvl), span = xpFor(lvl + 1) - xpFor(lvl);
    final d = c.daily[todayKey()];
    final f = c.factOfTheDay();
    final home = c.home != null ? c.country[c.home] : null;
    final mistakes = c.mistakes();
    return ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
      Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: const LinearGradient(
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
              colors: [Color(0xFFFFB44D), Color(0xFFFF6B3D), Color(0xFFE1306C)]),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(d != null ? 'Daily done ✓' : 'Your daily 10',
              style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          Text(
              d != null
                  ? 'You scored $d today. Keep exploring below, or come back tomorrow for a new set.'
                  : 'Ten surprising claims from around the world. Fact or myth? Takes about 3 minutes.',
              style: const TextStyle(color: Colors.white)),
          const SizedBox(height: 14),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: const Color(0xFFC2410C)),
            onPressed: () => d != null
                ? play(context, 'Bonus round', c.buildSession(c.facts))
                : play(context, 'Daily 10', c.buildSession(c.facts, seed: hashStr('daily${todayKey()}')), kind: 'daily'),
            child: Text(d != null ? 'Play a bonus round' : 'Start today’s 10'),
          ),
        ]),
      ),
      const SizedBox(height: 12),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            CircleAvatar(
                radius: 24,
                backgroundColor: accent.withValues(alpha: .15),
                child: Text('$lvl', style: const TextStyle(color: accent, fontWeight: FontWeight.w900, fontSize: 18))),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${titleOf(lvl)} · ${c.xp} XP', style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: LinearProgressIndicator(value: into / span, minHeight: 9, color: accent)),
                const SizedBox(height: 4),
                Text('${span - into} XP to level ${lvl + 1} · ${c.answers.length} of ${c.facts.length} facts discovered',
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
              ]),
            ),
          ]),
        ),
      ),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${c.cat[f.c]!.emoji} Fact of the day · ${f.r.map(flagOf).join(' ')}',
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
            const SizedBox(height: 6),
            Text(f.s, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 6),
            Text(f.e, style: TextStyle(color: cs.onSurfaceVariant)),
            Row(children: [
              TextButton(
                  onPressed: () => launchUrl(wikiUri(f.w), mode: LaunchMode.externalApplication),
                  child: const Text('Read more ↗')),
              ListenableBuilder(
                listenable: c,
                builder: (_, _) => TextButton(
                    onPressed: () => c.toggleSaveFact(f.id), child: Text(c.isSaved(f.id) ? '★ Saved' : '☆ Save')),
              ),
            ]),
          ]),
        ),
      ),
      const Padding(
          padding: EdgeInsets.fromLTRB(4, 12, 0, 8),
          child: Text('Go deeper', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
      GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        childAspectRatio: 1.25,
        children: [
          _Tile('🛂', 'World Passport',
              home != null ? "Facts from beyond ${home.name} you probably don't know" : 'Collect country stamps',
              () => push(context, const Scaffold(body: SafeArea(child: PassportTab(standalone: true))))),
          _Tile('⏳', 'Time Machine', 'Real events from this day in history. Which came first?',
              () => push(context, const TimeMachineScreen())),
          _Tile('🕳️', 'Rabbit Hole', 'An endless feed of random Wikipedia articles',
              () => push(context, const RabbitHoleScreen())),
          if (mistakes.isNotEmpty)
            _Tile('🔁', 'Review mistakes', '${mistakes.length} to revisit. Spaced repetition helps them stick.',
                () => play(context, 'Review', c.buildSession(mistakes), replayPool: c.mistakes))
          else
            _Tile('🎲', 'Random mix', 'Ten facts from all 20 topics', () => play(context, 'Random mix', c.buildSession(c.facts))),
        ],
      ),
    ]);
  }
}

// ------------------------------------------------------------------ explore
class ExploreTab extends StatelessWidget {
  const ExploreTab({super.key});
  @override
  Widget build(BuildContext context) {
    final c = Curio.I;
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 200, childAspectRatio: 1.2, crossAxisSpacing: 12, mainAxisSpacing: 12),
      itemCount: c.categories.length,
      itemBuilder: (context, k) {
        final cat = c.categories[k];
        final p = c.progressWhere((f) => f.c == cat.id);
        return Material(
          color: cat.color,
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () {
              List<Fact> pool() => c.facts.where((f) => f.c == cat.id).toList();
              play(context, cat.name, c.buildSession(pool()), kind: 'category', replayPool: pool);
            },
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text(cat.emoji, style: const TextStyle(fontSize: 30)),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(cat.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                  Text('${p.seen}/${p.total} discovered', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: LinearProgressIndicator(
                        value: p.seen / p.total, minHeight: 5, color: Colors.white, backgroundColor: Colors.white30),
                  ),
                ]),
              ]),
            ),
          ),
        );
      },
    );
  }
}

// ------------------------------------------------------------------ passport
class PassportTab extends StatefulWidget {
  final bool standalone;
  const PassportTab({super.key, this.standalone = false});
  @override
  State<PassportTab> createState() => _PassportTabState();
}

class _PassportTabState extends State<PassportTab> {
  String q = '';
  @override
  Widget build(BuildContext context) {
    final c = Curio.I;
    final cs = Theme.of(context).colorScheme;
    final list = c.countries
        .map((x) => (country: x, p: c.progressWhere((f) => f.r.contains(x.code))))
        .where((x) => x.p.total > 0)
        .toList();
    int rank(bool b) => b ? 1 : 0;
    list.sort((a, b) {
      final h = rank(a.country.code == c.home) - rank(b.country.code == c.home);
      if (h != 0) return h;
      final s = rank(a.p.seen == a.p.total) - rank(b.p.seen == b.p.total);
      return s != 0 ? s : b.p.total - a.p.total;
    });
    final stamped = list.where((x) => x.p.seen == x.p.total).length;
    final home = c.home != null ? c.country[c.home] : null;
    final shown = list.where((x) => x.country.name.toLowerCase().contains(q.toLowerCase())).toList();
    return CustomScrollView(slivers: [
      if (widget.standalone) const SliverAppBar(title: Text('World Passport'), floating: true),
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        sliver: SliverToBoxAdapter(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
                '${home != null ? 'Born in ${flagOf(home.code)} ${home.name}? These facts come from everywhere else. ' : ''}Discover every fact from a country to earn its stamp.',
                style: TextStyle(color: cs.onSurfaceVariant)),
            const SizedBox(height: 10),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('$stamped of ${list.length} stamps collected', style: const TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 6),
                      ClipRRect(
                          borderRadius: BorderRadius.circular(99),
                          child: LinearProgressIndicator(value: stamped / list.length, minHeight: 8, color: accent)),
                    ]),
                  ),
                  const SizedBox(width: 10),
                  FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: accent),
                    onPressed: () {
                      final opts = list.where((x) => x.country.code != c.home && x.p.seen < x.p.total).toList();
                      final pick = (opts.isEmpty ? list : opts)[Random().nextInt(opts.isEmpty ? list.length : opts.length)];
                      push(context, CountryScreen(code: pick.country.code));
                    },
                    child: const Text('🎲 Surprise me'),
                  ),
                ]),
              ),
            ),
            TextField(
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search countries…', border: OutlineInputBorder()),
              onChanged: (v) => setState(() => q = v),
            ),
            const SizedBox(height: 10),
          ]),
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        sliver: SliverGrid.builder(
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 170, childAspectRatio: 1.35, crossAxisSpacing: 10, mainAxisSpacing: 10),
          itemCount: shown.length,
          itemBuilder: (context, k) {
            final x = shown[k];
            final done = x.p.seen == x.p.total;
            final isHome = x.country.code == c.home;
            return Card(
              margin: EdgeInsets.zero,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: isHome ? const BorderSide(color: accent, width: 2) : BorderSide.none),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () async {
                  await Navigator.push(context, MaterialPageRoute(builder: (_) => CountryScreen(code: x.country.code)));
                  if (mounted) setState(() {});
                },
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Text(flagOf(x.country.code), style: const TextStyle(fontSize: 30)),
                      const Spacer(),
                      if (done) const CircleAvatar(radius: 11, backgroundColor: good, child: Icon(Icons.check, size: 14, color: Colors.white)),
                    ]),
                    const Spacer(),
                    Text(x.country.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text('${isHome ? 'Home · ' : ''}${x.p.seen}/${x.p.total} facts',
                        style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                  ]),
                ),
              ),
            );
          },
        ),
      ),
    ]);
  }
}

class CountryScreen extends StatelessWidget {
  final String code;
  const CountryScreen({super.key, required this.code});
  @override
  Widget build(BuildContext context) {
    final c = Curio.I;
    final country = c.country[code]!;
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final list = c.facts.where((f) => f.r.contains(code)).toList();
        final seen = list.where((f) => c.answers.containsKey(f.id)).toList();
        return Scaffold(
          appBar: AppBar(title: Text(country.name)),
          body: ListView(padding: const EdgeInsets.all(16), children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(children: [
                  Text(flagOf(code), style: const TextStyle(fontSize: 64)),
                  Text(country.name, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900)),
                  Text('${seen.length}/${list.length} facts discovered${seen.length == list.length ? ' · Stamp collected ✓' : ''}'),
                  const SizedBox(height: 14),
                  FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: accent, minimumSize: const Size.fromHeight(48)),
                    onPressed: () => play(context, country.name, c.buildSession(list), kind: 'country',
                        replayPool: () => c.facts.where((f) => f.r.contains(code)).toList()),
                    child: Text(seen.isEmpty ? 'Visit ${country.name}' : 'Play again'),
                  ),
                ]),
              ),
            ),
            if (seen.isEmpty)
              const Padding(padding: EdgeInsets.all(24), child: Center(child: Text("🔒 Play to unlock this country's facts")))
            else
              Card(
                child: Column(children: [
                  for (final f in seen)
                    ListTile(
                      leading: Text(c.cat[f.c]!.emoji, style: const TextStyle(fontSize: 22)),
                      title: Text('${f.a ? 'Fact' : 'Myth'}: ${f.s}'),
                      subtitle: Text(f.e),
                    ),
                ]),
              ),
            TextButton(
              onPressed: () => launchUrl(wikiUri(country.name), mode: LaunchMode.externalApplication),
              child: Text('Read about ${country.name} on Wikipedia ↗'),
            ),
          ]),
        );
      },
    );
  }
}

// ------------------------------------------------------------------ live
class LiveTab extends StatelessWidget {
  const LiveTab({super.key});
  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(16), children: [
        Text("Unlimited modes powered by Wikipedia's millions of articles. Needs an internet connection.",
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
        const SizedBox(height: 12),
        _Tile('⏳', 'Time Machine',
            "Two real events that happened on today's date in history. Which came first? Every day brings new events.",
            () => push(context, const TimeMachineScreen())),
        _Tile('🕳️', 'Rabbit Hole',
            'A random Wikipedia article every time. Places, people, inventions, species, wars and more, with no end to it.',
            () => push(context, const RabbitHoleScreen())),
      ]);
}

// ------------------------------------------------------------------ me
class MeTab extends StatelessWidget {
  const MeTab({super.key});
  @override
  Widget build(BuildContext context) {
    final c = Curio.I;
    final cs = Theme.of(context).colorScheme;
    final lvl = levelOf(c.xp);
    final ok = c.answers.values.fold<int>(0, (s, a) => s + a.ok);
    final all = c.answers.values.fold<int>(0, (s, a) => s + a.ok + a.bad);
    final home = c.home != null ? c.country[c.home] : null;
    final stamps = c.countries.where((x) {
      final p = c.progressWhere((f) => f.r.contains(x.code));
      return p.total > 0 && p.seen == p.total;
    }).length;
    Widget stat(String v, String l) => Expanded(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Column(children: [
                Text(v, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                Text(l, style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
              ]),
            ),
          ),
        );
    return ListView(padding: const EdgeInsets.all(16), children: [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(children: [
            Text(home != null ? flagOf(home.code) : '🌐', style: const TextStyle(fontSize: 48)),
            Text(titleOf(lvl), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900)),
            Text('Level $lvl · ${c.xp} XP${home != null ? ' · from ${home.name}' : ''}',
                style: TextStyle(color: cs.onSurfaceVariant)),
          ]),
        ),
      ),
      Row(children: [
        stat('${c.answers.length}', 'facts discovered'),
        stat('${all == 0 ? 0 : (ok * 100 / all).round()}%', 'accuracy'),
        stat('🔥${c.currentStreak}', 'day streak'),
      ]),
      Row(children: [
        stat('$stamps', 'passport stamps'),
        stat('${c.wikiCount}', 'rabbit holes'),
        stat('${c.savedFacts.length + c.savedArticles.length}', 'saved'),
      ]),
      const SizedBox(height: 8),
      OutlinedButton.icon(
          onPressed: () => push(context, const SavedScreen()), icon: const Icon(Icons.star_rounded), label: const Text('Saved collection')),
      const SizedBox(height: 8),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Knowledge map', style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            for (final cat in c.categories)
              Builder(builder: (_) {
                final p = c.progressWhere((f) => f.c == cat.id);
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(children: [
                    SizedBox(width: 28, child: Text(cat.emoji)),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(99),
                        child: LinearProgressIndicator(value: p.seen / p.total, minHeight: 8, color: cat.color),
                      ),
                    ),
                    SizedBox(width: 48, child: Text(' ${p.seen}/${p.total}', style: const TextStyle(fontSize: 12))),
                  ]),
                );
              }),
          ]),
        ),
      ),
      Card(
        child: Column(children: [
          ListTile(
            title: const Text('Home country'),
            trailing: Text(home != null ? '${flagOf(home.code)} ${home.name}' : 'Choose'),
            onTap: () => push(context, const Onboarding(homeOnly: true)),
          ),
          ListTile(
            title: const Text('Theme'),
            trailing: DropdownButton<ThemeMode>(
              value: c.themeMode,
              onChanged: (v) => c.setTheme(v!),
              items: const [
                DropdownMenuItem(value: ThemeMode.system, child: Text('System')),
                DropdownMenuItem(value: ThemeMode.light, child: Text('Light')),
                DropdownMenuItem(value: ThemeMode.dark, child: Text('Dark')),
              ],
            ),
          ),
        ]),
      ),
      TextButton(
        onPressed: () async {
          final yes = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Reset all progress?'),
              content: const Text('XP, streak, answers and saved items will be deleted.'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Reset')),
              ],
            ),
          );
          if (yes == true) await c.resetAll();
        },
        child: const Text('Reset progress'),
      ),
      Text('Facts are curated and link to Wikipedia. Live modes use the Wikipedia API (CC BY-SA).',
          textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
    ]);
  }
}

class SavedScreen extends StatelessWidget {
  const SavedScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final c = Curio.I;
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final facts = [for (final id in c.savedFacts) ...c.facts.where((f) => f.id == id)];
        return Scaffold(
          appBar: AppBar(title: const Text('Saved')),
          body: facts.isEmpty && c.savedArticles.isEmpty
              ? const Center(child: Text('☆ Tap the star on any fact or article to keep it here.'))
              : ListView(padding: const EdgeInsets.all(16), children: [
                  for (final f in facts)
                    Card(
                      child: ListTile(
                        leading: Text(c.cat[f.c]!.emoji, style: const TextStyle(fontSize: 22)),
                        title: Text('${f.a ? 'Fact' : 'Myth'}: ${f.s}'),
                        subtitle: Text(f.e),
                        onTap: () => launchUrl(wikiUri(f.w), mode: LaunchMode.externalApplication),
                        trailing: IconButton(icon: const Icon(Icons.star_rounded, color: accent), onPressed: () => c.toggleSaveFact(f.id)),
                      ),
                    ),
                  for (final a in c.savedArticles)
                    Card(
                      child: ListTile(
                        leading: const Text('🕳️', style: TextStyle(fontSize: 22)),
                        title: Text(a.title),
                        subtitle: Text(a.extract, maxLines: 3, overflow: TextOverflow.ellipsis),
                        onTap: () => launchUrl(Uri.parse(a.url), mode: LaunchMode.externalApplication),
                        trailing: IconButton(icon: const Icon(Icons.star_rounded, color: accent), onPressed: () => c.toggleSaveArticle(a)),
                      ),
                    ),
                ]),
        );
      },
    );
  }
}
