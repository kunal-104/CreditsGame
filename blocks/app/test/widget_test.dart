import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:blockora/main.dart';

void main() {
  testWidgets('home -> game -> place a piece by dragging', (tester) async {
    SharedPreferences.setMockInitialValues({'seenHowTo': true});
    await Store.load();
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const BlockoraApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('▶  Play'));
    await tester.pumpAndSettle();
    expect(find.text('Lines 0'), findsOneWidget);
  });
}
