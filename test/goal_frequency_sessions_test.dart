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
import 'package:malva_mental_health/src/screens/goals_screen.dart';
import 'package:malva_mental_health/src/services/malva_api_client.dart';
import 'package:malva_mental_health/src/theme.dart';
import 'package:malva_mental_health/src/time/wib.dart';
import 'record_render_capture.dart';

void main() {
  setUpAll(loadRecordCaptureFonts);
  for (final method in ['yes_no', 'numeric', 'checklist']) {
    testWidgets(
        'frequency $method completes twice and preserves partial on undo',
        (tester) async {
      FlutterSecureStorage.setMockInitialValues({});
      tester.view.physicalSize = const Size(390, 1300);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      enableRecordCaptureRendering();
      final boundary = GlobalKey();
      var count = 0;
      var value = method == 'numeric' ? 6 : 0;
      var steps = method == 'checklist' ? ['a'] : <String>[];
      final keys = <String>{};
      final actions = <String>[];
      final date = wibDateKey(wibNow());
      final goal = <String, dynamic>{
        'id': 'goal',
        'title': 'Membaca buku',
        'category': 'general',
        'target_per_week': 5,
        'is_active': true,
        'details': {
          'method': method,
          'target': 7,
          'unit': 'halaman',
          'start_date': '2026-01-01',
          'recurrence': 'weekly',
          'weekly_target': 5,
          'steps': [
            {'id': 'a', 'label': 'Siapkan buku'},
            {'id': 'b', 'label': 'Baca buku'}
          ],
        },
        'is_due': true,
      };
      final container = ProviderContainer(overrides: [
        apiClientProvider.overrideWithValue(MalvaApiClient(
          baseUrl: 'https://goal.test',
          httpClient: MockClient((request) async {
            if (request.method == 'GET') {
              return http.Response(
                  jsonEncode(request.url.path == '/v1/habit-logs'
                      ? {'logs': []}
                      : {
                          'goals': [
                            {
                              ...goal,
                              'done_today': count > 0,
                              'done_this_week': count,
                              'today_sessions': count,
                              'today_value': method == 'yes_no' ? count : value,
                              'today_completed_step_ids': steps,
                            }
                          ]
                        }),
                  200);
            }
            final data = jsonDecode(request.body) as Map<String, dynamic>;
            final action = data['session_action'] as String?;
            if (action != null) {
              expect(data.containsKey('value'), isFalse);
              expect(data.containsKey('completed_step_ids'), isFalse);
              expect(request.headers['Idempotency-Key'], isNotEmpty);
              expect(keys.add(request.headers['Idempotency-Key']!), isTrue);
              actions.add(action);
              count += action == 'complete' ? 1 : -1;
              if (action == 'complete') {
                value = 0;
                steps = [];
              }
            } else {
              value = data['value'] as int? ?? value;
              steps = (data['completed_step_ids'] as List?)?.cast<String>() ??
                  steps;
            }
            return http.Response(
                jsonEncode({
                  'log': {
                    'id': 'log',
                    'goal_id': 'goal',
                    'logged_on': date,
                    'done': count > 0,
                    'sessions': count,
                    'value': method == 'yes_no' ? count : value,
                    'completed_step_ids': steps,
                  }
                }),
                200);
          }),
        )),
      ]);
      addTearDown(container.dispose);
      container.read(authStateProvider.notifier).setSession(const AuthSession(
            role: UserRole.patient,
            identifier: 'patient',
            displayName: 'Pasien',
            accessToken: 'test',
          ));
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: RepaintBoundary(
          key: boundary,
          child: MaterialApp(
            theme: buildMalvaTheme(),
            home: const GoalsScreen(),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('0/5 sesi'), findsOneWidget);
      await captureRecord(tester, boundary, 'frequency-$method-initial.png');
      for (var i = 1; i <= 2; i++) {
        await tester.ensureVisible(find.text('Ya'));
        await tester.tap(find.text('Ya'));
        await tester.pumpAndSettle();
        expect(find.text('$i/5 sesi'), findsOneWidget);
        if (method == 'numeric') {
          expect(
              tester
                  .widget<TextField>(find.byKey(const Key('goal-value-goal')))
                  .controller!
                  .text,
              '0');
          expect(find.text('/ 7 halaman'), findsOneWidget);
        }
        if (method == 'checklist')
          expect(find.text('0/2 selesai'), findsOneWidget);
      }
      if (method == 'numeric') {
        await tester
            .ensureVisible(find.byTooltip('Tambah progres Membaca buku'));
        await tester.tap(find.byTooltip('Tambah progres Membaca buku'));
        await tester.pumpAndSettle();
      } else if (method == 'checklist') {
        await tester.ensureVisible(find.text('Siapkan buku'));
        await tester.tap(find.text('Siapkan buku'));
        await tester.pumpAndSettle();
      }
      await tester.ensureVisible(find.text('Undo'));
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(find.text('1/5 sesi'), findsOneWidget);
      if (method == 'numeric') {
        expect(
            tester
                .widget<TextField>(find.byKey(const Key('goal-value-goal')))
                .controller!
                .text,
            '1');
        expect(find.text('/ 7 halaman'), findsOneWidget);
        TextDecoration? titleDecoration() =>
            tester.widget<Text>(find.text('Membaca buku')).style?.decoration;
        expect(titleDecoration(), isNull);
        final add = find.byTooltip('Tambah progres Membaca buku');
        for (var i = 2; i <= 8; i++) {
          await tester.ensureVisible(add);
          await tester.tap(add);
          await tester.pumpAndSettle();
          expect(titleDecoration(), i >= 7 ? TextDecoration.lineThrough : null);
        }
      }
      if (method == 'checklist')
        expect(find.text('1/2 selesai'), findsOneWidget);
      expect(actions, ['complete', 'complete', 'undo']);
      expect(tester.takeException(), isNull);
      await captureRecord(tester, boundary, 'frequency-$method-after-undo.png');
      resetRecordCaptureRendering();
    });
  }

  test('undo from an earlier date retains selected numeric progress', () {
    final goal = BackendGoal.fromJson({
      'id': 'g',
      'details': {
        'method': 'numeric',
        'target': 7,
        'recurrence': 'weekly',
        'weekly_target': 5
      },
      'done_this_week': 2,
      'done_today': false,
      'today_value': 3,
      'today_sessions': 0,
    });
    final updated = goal.withProgress(
        const BackendHabitLog(
          id: 'l',
          goalId: 'g',
          loggedOn: '2026-11-23',
          done: true,
          value: 0,
          sessions: 1,
        ),
        selectedDate: '2026-11-28',
        sessionAction: 'undo');
    expect(updated.doneThisWeek, 1);
    expect(updated.todayValue, 3);
    expect(updated.todaySessions, 0);
    expect(updated.doneToday, isFalse);
  });

  test('historical method edit preserves independent completed sessions', () {
    final old = BackendGoal.fromJson({
      'id': 'g',
      'title': 'Read',
      'done_today': true,
      'done_this_week': 3,
      'today_value': 2,
      'today_sessions': 3,
      'details': {
        'method': 'numeric',
        'target': 7,
        'recurrence': 'weekly',
        'weekly_target': 5
      },
    });
    final saved = BackendGoal.fromJson({
      'id': 'g',
      'title': 'Read',
      'details': {
        'method': 'yes_no',
        'recurrence': 'weekly',
        'weekly_target': 5
      },
    });
    final updated = old.withDefinition(saved, on: wibFromParts(2026, 11, 27));
    expect(updated.todayValue, 3);
    expect(updated.todaySessions, 3);
    expect(updated.doneThisWeek, 3);
    expect(updated.doneToday, isTrue);
  });

  for (final priorWeek in [false, true]) {
    testWidgets('local legacy session count respects date scope $priorWeek',
        (tester) async {
      FlutterSecureStorage.setMockInitialValues({});
      tester.view.physicalSize = const Size(390, 1300);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final now = wibFromParts(2026, 11, 28, 12);
      container.read(malvaStoreProvider.notifier).upsertGoal(GoalItem(
            id: 'local',
            title: 'Latihan',
            frequency: 'Mingguan',
            streakDays: 0,
            completedToday: true,
            reminder: const TimeOfDay(hour: 9, minute: 0),
            note: '',
            value: 3,
            progressOn: priorWeek
                ? wibDateKey(now.subtract(const Duration(days: 7)))
                : null,
            details: const GoalDetails(
                startDate: '2026-01-01', recurrence: 'weekly', weeklyTarget: 5),
          ));
      await tester.pumpWidget(UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
              theme: buildMalvaTheme(), home: GoalsScreen(now: () => now))));
      await tester.pumpAndSettle();
      expect(find.text('${priorWeek ? 0 : 3}/5 sesi'), findsOneWidget);
      if (!priorWeek) {
        await tester.ensureVisible(find.text('Ya'));
        await tester.tap(find.text('Ya'));
        await tester.pumpAndSettle();
        expect(find.text('4/5 sesi'), findsOneWidget);
        await tester.tap(find.text('Undo'));
        await tester.pumpAndSettle();
        expect(find.text('3/5 sesi'), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });
  }
}
