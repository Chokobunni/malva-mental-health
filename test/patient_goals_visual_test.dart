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
import 'package:malva_mental_health/src/screens/goals/goal_editor.dart';
import 'package:malva_mental_health/src/services/malva_api_client.dart';
import 'package:malva_mental_health/src/theme.dart';
import 'package:malva_mental_health/src/time/wib.dart';
import 'record_render_capture.dart';

// Synthetic fixtures matching the user's visual references, never seeded into patient data.
final visualGoals = [
  {
    'id': 'a',
    'title': 'Olahraga Kardio / Jalan Pagi',
    'category': 'general',
    'target_per_week': 4,
    'is_active': true,
    'details': {
      'method': 'yes_no',
      'note':
          'Minimal 30 menit di pagi hari agar tubuh bugar sepanjang minggu.',
      'start_date': '2026-11-11',
      'time': '06:30',
      'recurrence': 'weekly',
      'weekly_target': 4,
      'interval': 1,
      'weekdays': [1, 2, 3, 4, 5, 6, 7],
      'reminders': [10],
      'auto_fail': true,
      'lock_past': false,
      'target': 1,
      'unit': '',
      'steps': [
        {'id': 'activity-a', 'label': 'Siapkan sepatu dan air minum'},
        {'id': 'activity-b', 'label': 'Jalan santai selama 30 menit'}
      ]
    },
    'done_today': true,
    'done_this_week': 3,
    'completed_weekdays': [1, 2, 3],
    'streak_days': 12,
    'is_due': true
  },
  {
    'id': 'b',
    'title': 'Baca Buku Pengembangan Diri',
    'category': 'general',
    'target_per_week': 7,
    'is_active': true,
    'details': {
      'method': 'numeric',
      'note': '',
      'start_date': '2026-11-11',
      'time': '21:30',
      'recurrence': 'weekly',
      'interval': 1,
      'weekdays': [1, 2, 3, 4, 5],
      'reminders': [30],
      'auto_fail': true,
      'lock_past': false,
      'target': 20,
      'unit': 'halaman',
      'steps': [
        {'id': 'reading-a', 'label': 'Siapkan buku yang ingin dibaca'},
        {'id': 'reading-b', 'label': 'Baca dan catat gagasan utama'}
      ]
    },
    'done_today': false,
    'today_value': 14,
    'done_this_week': 2,
    'completed_weekdays': [1, 2],
    'streak_days': 8,
    'is_due': true
  },
  {
    'id': 'c',
    'title': 'Rutinitas Malam & Perawatan Diri',
    'category': 'general',
    'target_per_week': 7,
    'is_active': true,
    'details': {
      'method': 'checklist',
      'note':
          'Persiapan agar kualitas tidur lebih nyenyak dan bangun lebih segar.',
      'start_date': '2026-11-11',
      'time': '22:00',
      'recurrence': 'daily',
      'interval': 1,
      'weekdays': [1, 2, 3, 4, 5, 6, 7],
      'reminders': [15],
      'auto_fail': true,
      'lock_past': true,
      'target': 1,
      'unit': '',
      'steps': [
        {
          'id': 's1',
          'label': 'Matikan layar HP & laptop 30 menit sebelum tidur'
        },
        {'id': 's2', 'label': 'Cuci muka & gunakan pelembap malam'},
        {'id': 's3', 'label': 'Tulis 3 hal yang disyukuri hari ini'}
      ]
    },
    'done_today': false,
    'today_completed_step_ids': ['s1', 's2'],
    'streak_days': 5,
    'is_due': true
  },
  {
    'id': 'd',
    'title': 'Latihan Peregangan & Mobilitas',
    'category': 'general',
    'target_per_week': 3,
    'is_active': true,
    'details': {
      'method': 'numeric',
      'note': '',
      'start_date': '2026-11-11',
      'time': '07:00',
      'recurrence': 'weekly',
      'interval': 1,
      'weekdays': [1, 3, 5],
      'reminders': [30],
      'auto_fail': true,
      'lock_past': false,
      'target': 15,
      'unit': 'menit',
      'steps': []
    },
    'done_today': true,
    'today_value': 15,
    'done_this_week': 2,
    'completed_weekdays': [1, 3],
    'streak_days': 6,
    'is_due': true
  },
];

