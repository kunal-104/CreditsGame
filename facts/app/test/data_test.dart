import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:curio/data.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('dataset loads and every fact references known categories and countries', () async {
    final c = await Curio.load();
    expect(c.facts.length, greaterThan(250));
    for (final f in c.facts) {
      expect(c.cat.containsKey(f.c), isTrue);
      for (final r in f.r) {
        expect(r == 'world' || c.country.containsKey(r), isTrue, reason: r);
      }
    }
  });

  test('sessions are balanced, unique and prefer facts from beyond home', () async {
    final c = await Curio.load();
    c.setHome('IN');
    for (var seed = 0; seed < 30; seed++) {
      final s = c.buildSession(c.facts, seed: seed);
      expect(s.length, 10);
      expect(s.map((f) => f.id).toSet().length, 10);
      final myths = s.where((f) => !f.a).length;
      expect(myths, inInclusiveRange(3, 5));
    }
    final s = c.buildSession(c.facts, seed: 1);
    expect(s.where((f) => f.r.contains('IN')).length, lessThan(3));
  });

  test('answered facts are deprioritised', () async {
    final c = await Curio.load();
    final first = c.buildSession(c.facts, seed: 7);
    for (final f in first) {
      c.recordAnswer(f, true, 0);
    }
    final second = c.buildSession(c.facts, seed: 8);
    expect(second.where(first.contains).length, 0);
  });

  test('levels', () {
    expect(levelOf(0), 1);
    expect(levelOf(100), 2);
    expect(levelOf(299), 2);
    expect(levelOf(300), 3);
    expect(titleOf(1), 'Curious');
    expect(titleOf(7), 'Scholar');
  });
}
