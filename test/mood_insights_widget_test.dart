import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:malva_mental_health/src/models.dart';
import 'package:malva_mental_health/src/time/wib.dart';
import 'package:malva_mental_health/src/widgets/mood_insights.dart';

void main() {
  for (final keepEntries in [false, true])
    testWidgets(
        'open calendar details close when the patient owner changes (same data: $keepEntries)',
        (tester) async {
      final entries = [
        MoodEntry(
            date: wibFromParts(2026, 11, 8),
            mood: MoodValue.good,
            sleepHours: 7,
            energy: 8,
            anxiety: 3,
            irritability: 2,
            note: '')
      ];
      var owner = 'patient-a';
      late StateSetter change;
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(body: StatefulBuilder(builder: (context, update) {
        change = update;
        return SingleChildScrollView(
            child: MoodInsights(
                entries: owner == 'patient-a' || keepEntries ? entries : [],
                ownerKey: owner,
                now: wibFromParts(2026, 11, 8)));
      }))));
      final cell = find.byWidgetPredicate((w) =>
          w is Semantics &&
          w.properties.label == '8 November 2026, 1 check-in');
      await tester.ensureVisible(cell);
      await tester.pumpAndSettle();
      await tester.tap(cell);
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
      change(() => owner = 'patient-b');
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
      if (!keepEntries) expect(find.text('Baik'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  testWidgets(
      'dashboard shows exact statistics, real monthly calendar and balance filter',
      (tester) async {
    tester.view.physicalSize = const Size(420, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: MoodInsights(entries: [
      MoodEntry(
          date: wibFromParts(2026, 10, 31),
          mood: MoodValue.good,
          sleepHours: 7,
          energy: 8,
          anxiety: 3,
          irritability: 2,
          note: ''),
    ], now: wibFromParts(2026, 11, 8))))));
    expect(find.text('✅ Longest Streak'), findsOneWidget);
    expect(find.text('🔥 Current Streak'), findsOneWidget);
    expect(find.text('🗓️ Total Days'), findsOneWidget);
    expect(find.text('November 2026'), findsOneWidget);
    await tester.tap(find.byTooltip('Bulan sebelumnya'));
    await tester.pump();
    expect(find.text('Oktober 2026'), findsOneWidget);
    expect(
        find.byWidgetPredicate((w) =>
            w is Semantics &&
            w.properties.label == '31 Oktober 2026, 1 check-in'),
        findsOneWidget);
    expect(find.text('Symptoms Balance Map'), findsOneWidget);
    expect(find.text('Lifetime'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
