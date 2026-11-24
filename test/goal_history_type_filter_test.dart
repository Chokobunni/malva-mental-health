import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:malva_mental_health/src/screens/goals_screen.dart';
import 'package:malva_mental_health/src/screens/goals/goal_history_panel.dart';
import 'package:malva_mental_health/src/services/malva_api_client.dart';
import 'package:malva_mental_health/src/time/wib.dart';
import 'record_render_capture.dart';

void main() {
  testWidgets('empty archive uses reference illustration and title bar',
      (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await loadRecordCaptureFonts();
    final boundary = GlobalKey();
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
            home: RepaintBoundary(
                key: boundary, child: const GoalsScreen(showArchive: true)))));
    await tester.pumpAndSettle();
    await tester.runAsync(() => precacheImage(
        const AssetImage('assets/goals/archive-empty.png'),
        tester.element(find.byType(GoalsScreen))));
    await tester.pumpAndSettle();
    expect(find.image(const AssetImage('assets/goals/archive-empty.png')),
        findsOneWidget);
    final appBar = tester.widget<AppBar>(find.byType(AppBar));
    expect(appBar.flexibleSpace, isNotNull);
    expect(find.text('Belum ada target diarsipkan.'), findsOneWidget);
    await captureRecord(tester, boundary, 'archive-empty.png');
  });
  testWidgets('history filters saved goals by type including legacy yes/no',
      (tester) async {
    tester.view.physicalSize = const Size(430, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final goals = [
      for (final method in ['legacy', 'yes_no', 'numeric', 'checklist'])
        BackendGoal.fromJson({
          'id': method,
          'title': 'Target $method',
          if (method != 'legacy') 'details': {'method': method}
        })
    ];
    final logs = [
      for (final goal in goals)
        BackendHabitLog(
            id: goal.id, goalId: goal.id, loggedOn: '2026-11-24', done: true)
    ];
    var selection = '';
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: StatefulBuilder(
                builder: (context, setState) => SingleChildScrollView(
                        child: GoalHistoryPanel(
                      goals: goals,
                      logs: logs,
                      range: DateTimeRange(
                          start: wibFromParts(2026, 11, 18),
                          end: wibFromParts(2026, 11, 24)),
                      today: wibFromParts(2026, 11, 24),
                      rangeLabel: '7 hari terakhir',
                      onRangeChanged: (_) {},
                      method: selection,
                      onMethodChanged: (value) =>
                          setState(() => selection = value ?? ''),
                      onArchive: () {},
                      loading: false,
                      error: null,
                      onRetry: () {},
                    ))))));
    await tester.tap(find.text('Semua Target'));
    await tester.pumpAndSettle();
    for (final label in [
      'Semua Target',
      'Ya/Tidak',
      'Dengan Nilai',
      'Sub-Tugas'
    ]) {
      expect(find.text(label), findsWidgets);
    }
    await tester.tap(find.text('Dengan Nilai'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(ExpansionTile));
    await tester.pumpAndSettle();
    expect(find.text('Target numeric'), findsOneWidget);
    expect(find.text('Target checklist'), findsNothing);
    expect(find.text('Target yes_no'), findsNothing);
    await tester.tap(find.text('Dengan Nilai'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ya/Tidak'));
    await tester.pumpAndSettle();
    expect(find.text('Target legacy'), findsOneWidget);
    expect(find.text('Target yes_no'), findsOneWidget);
    expect(find.text('Target numeric'), findsNothing);
    await tester.tap(find.text('Ya/Tidak'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sub-Tugas'));
    await tester.pumpAndSettle();
    expect(find.text('Target checklist'), findsOneWidget);
    expect(find.text('Target legacy'), findsNothing);
    await tester.tap(find.text('Sub-Tugas'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Semua Target'));
    await tester.pumpAndSettle();
    for (final goal in goals) {
      expect(find.text(goal.title), findsOneWidget);
    }
  });

  testWidgets('a missed target is counted on its scheduled day',
      (tester) async {
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final start = wibFromParts(2026, 11, 24);
    final today = wibFromParts(2026, 11, 25, 23);
    final goal = BackendGoal.fromJson({
      'id': 'sleep',
      'title': 'Tidur jam 22.00',
      'details': {'start_date': '2026-11-24', 'time': '22:00'},
    });
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: GoalHistoryPanel(
      goals: [goal],
      logs: const [],
      range: DateTimeRange(start: start, end: today),
      today: today,
      rangeLabel: 'Tanggal pilihan',
      onRangeChanged: (_) {},
      method: '',
      onMethodChanged: (_) {},
      onArchive: () {},
      loading: false,
      error: null,
      onRetry: () {},
    ))));
    expect(find.byType(ExpansionTile), findsOneWidget);
    expect(find.text('0/1 selesai'), findsOneWidget);
    await tester.tap(find.byType(ExpansionTile));
    await tester.pumpAndSettle();
    expect(find.text('Tidur jam 22.00'), findsOneWidget);
    expect(find.text('Tidak dilakukan'), findsOneWidget);
    await tester.tap(find.text('Tidur jam 22.00'));
    await tester.pumpAndSettle();
    expect(find.text('Detail aktivitas'), findsOneWidget);
    expect(find.text('Selasa, 24 November 2026'), findsOneWidget);
    expect(find.text('Tidak dilakukan'), findsWidgets);
  });
}