void main() {
  setUpAll(loadRecordCaptureFonts);
  testWidgets('reference list renders with real status fields', (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    tester.view.physicalSize = const Size(390, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    enableRecordCaptureRendering();
    final container = ProviderContainer(overrides: [
      apiClientProvider.overrideWithValue(MalvaApiClient(
          baseUrl: 'https://synthetic.test',
          httpClient: MockClient((r) async =>
              http.Response(jsonEncode({'goals': visualGoals}), 200))))
    ]);
    addTearDown(container.dispose);
    container.read(authStateProvider.notifier).setSession(const AuthSession(
        role: UserRole.patient,
        identifier: 'visual',
        displayName: 'Pasien',
        accessToken: 'synthetic'));
    final boundary = GlobalKey();
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: RepaintBoundary(
            key: boundary,
            child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: buildMalvaTheme(),
                home:
                    GoalsScreen(now: () => wibFromParts(2026, 11, 11, 12))))));
    await tester.pumpAndSettle();
    tester.view.physicalSize = Size(
        390, tester.getSize(find.byKey(const Key('goal-list-content'))).height);
    await tester.pumpAndSettle();
    await captureRecord(tester, boundary, '01-list.png');
    resetRecordCaptureRendering();
    expect(find.text('50%'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.byKey(const Key('goal-filter-numeric')));
    await tester.tap(find.byKey(const Key('goal-filter-numeric')));
    await tester.pumpAndSettle();
    expect(find.text('Olahraga Kardio / Jalan Pagi'), findsNothing);
    expect(find.text('Baca Buku Pengembangan Diri'), findsOneWidget);
  });
  for (var i = 0; i < 6; i++) {
    final edit = i >= 3, method = ['yes_no', 'numeric', 'checklist'][i % 3];
    testWidgets(
        'reference ${edit ? 'edit' : 'create'} $method renders at mobile width',
        (tester) async {
      tester.view.physicalSize = const Size(390, 2600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      enableRecordCaptureRendering();
      final boundary = GlobalKey();
      await tester.pumpWidget(RepaintBoundary(
          key: boundary,
          child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: recordCaptureEnabled
                  ? buildMalvaTheme().copyWith(
                      filledButtonTheme: FilledButtonThemeData(
                          style: buildMalvaTheme()
                              .filledButtonTheme
                              .style!
                              .copyWith(
                                  textStyle: const WidgetStatePropertyAll(
                                      TextStyle(
                                          fontFamily: 'Roboto',
                                          fontWeight: FontWeight.w800,
                                          fontSize: 16)))))
                  : buildMalvaTheme(),
              home: GoalEditor(
                  goal: edit ? BackendGoal.fromJson(visualGoals[i % 3]) : null,
                  onSave: (_) async => true))));
      await tester.pumpAndSettle();
      await tester.runAsync(() => precacheImage(
          const AssetImage('assets/goals/flower-white.png'),
          tester.element(find.byType(GoalEditor))));
      await tester.pumpAndSettle();

      if (!edit) {
        await tester.tap(find.byKey(Key('goal-method-$method')));
        await tester.pumpAndSettle();
        if (method == 'checklist') {
          await tester.enterText(find.byKey(const Key('goal-new-step')),
              'Siapkan buku di meja samping tempat tidur');
          await tester.ensureVisible(find.text('Tambah Langkah'));
          await tester.tap(find.text('Tambah Langkah'));
          await tester.pumpAndSettle();
        }
        if (method == 'numeric') {
          await tester.enterText(find.byKey(const Key('goal-target')), '20');
          await tester.enterText(find.byKey(const Key('goal-unit')), 'halaman');
        }
        await tester.ensureVisible(find.text('Rincian Target Utama'));
        await tester.pumpAndSettle();
      }
      tester.view.physicalSize = Size(
          390,
          tester.getSize(find.byKey(const Key('goal-editor-content'))).height +
              10);
      await tester.pumpAndSettle();
      await captureRecord(tester, boundary,
          '0${i + 2}-${edit ? 'edit' : 'create'}-$method.png');
      if (i == 3) {
        tester.view.physicalSize = const Size(390, 844);
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Tambah Pengingat'));
        await tester.tap(find.text('Tambah Pengingat'));
        await tester.pumpAndSettle();
        await captureRecord(tester, boundary, '08-reminder-dialog.png');
        expect(find.textContaining('0–10080'), findsNothing);
      }
      resetRecordCaptureRendering();
      expect(tester.takeException(), isNull);
    });
  }
  for (final width in [320.0, 390.0]) {
    testWidgets('large text editor fits width $width', (tester) async {
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
          theme: buildMalvaTheme(),
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(1.35)),
              child: child!),
          home: GoalEditor(
              goal: BackendGoal.fromJson(visualGoals[1]),
              onSave: (_) async => true)));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Simpan Perubahan'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
