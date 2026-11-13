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

BackendGoal goal({GoalDetails? details, int quota = 3}) => BackendGoal(
    id: 'g',
    title: 'Habit nyata',
    category: 'general',
    targetPerWeek: quota,
    isActive: true,
    createdAt: wibFromParts(2026, 10, 11, 6),
    details: details);

void size(WidgetTester t) {
  t.view.physicalSize = const Size(390, 1100);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

Future<void> tap(WidgetTester t, Finder f) async {
  await t.ensureVisible(f);
  await t.tap(f);
  await t.pumpAndSettle();
}

Future<void> list(WidgetTester t, Map<String, dynamic> data) async {
  FlutterSecureStorage.setMockInitialValues({});
  final c = ProviderContainer(overrides: [
    apiClientProvider.overrideWithValue(MalvaApiClient(
        baseUrl: 'https://goals.test',
        httpClient: MockClient((r) async => http.Response(
            jsonEncode(r.url.path == '/v1/habit-logs'
                ? {'logs': []}
                : {
                    'goals': [data]
                  }),
            200))))
  ]);
  addTearDown(c.dispose);
  c.read(authStateProvider.notifier).setSession(const AuthSession(
      role: UserRole.patient,
      identifier: 'p',
      displayName: 'P',
      accessToken: 't'));
  await t.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
          theme: buildMalvaTheme(),
          home: GoalsScreen(now: () => wibFromParts(2026, 11, 13, 12)))));
  await t.pumpAndSettle();
}

Map<String, dynamic> record(Map<String, dynamic> details) => {
      'id': 'g',
      'title': 'Habit nyata',
      'target_per_week': 3,
      'is_active': true,
      'is_due': true,
      'details': details,
      'done_this_week': 2,
    };

