import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:malva_mental_health/src/models.dart';
import 'package:malva_mental_health/src/providers/providers.dart';
import 'package:malva_mental_health/src/screens/goals_screen.dart';
import 'package:malva_mental_health/src/screens/goals/goal_history_panel.dart';
import 'package:malva_mental_health/src/screens/goals/goal_numeric_progress.dart';
import 'package:malva_mental_health/src/services/malva_api_client.dart';
import 'package:malva_mental_health/src/time/wib.dart';
import 'package:malva_mental_health/src/theme.dart';
import 'record_render_capture.dart';

void main() {
  late GlobalKey boundary;
  Future<void> open(WidgetTester tester, {bool archive = false}) async {
    FlutterSecureStorage.setMockInitialValues({});
    tester.view.physicalSize = const Size(430, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await loadRecordCaptureFonts();
    boundary = GlobalKey();
    var value = 2;
    final container = ProviderContainer(overrides: [
      apiClientProvider.overrideWithValue(MalvaApiClient(
        baseUrl: 'https://goals.test',
        httpClient: MockClient((request) async {
          if (request.method == 'POST') {
            value = jsonDecode(request.body)['value'] as int;
            return http.Response(
                jsonEncode({
                  'log': {
                    'id': 'l',
                    'goal_id': 'g',
                    'logged_on': '2026-11-28',
                    'done': value >= 8,
                    'value': value,
                  }
                }),
                200);
          }
          return http.Response(
              jsonEncode({
                'goals': [
                  {
                    'id': 'g',
                    'title': 'Minum air',
                    'is_active': !archive,
                    'is_due': true,
                    'today_value': value,
                    'details': {
                      'method': 'numeric',
                      'target': 8,
                      'unit': 'gelas',
                      'start_date': '2026-11-01',
                      'recurrence': 'weekly',
                      'weekdays': [6, 7],
                      'time': '08:00',
                      'reminders': [0]
                    },
                  }
                ]
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
        child: RepaintBoundary(
            key: boundary,
            child: MaterialApp(
                theme: recordCaptureTheme(buildMalvaTheme()),
                home: GoalsScreen(
                    showArchive: archive,
                    now: () => wibFromParts(2026, 11, 28, 12))))));
    await tester.pumpAndSettle();
  }

  testWidgets('numeric value can be typed, saved, and incremented',
      (tester) async {
    await open(tester);
    final field = find.byKey(const Key('goal-value-g'));
    expect(field, findsOneWidget);
    await tester.enterText(field, '7');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(field).controller!.text, '7');
    await tester.tap(find.byTooltip('Tambah progres Minum air'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(field).controller!.text, '8');
    expect(tester.widget<Text>(find.text('Minum air')).style!.decoration,
        TextDecoration.lineThrough);
    await captureRecord(tester, boundary, 'goal-numeric-input.png');
    await tester.enterText(field, '9999999');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(field).controller!.text, '8');
    await tester.enterText(field, '100');
    await tester.tap(find.byTooltip('Kurangi progres Minum air'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(field).controller!.text, '99');
  });

  testWidgets('archive hides editing and live schedule markers',
      (tester) async {
    await open(tester, archive: true);
    expect(find.byTooltip('Edit goal'), findsNothing);
    expect(find.byIcon(Icons.notifications_off_outlined), findsOneWidget);
    expect(find.text('Jadwal hari ini'), findsNothing);
    expect(find.text('Di luar jadwal'), findsNothing);
    expect(find.byIcon(Icons.circle), findsNothing);
    expect(find.text('Sab'), findsOneWidget);
    expect(find.text('Min'), findsOneWidget);
    expect(find.byKey(const Key('goal-value-g')), findsNothing);
    await captureRecord(tester, boundary, 'goal-archive.png');
  });

  testWidgets(
      'switching numeric cards commits the draft and rejected saves restore the stored value',
      (tester) async {
    final values = [0, 0];
    var accept = true;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: StatefulBuilder(
                builder: (context, setState) => Column(children: [
                      for (var i = 0; i < 2; i++)
                        GoalNumericProgress(
                            id: '$i',
                            title: 'Angka $i',
                            value: values[i],
                            target: 100,
                            unit: 'kali',
                            locked: false,
                            readOnly: false,
                            onSave: (value) async {
                              if (accept) setState(() => values[i] = value);
                            }),
                    ])))));
    final first = find.byKey(const Key('goal-value-0'));
    await tester.enterText(first, '5');
    await tester.tap(find.byKey(const Key('goal-value-1')));
    await tester.pumpAndSettle();
    expect(values, [5, 0]);
    accept = false;
    await tester.enterText(first, '7');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(first).controller!.text, '5');
  });

  testWidgets('every history result has an arrow and opens its own detail',
      (tester) async {
    final day = wibFromParts(2026, 11, 27);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: GoalHistoryPanel(
      goals: [
        BackendGoal.fromJson({
          'id': 'g',
          'title': 'Baca buku',
          'details': {
            'method': 'numeric',
            'target': 7,
            'unit': 'halaman',
            'start_date': '2026-11-27'
          }
        })
      ],
      logs: const [
        BackendHabitLog(
            id: 'l', goalId: 'g', loggedOn: '2026-11-27', done: false, value: 4)
      ],
      range: DateTimeRange(start: day, end: day),
      today: day,
      rangeLabel: 'Tanggal pilihan',
      onRangeChanged: (_) {},
      method: '',
      onMethodChanged: (_) {},
      onArchive: () {},
      loading: false,
      error: null,
      onRetry: () {},
    )))));
    await tester.tap(find.byType(ExpansionTile));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('goal-history-open-g-2026-11-27')),
        findsOneWidget);
    await tester.tap(find.text('Baca buku'));
    await tester.pumpAndSettle();
    expect(find.text('Progres tercatat: 4/7 halaman'), findsOneWidget);
    expect(find.text('57%'), findsOneWidget);
    expect(find.text('Jumat, 27 November 2026'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets(
      'normal history uses the selected date snapshot and guards account switches',
      (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    tester.view.physicalSize = const Size(430, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await loadRecordCaptureFonts();
    final capture = GlobalKey();
    final requestedDates = <String>[];
    final container = ProviderContainer(overrides: [
      apiClientProvider.overrideWithValue(MalvaApiClient(
          baseUrl: 'https://goals.test',
          httpClient: MockClient((request) async {
            if (request.url.path == '/v1/habit-logs') {
              return http.Response(
                  jsonEncode({
                    'logs': [
                      {
                        'id': 'l',
                        'goal_id': 'g',
                        'logged_on': '2026-11-27',
                        'done': true,
                        'sessions': 1,
                      }
                    ]
                  }),
                  200);
            }
            final date = request.url.queryParameters['on']!;
            requestedDates.add(date);
            return http.Response(
                jsonEncode({
                  'goals': [
                    {
                      'id': 'g',
                      'title': 'Journaling pribadi',
                      'is_active': true,
                      'is_due': true,
                      'done_today': true,
                      'today_sessions': 1,
                      'done_this_week': date == '2026-11-27' ? 3 : 9,
                      'streak_days': date == '2026-11-27' ? 1 : 9,
                      'details': {
                        'method': 'yes_no',
                        'start_date': '2026-11-20',
                        'recurrence': 'weekly',
                        'weekly_target': 4,
                        'note': 'Catatan pribadi'
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
        identifier: 'a',
        displayName: 'A',
        accessToken: 'a'));
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: RepaintBoundary(
            key: capture,
            child: MaterialApp(
                theme: recordCaptureTheme(buildMalvaTheme()),
                home:
                    GoalsScreen(now: () => wibFromParts(2026, 11, 28, 12))))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Riwayat'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(ExpansionTile));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Journaling pribadi'));
    await tester.pumpAndSettle();
    expect(requestedDates.last, '2026-11-27');
    expect(find.text('1 hari'), findsOneWidget);
    expect(find.text('3/4 sesi'), findsOneWidget);
    expect(find.text('9 hari'), findsNothing);
    expect(find.text('Selesai dilakukan'), findsOneWidget);
    await captureRecord(tester, capture, 'goal-history-detail.png');
    container.read(authStateProvider.notifier).setSession(const AuthSession(
        role: UserRole.patient,
        identifier: 'b',
        displayName: 'B',
        accessToken: 'b'));
    await tester.pumpAndSettle();
    expect(find.text('Journaling pribadi'), findsNothing);
    expect(find.text('Catatan pribadi'), findsNothing);
    expect(find.text('Sesi akun telah berubah.'), findsOneWidget);
  });
}
