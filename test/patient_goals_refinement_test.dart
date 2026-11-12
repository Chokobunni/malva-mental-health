import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:malva_mental_health/src/models.dart';
import 'package:malva_mental_health/src/models/goal_details.dart';
import 'package:malva_mental_health/src/providers/providers.dart';
import 'package:malva_mental_health/src/screens/goals/goal_editor.dart';
import 'package:malva_mental_health/src/screens/goals_screen.dart';
import 'package:malva_mental_health/src/services/malva_api_client.dart';
import 'package:malva_mental_health/src/theme.dart';
import 'package:malva_mental_health/src/time/wib.dart';

void main() {
  testWidgets('rollover drops prior day progress while next day refresh fails',
      (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    var now = wibFromParts(2026, 11, 11, 23, 59);
    var reads = 0, writes = 0;
    final refresh = Completer<void>();
    final container = ProviderContainer(overrides: [
      apiClientProvider.overrideWithValue(MalvaApiClient(
          baseUrl: 'https://goals.test',
          httpClient: MockClient((r) async {
            if (r.method != 'GET') {
              writes++;
              return http.Response('{}', 500);
            }
            if (reads++ > 0) {
              await refresh.future;
              return http.Response('{"error":"offline"}', 503);
            }
            return http.Response(
                jsonEncode({
                  'goals': [
                    {
                      'id': 'g',
                      'title': 'Kemarin',
                      'is_active': true,
                      'is_due': true,
                      'done_today': false,
                      'today_value': 14,
                      'details': {
                        'method': 'numeric',
                        'target': 20,
                        'unit': 'halaman',
                        'start_date': '2026-01-01'
                      },
                    }
                  ]
                }),
                200);
          }))),
    ]);
    addTearDown(container.dispose);
    container.read(authStateProvider.notifier).setSession(const AuthSession(
        role: UserRole.patient,
        identifier: 'p',
        displayName: 'P',
        accessToken: 't'));
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
            theme: buildMalvaTheme(), home: GoalsScreen(now: () => now))));
    await tester.pumpAndSettle();
    expect(find.text('Kemarin'), findsOneWidget);
    now = wibFromParts(2026, 11, 12, 0, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(find.text('Kemarin'), findsNothing);
    expect(find.byTooltip('Tambah progres Kemarin'), findsNothing);
    refresh.complete();
    await tester.pumpAndSettle();
    expect(find.text('Kemarin'), findsNothing);
    expect(find.textContaining('Gagal memuat'), findsOneWidget);
    expect(writes, 0);
  });
  test('monthly dates clamp short months and restore original anchor', () {
    final d = GoalDetails.fromJson({
      'start_date': '2028-01-31',
      'recurrence': 'monthly',
      'interval': 1,
      'weekdays': [],
    });
    for (final entry in {
      '2028-01-30': false,
      '2028-01-31': true,
      '2028-02-28': false,
      '2028-02-29': true,
      '2028-03-29': false,
      '2028-03-31': true,
      '2028-04-30': true,
    }.entries) {
      expect(d.isDueOn(DateTime.parse(entry.key)), entry.value,
          reason: entry.key);
    }
    final alternate = GoalDetails.fromJson({
      'start_date': '2027-12-31',
      'recurrence': 'monthly',
      'interval': 2,
    });
    expect(alternate.isDueOn(DateTime(2028, 2, 29)), isTrue);
    expect(alternate.isDueOn(DateTime(2028, 3, 31)), isFalse);
    expect(alternate.scheduleLabel, contains('setiap 2 bulan'));
  });

  test('weekly quota zero is retained and permits flexible days', () {
    final d = GoalDetails.fromJson({
      'start_date': '2026-11-11',
      'recurrence': 'weekly',
      'interval': 2,
      'weekdays': [],
      'weekly_target': 0,
    });
    expect(d.toJson()['weekly_target'], 0);
    expect(d.isDueOn(DateTime(2026, 11, 12)), isTrue);
    expect(d.isDueOn(DateTime(2026, 11, 16)), isFalse);
    expect(d.isDueOn(DateTime(2026, 11, 23)), isTrue);
  });

  testWidgets('editor saves monthly interval and restores weekly frequency',
      (tester) async {
    tester.view.physicalSize = const Size(390, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    GoalEditorResult? saved;
    await tester.pumpWidget(MaterialApp(
        theme: buildMalvaTheme(),
        home: GoalEditor(
          onSave: (result) async {
            saved = result;
            return false;
          },
        )));
    await tester.enterText(find.byKey(const Key('goal-title')), 'Bulanan');
    final recurrence = find.byType(DropdownButton<String>);
    await tester.ensureVisible(recurrence);
    await tester.tap(recurrence);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bulanan').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Tambah interval'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Simpan Target'));
    await tester.tap(find.text('Simpan Target'));
    await tester.pumpAndSettle();
    expect(saved?.details.recurrence, 'monthly');
    expect(saved?.details.interval, 2);
    expect(saved?.details.toJson().containsKey('weekly_target'), isFalse);
  });

  testWidgets('weekly editor retains optional zero quota and chosen weekdays',
      (tester) async {
    tester.view.physicalSize = const Size(390, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    GoalEditorResult? saved;
    await tester.pumpWidget(MaterialApp(
        theme: buildMalvaTheme(),
        home: GoalEditor(
          onSave: (result) async {
            saved = result;
            return false;
          },
        )));
    await tester.enterText(find.byKey(const Key('goal-title')), 'Fleksibel');
    final frequency = find.byKey(const Key('goal-frequency-target'));
    await tester.ensureVisible(frequency);
    await tester.tap(frequency);
    await tester.ensureVisible(find.text('Simpan Target'));
    await tester.tap(find.text('Simpan Target'));
    await tester.pumpAndSettle();
    expect(saved?.details.toJson()['weekly_target'], 0);
    await tester.ensureVisible(find.byKey(const Key('goal-frequency-days')));
    await tester.tap(find.byKey(const Key('goal-frequency-days')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Hari Kerja'));
    await tester.tap(find.text('Hari Kerja'));
    await tester.ensureVisible(find.text('Simpan Target'));
    await tester.tap(find.text('Simpan Target'));
    await tester.pumpAndSettle();
    expect(saved?.details.weekdays, [1, 2, 3, 4, 5]);
    expect(saved?.details.toJson().containsKey('weekly_target'), isFalse);
  });

  for (final method in ['numeric', 'checklist']) {
    for (final failure in [false, true]) {
      testWidgets(
          '$method keeps habit position during save and ${failure ? 'failed' : 'successful'} reload',
          (tester) async {
        FlutterSecureStorage.setMockInitialValues({});
        tester.view.physicalSize = const Size(390, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final write = Completer<void>(), reload = Completer<void>();
        var changed = false;
        final today = wibDateKey(wibNow());
        final goals = List.generate(
            12,
            (i) => <String, dynamic>{
                  'id': 'g$i',
                  'title': 'Kebiasaan $i',
                  'target_per_week': 3,
                  'is_active': true,
                  'is_due': true,
                  'done_today': false,
                  'details': {
                    'method': i == 8 ? method : 'yes_no',
                    'target': 20,
                    'unit': 'halaman',
                    'start_date': today,
                    'steps': [
                      {'id': 'a', 'label': 'Langkah delapan'}
                    ]
                  },
                });
        final container = ProviderContainer(overrides: [
          apiClientProvider.overrideWithValue(MalvaApiClient(
            baseUrl: 'https://goals.test',
            httpClient: MockClient((r) async {
              if (r.method == 'GET') {
                if (changed) {
                  await reload.future;
                  if (failure)
                    return http.Response('{"error":"reload gagal"}', 503);
                }
                return http.Response(jsonEncode({'goals': goals}), 200);
              }
              await write.future;
              changed = true;
              final body = jsonDecode(r.body) as Map<String, dynamic>;
              goals[8].addAll({
                'today_value': body['value'] ?? 0,
                'today_completed_step_ids': body['completed_step_ids'] ?? [],
                'done_today': method == 'checklist'
              });
              return http.Response(
                  jsonEncode({
                    'log': {
                      'id': 'l',
                      'goal_id': 'g8',
                      'logged_on': today,
                      'done': method == 'checklist',
                      'value': body['value'] ?? 0,
                      'completed_step_ids': body['completed_step_ids'] ?? []
                    }
                  }),
                  200);
            }),
          )),
        ]);
        addTearDown(container.dispose);
        container.read(authStateProvider.notifier).setSession(const AuthSession(
            role: UserRole.patient,
            identifier: 'p',
            displayName: 'P',
            accessToken: 't'));
        await tester.pumpWidget(UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
                theme: buildMalvaTheme(), home: const GoalsScreen())));
        await tester.pumpAndSettle();
        final control = method == 'numeric'
            ? find.byTooltip('Tambah progres Kebiasaan 8')
            : find.descendant(
                of: find.byKey(const ValueKey('g8')),
                matching: find.text('Langkah delapan'));
        await tester.ensureVisible(control);
        await tester.pumpAndSettle();
        final title = find.text('Kebiasaan 8');
        final before = tester.getTopLeft(title).dy;
        final scrollable = find
            .descendant(
                of: find.byKey(const Key('goals-scroll')),
                matching: find.byType(Scrollable))
            .first;
        final position = tester.state<ScrollableState>(scrollable).position;
        final offset = position.pixels;
        await tester.tap(control);
        await tester.pump();
        expect(tester.getTopLeft(title).dy, closeTo(before, .1));
        write.complete();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 40));
        expect(title, findsOneWidget);
        expect(tester.getTopLeft(title).dy, closeTo(before, .1));
        expect(position.pixels, closeTo(offset, .1));
        reload.complete();
        await tester.pumpAndSettle();
        expect(tester.getTopLeft(title).dy, closeTo(before, .1));
        expect(position.pixels, closeTo(offset, .1));
        if (method == 'numeric')
          expect(find.textContaining('Progres: '), findsOneWidget);
        if (method == 'checklist')
          expect(find.text('1/1 selesai'), findsOneWidget);
      });
    }
  }
}