void main() {
  for (final reason in ['pre-start', 'inactive', 'locked history']) {
    testWidgets('checklist still blocks $reason progress', (t) async {
      size(t);
      await list(t, {
        ...record({
          'method': 'checklist',
          'start_date': reason == 'pre-start' ? '2026-11-14' : '2026-01-01',
          'lock_past': reason == 'locked history',
          'steps': [
            {'id': 'a', 'label': 'A'}
          ]
        }),
        'is_active': reason != 'inactive',
        'is_due': false,
      });
      if (reason == 'locked history' || reason == 'inactive') {
        await tap(t, find.text('Jumat, 13 November 2026'));
        await t.tap(find.text('11'));
        await t.tap(find.text('OK'));
        await t.pumpAndSettle();
      }
      await t.ensureVisible(find.byType(Checkbox));
      expect(t.widget<Checkbox>(find.byType(Checkbox)).onChanged, isNull);
      expect(t.takeException(), isNull);
    });
  }

  for (final method in ['yes_no', 'numeric']) {
    testWidgets(
        '$method activity descriptions are bullets and persist stable IDs',
        (t) async {
      size(t);
      GoalEditorResult? saved;
      await t.pumpWidget(MaterialApp(
          theme: buildMalvaTheme(),
          home: GoalEditor(
              goal: goal(
                  details: GoalDetails(
                      startDate: '2026-01-01',
                      method: method,
                      target: 20,
                      unit: 'halaman',
                      steps: const [
                    GoalStep(id: 'a', label: 'Persiapan'),
                    GoalStep(id: 'b', label: 'Pelaksanaan')
                  ])),
              onSave: (r) async {
                saved = r;
                return false;
              })));
      await t.ensureVisible(find.text('Persiapan'));
      expect(find.text('Rincian Aktivitas'), findsOneWidget);
      expect(find.text('Daftar Langkah (Checklist)'), findsNothing);
      expect(find.text('•'), findsNWidgets(2));
      await tap(t, find.text('Simpan Perubahan'));
      expect(saved!.details.steps.map((s) => s.toJson()).toList(), [
        {'id': 'a', 'label': 'Persiapan'},
        {'id': 'b', 'label': 'Pelaksanaan'}
      ]);
      expect(saved!.details.method, method);
    });
    testWidgets(
        '$method card shows activity text without step completion controls',
        (t) async {
      size(t);
      await list(
          t,
          record({
            'method': method,
            'start_date': '2026-01-01',
            'target': 20,
            'unit': 'halaman',
            'steps': [
              {'id': 'a', 'label': 'Persiapan'}
            ]
          }));
      await t.ensureVisible(find.text('Habit nyata'));
      expect(find.text('Persiapan'), findsOneWidget);
      expect(find.text('Rincian Aktivitas'), findsOneWidget);
      expect(find.byType(Checkbox), findsNothing);
    });
  }

  testWidgets(
      'legacy quota edit retains weekly intent without invented daily time',
      (t) async {
    size(t);
    GoalEditorResult? saved;
    await t.pumpWidget(MaterialApp(
        theme: buildMalvaTheme(),
        home: GoalEditor(
            goal: goal(quota: 4),
            onSave: (r) async {
              saved = r;
              return false;
            })));
    await tap(t, find.text('Simpan Perubahan'));
    expect(saved!.details.recurrence, 'weekly');
    expect(saved!.details.weeklyTarget, 4);
    expect(saved!.details.time, isEmpty);
    expect(saved!.details.startDate, '2026-10-11');
  });

  for (final schedule in <Map<String, dynamic>>[
    {
      'recurrence': 'daily',
      'interval': 1,
      'weekdays': [1, 2, 3, 4, 5, 6, 7]
    },
    {
      'recurrence': 'daily',
      'interval': 3,
      'weekdays': [1, 2, 3, 4, 5, 6, 7]
    },
    {
      'recurrence': 'weekly',
      'interval': 1,
      'weekdays': [5, 6, 7]
    },
    {
      'recurrence': 'weekly',
      'interval': 2,
      'weekdays': [1, 3]
    },
    {'recurrence': 'weekly', 'interval': 1, 'weekdays': [], 'weekly_target': 4},
    {'recurrence': 'weekly', 'interval': 2, 'weekdays': [], 'weekly_target': 0},
    {'recurrence': 'monthly', 'interval': 2, 'weekdays': []},
  ]) {
    testWidgets(
        'editing ${jsonEncode(schedule)} preserves complete stored configuration',
        (t) async {
      size(t);
      GoalEditorResult? saved;
      final original = GoalDetails.fromJson({
        'method': 'numeric',
        'target': 20,
        'unit': 'halaman',
        'start_date': '2026-10-31',
        'time': '06:30',
        'reminders': [0, 30],
        'auto_fail': false,
        'lock_past': true,
        'note': 'Catatan asli',
        'steps': [
          {'id': 'stable', 'label': 'Aktivitas asli'}
        ],
        ...schedule
      });
      await t.pumpWidget(MaterialApp(
          theme: buildMalvaTheme(),
          home: GoalEditor(
              goal: goal(details: original),
              onSave: (r) async {
                saved = r;
                return false;
              })));
      if (schedule['weekly_target'] == 0 && schedule['interval'] == 2) {
        expect(
            t
                .widgetList<RichText>(find.byType(RichText))
                .any((w) => w.text.toPlainText().contains('setiap 2 minggu')),
            isTrue);
      }
      await tap(t, find.text('Simpan Perubahan'));
      expect(saved!.details.toJson(), original.toJson());
      // Reopening the accepted response must retain the same state again.
      await t.pumpWidget(const SizedBox());
      await t.pumpWidget(MaterialApp(
          theme: buildMalvaTheme(),
          home: GoalEditor(
              goal: goal(details: saved!.details),
              onSave: (r) async {
                saved = r;
                return false;
              })));
      await tap(t, find.text('Simpan Perubahan'));
      expect(saved!.details.toJson(), original.toJson());
    });
  }

  testWidgets(
      'first weekly card counts Friday to Sunday rather than days before start',
      (t) async {
    size(t);
    await list(
        t,
        record({
          'method': 'yes_no',
          'start_date': '2026-11-13',
          'recurrence': 'weekly',
          'interval': 1,
          'weekdays': [1, 2, 3, 4, 5, 6, 7]
        }));
    expect(find.text('Hari terpilih (3×/minggu)'), findsOneWidget);
    expect(find.text('Hari terpilih (7×/minggu)'), findsNothing);
  });
  testWidgets(
      'daily card derives weekly denominator from schedule instead of legacy quota',
      (t) async {
    size(t);
    await list(
        t,
        record({
          'method': 'yes_no',
          'start_date': '2026-01-01',
          'recurrence': 'daily',
          'interval': 1
        }));
    expect(find.text('2/7 kali'), findsOneWidget);
    expect(find.text('2/3 kali'), findsNothing);
  });
  for (final value in [0, 1, 2]) {
    testWidgets(
        'reminder bell only with configured time and offsets case$value',
        (t) async {
      size(t);
      await list(
          t,
          record({
            'method': 'yes_no',
            'start_date': '2026-01-01',
            'time': value == 2 ? '' : '06:30',
            'reminders': value == 0 ? [] : [0]
          }));
      expect(find.byTooltip('Pengingat aktif • jadwal pukul 06.30 WIB'),
          value == 1 ? findsOneWidget : findsNothing);
    });
  }
  testWidgets(
      'reminder dialog omits range helper and rejects invalid input visibly',
      (t) async {
    size(t);
    await t.pumpWidget(MaterialApp(
        theme: buildMalvaTheme(),
        home: GoalEditor(onSave: (_) async => false)));
    await tap(t, find.text('Tambah Pengingat'));
    expect(find.textContaining('0–10080 menit (0 ='), findsNothing);
    final field = find.descendant(
        of: find.byType(AlertDialog), matching: find.byType(TextField));
    await t.enterText(field, '10081');
    await tap(t, find.text('Tambah'));
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(t.widget<TextField>(field).decoration!.errorText, isNotNull);
    await t.enterText(field, '0');
    await tap(t, find.text('Tambah'));
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Saat waktunya'), findsOneWidget);
  });
  test(
      'accepted extra checklist progress does not invent scheduled weekly credit',
      () {
    final g = BackendGoal.fromJson({
      ...record({
        'method': 'checklist',
        'start_date': '2026-01-01',
        'steps': [
          {'id': 'a', 'label': 'A'}
        ]
      }),
      'is_due': false,
      'done_this_week': 2,
      'completed_weekdays': [1, 2]
    });
    final accepted = g.withProgress(BackendHabitLog.fromJson({
      'id': 'l',
      'goal_id': 'g',
      'logged_on': '2026-11-13',
      'done': true,
      'completed_step_ids': ['a']
    }));
    expect(accepted.doneToday, isTrue);
    expect(accepted.doneThisWeek, 2);
    expect(accepted.completedWeekdays, [1, 2]);
    expect(
        accepted
            .withProgress(BackendHabitLog.fromJson({
              'id': 'l',
              'goal_id': 'g',
              'logged_on': '2026-11-13',
              'done': false,
              'completed_step_ids': []
            }))
            .failedToday,
        isFalse);
  });

  for (final failedReload in [false, true]) {
    testWidgets(
        'recorded checklist corrects and reopens empty log through ${failedReload ? 'failed' : 'successful'} reload',
        (t) async {
      size(t);
      FlutterSecureStorage.setMockInitialValues({});
      var ids = <String>['a'];
      var writes = 0;
      var fail = failedReload;
      Map<String, dynamic> snapshot() => {
            ...record({
              'method': 'checklist',
              'start_date': '2026-11-01',
              'recurrence': 'weekly',
              'interval': 1,
              'weekdays': [6, 7],
              'steps': [
                {'id': 'a', 'label': 'A'},
                {'id': 'b', 'label': 'B'}
              ]
            }),
            'is_due': false,
            'done_this_week': 0,
            'done_today': ids.length == 2,
            'today_completed_step_ids': ids
          };
      final c = ProviderContainer(overrides: [
        apiClientProvider.overrideWithValue(MalvaApiClient(
            baseUrl: 'https://goals.test',
            httpClient: MockClient((r) async {
              if (r.method == 'GET' && r.url.path == '/v1/habit-logs') {
                expect(r.url.queryParameters['from'], '2026-11-13');
                expect(r.url.queryParameters['to'], '2026-11-13');
                return http.Response(
                    jsonEncode({
                      'logs': [
                        {
                          'id': 'l',
                          'goal_id': 'g',
                          'logged_on': '2026-11-13',
                          'done': ids.length == 2,
                          'completed_step_ids': ids
                        }
                      ]
                    }),
                    200);
              }
              if (r.method == 'GET')
                return fail && writes > 0
                    ? http.Response('{"error":"refresh gagal"}', 503)
                    : http.Response(
                        jsonEncode({
                          'goals': [snapshot()]
                        }),
                        200);
              final body = jsonDecode(r.body) as Map<String, dynamic>;
              expect(body['logged_on'], '2026-11-13');
              ids = (body['completed_step_ids'] as List).cast<String>();
              writes++;
              return http.Response(
                  jsonEncode({
                    'log': {
                      'id': 'l',
                      'goal_id': 'g',
                      'logged_on': '2026-11-13',
                      'done': ids.length == 2,
                      'completed_step_ids': ids
                    }
                  }),
                  200);
            })))
      ]);
      addTearDown(c.dispose);
      c.read(authStateProvider.notifier).setSession(const AuthSession(
          role: UserRole.patient,
          identifier: 'p',
          displayName: 'P',
          accessToken: 't'));
      Future<void> open() async {
        await t.pumpWidget(UncontrolledProviderScope(
            container: c,
            child: MaterialApp(
                theme: buildMalvaTheme(),
                home: GoalsScreen(now: () => wibFromParts(2026, 11, 13, 12)))));
        await t.pumpAndSettle();
      }

      await open();
      final checkboxes = find.byType(Checkbox);
      expect(t.widget<Checkbox>(checkboxes.last).onChanged, isNotNull);
      await tap(t, checkboxes.last);
      expect(find.text('2/2 selesai'), findsOneWidget);
      await tap(t, checkboxes.first);
      expect(find.text('1/2 selesai'), findsOneWidget);
      await tap(t, checkboxes.last);
      expect(find.text('0/2 selesai'), findsOneWidget);
      // An existing empty row must remain correctable after reopening.
      fail = false;
      await t.pumpWidget(const SizedBox());
      await open();
      expect(t.widget<Checkbox>(checkboxes.first).onChanged, isNotNull);
      fail = failedReload;
      await tap(t, checkboxes.first);
      expect(find.text('1/2 selesai'), findsOneWidget);
      expect(writes, 4);
      fail = false;
      await t.pumpWidget(const SizedBox());
      await open();
      expect(t.widget<Checkbox>(checkboxes.first).value, isTrue);
      expect(t.widget<Checkbox>(checkboxes.last).value, isFalse);
      expect(find.text('1/2 selesai'), findsOneWidget);
    });
  }

  for (final presence in ['absent', 'other-date', 'failed']) {
    testWidgets('off-schedule checklist blocks $presence record', (t) async {
      size(t);
      FlutterSecureStorage.setMockInitialValues({});
      var writes = 0;
      final c = ProviderContainer(overrides: [
        apiClientProvider.overrideWithValue(MalvaApiClient(
            baseUrl: 'https://goals.test',
            httpClient: MockClient((r) async {
              if (r.method == 'POST') {
                writes++;
                return http.Response('{}', 400);
              }
              if (r.url.path == '/v1/habit-logs') {
                if (presence == 'failed')
                  return http.Response('{"error":"gagal"}', 503);
                return http.Response(
                    jsonEncode({
                      'logs': presence == 'absent'
                          ? []
                          : [
                              {
                                'id': 'l',
                                'goal_id': 'g',
                                'logged_on': '2026-11-12',
                                'done': false,
                                'completed_step_ids': []
                              }
                            ]
                    }),
                    200);
              }
              return http.Response(
                  jsonEncode({
                    'goals': [
                      {
                        ...record({
                          'method': 'checklist',
                          'start_date': '2026-01-01',
                          'steps': [
                            {'id': 'a', 'label': 'A'}
                          ]
                        }),
                        'is_due': false
                      }
                    ]
                  }),
                  200);
            })))
      ]);
      addTearDown(c.dispose);
      c.read(authStateProvider.notifier).setSession(const AuthSession(
          role: UserRole.patient,
          identifier: 'p',
          displayName: 'P',
          accessToken: 't'));
      await t.pumpWidget(UncontrolledProviderScope(
          container: c,
          child: MaterialApp(
              theme: buildMalvaTheme(),
              home: GoalsScreen(now: () => wibFromParts(2026, 11, 13, 12)))));
      await t.pumpAndSettle();
      if (presence != 'failed') {
        final checkbox = find.byType(Checkbox);
        expect(t.widget<Checkbox>(checkbox).onChanged, isNull);
        await tap(t, checkbox);
      }
      expect(writes, 0);
      expect(find.text('Koreksi progres di luar jadwal'), findsNothing);
    });
  }

  for (final change in ['date', 'account']) {
    testWidgets('late day-log response cannot grant another $change correction',
        (t) async {
      size(t);
      FlutterSecureStorage.setMockInitialValues({});
      final pending = Completer<http.Response>();
      final c = ProviderContainer(overrides: [
        apiClientProvider.overrideWithValue(MalvaApiClient(
            baseUrl: 'https://goals.test',
            httpClient: MockClient((r) async {
              final date =
                  r.url.queryParameters['on'] ?? r.url.queryParameters['from'];
              if (r.url.path == '/v1/habit-logs') {
                if (date == '2026-11-13') return pending.future;
                return http.Response('{"logs":[]}', 200);
              }
              return http.Response(
                  jsonEncode({
                    'goals': [
                      {
                        ...record({
                          'method': 'checklist',
                          'start_date': '2026-01-01',
                          'steps': [
                            {'id': 'a', 'label': 'A'}
                          ]
                        }),
                        'is_due': false
                      }
                    ]
                  }),
                  200);
            })))
      ]);
      addTearDown(c.dispose);
      c.read(authStateProvider.notifier).setSession(const AuthSession(
          role: UserRole.patient,
          identifier: 'p',
          displayName: 'P',
          accessToken: 't'));
      await t.pumpWidget(UncontrolledProviderScope(
          container: c,
          child: MaterialApp(
              theme: buildMalvaTheme(),
              home: GoalsScreen(now: () => wibFromParts(2026, 11, 13, 12)))));
      await t.pumpAndSettle();
      if (change == 'date') {
        await tap(t, find.text('Jumat, 13 November 2026'));
        await t.tap(find.text('12'));
        await t.tap(find.text('OK'));
        await t.pumpAndSettle();
      } else {
        for (final owner in ['next', 'p']) {
          c.read(authStateProvider.notifier).setSession(AuthSession(
              role: UserRole.patient,
              identifier: owner,
              displayName: owner,
              accessToken: 't'));
          await t.pump();
        }
      }
      pending.complete(http.Response(
          '{"logs":[{"id":"l","goal_id":"g","logged_on":"2026-11-13","done":false,"completed_step_ids":[]}]}',
          200));
      await t.pumpAndSettle();
      if (change == 'date') {
        expect(t.widget<Checkbox>(find.byType(Checkbox)).onChanged, isNull);
        expect(find.text('Kamis, 12 November 2026'), findsOneWidget);
      } else {
        expect(find.byType(Checkbox), findsNothing);
        expect(find.text('Sesi akun telah berubah. Buka kembali Goals.'),
            findsOneWidget);
      }
    });
  }
}
