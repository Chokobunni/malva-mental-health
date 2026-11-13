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
import 'package:malva_mental_health/src/services/malva_api_client.dart';
import 'package:malva_mental_health/src/theme.dart';
import 'package:malva_mental_health/src/time/wib.dart';

Future<void> tapGoalControl(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  for (final historical in [false, true]) {
    testWidgets(
        'removed completed checklist step is excluded on ${historical ? 'historical' : 'today'} retry after edit refresh failure',
        (tester) async {
      FlutterSecureStorage.setMockInitialValues({});
      tester.view.physicalSize = const Size(430, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final yesterday = wibNow().subtract(const Duration(days: 1));
      var edited = false;
      Map<String, dynamic>? posted;
      final definition = <String, dynamic>{
        'id': 'g',
        'title': 'Daftar',
        'category': 'general',
        'target_per_week': 7,
        'is_active': true,
        'details': {
          'method': 'checklist',
          'start_date': '2026-01-01',
          'steps': [
            {'id': 'a', 'label': 'Langkah A'},
            {'id': 'b', 'label': 'Langkah B'}
          ]
        },
        'today_completed_step_ids': ['a'],
        'done_today': false,
        'is_due': true,
      };
      final container = ProviderContainer(overrides: [
        apiClientProvider.overrideWithValue(MalvaApiClient(
            baseUrl: 'https://goals.test',
            httpClient: MockClient((r) async {
              if (r.method == 'GET' && r.url.path == '/v1/habit-logs') {
                return http.Response(
                    jsonEncode({
                      'logs': [
                        {
                          'id': 'l',
                          'goal_id': 'g',
                          'logged_on': r.url.queryParameters['from'],
                          'done': false,
                          'completed_step_ids': ['a']
                        }
                      ]
                    }),
                    200);
              }
              if (r.method == 'GET')
                return edited
                    ? http.Response('{"error":"reload gagal"}', 503)
                    : http.Response(
                        jsonEncode({
                          'goals': [definition]
                        }),
                        200);
              final body = jsonDecode(r.body) as Map<String, dynamic>;
              if (r.method == 'PATCH') {
                edited = true;
                definition.addAll(body);
                return http.Response(jsonEncode({'goal': definition}), 200);
              }
              posted = body;
              if ((body['completed_step_ids'] as List).contains('a'))
                return http.Response('{"error":"unknown step a"}', 422);
              return http.Response(
                  jsonEncode({
                    'log': {
                      'id': 'l',
                      'goal_id': 'g',
                      'logged_on': body['logged_on'],
                      'done': true,
                      'completed_step_ids': body['completed_step_ids']
                    }
                  }),
                  200);
            })))
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
      if (historical) {
        await tapGoalControl(
            tester, find.byIcon(Icons.calendar_today_outlined));
        await tester.tap(find.byTooltip('Switch to input'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField),
            '${yesterday.month}/${yesterday.day}/${yesterday.year}');
        await tester.tap(find.text('OK'));
        await tester.pumpAndSettle();
      }
      await tapGoalControl(tester, find.byTooltip('Edit goal'));
      await tapGoalControl(tester, find.byTooltip('Hapus langkah Langkah A'));
      await tapGoalControl(tester, find.text('Simpan Perubahan'));
      expect(find.text('Langkah A'), findsNothing);
      if (historical) {
        expect(
            find.text('Riwayat mingguan belum dapat dimuat'), findsOneWidget);
        await tapGoalControl(tester, find.byType(Checkbox));
      } else {
        await tapGoalControl(tester, find.text('Langkah B'));
      }
      expect(posted?['completed_step_ids'], ['b']);
      expect(posted?['logged_on'],
          historical ? wibDateKey(yesterday) : wibDateKey(wibNow()));
      expect(find.text('1/1 selesai'), findsOneWidget);
    });
  }
  testWidgets('historical progress survives edit and failed reload',
      (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    tester.view.physicalSize = const Size(390, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final yesterday = wibNow().subtract(const Duration(days: 1));
    final historicalDate = wibDateKey(yesterday);
    var edited = false;
    final goal = <String, dynamic>{
      'id': 'g',
      'title': 'Baca',
      'category': 'general',
      'target_per_week': 7,
      'is_active': true,
      'details': {
        'method': 'numeric',
        'start_date': '2026-01-01',
        'target': 20,
        'unit': 'halaman'
      },
      'today_value': 2,
      'done_today': false,
      'is_due': true,
    };
    final container = ProviderContainer(overrides: [
      apiClientProvider.overrideWithValue(MalvaApiClient(
        baseUrl: 'https://goals.test',
        httpClient: MockClient((r) async {
          if (r.method == 'GET') {
            if (edited) return http.Response('{"error":"reload gagal"}', 503);
            return http.Response(
                jsonEncode({
                  'goals': [
                    {
                      ...goal,
                      if (r.url.queryParameters['on'] == historicalDate)
                        'today_value': 14,
                    }
                  ]
                }),
                200);
          }
          edited = true;
          return http.Response(
              jsonEncode({
                'goal': {...goal, ...jsonDecode(r.body) as Map<String, dynamic>}
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
        child:
            MaterialApp(theme: buildMalvaTheme(), home: const GoalsScreen())));
    await tester.pumpAndSettle();
    await tapGoalControl(tester, find.byIcon(Icons.calendar_today_outlined));
    await tester.tap(find.byTooltip('Switch to input'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField),
        '${yesterday.month}/${yesterday.day}/${yesterday.year}');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.text('Progres: 14 / 20 halaman', findRichText: true),
        findsOneWidget);
    await tapGoalControl(tester, find.byTooltip('Edit goal'));
    await tester.enterText(find.byKey(const Key('goal-title')), 'Baca baru');
    await tapGoalControl(tester, find.text('Simpan Perubahan'));
    expect(find.text('Baca baru'), findsOneWidget);
    expect(find.text('Progres: 14 / 20 halaman', findRichText: true),
        findsOneWidget);
  });
  for (final numeric in [true, false]) {
    testWidgets(
        '${numeric ? 'numeric' : 'checklist'} accepted progress survives reload failure',
        (tester) async {
      FlutterSecureStorage.setMockInitialValues({});
      tester.view.physicalSize = const Size(390, 950);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      var posted = false;
      final goal = <String, dynamic>{
        'id': 'g',
        'title': 'Baca',
        'category': 'general',
        'target_per_week': 7,
        'is_active': true,
        'details': {
          'method': numeric ? 'numeric' : 'checklist',
          'start_date': '2026-11-01',
          'target': 20,
          'unit': 'halaman',
          'steps': [
            {'id': 's1', 'label': 'Siapkan buku'},
            {'id': 's2', 'label': 'Baca buku'}
          ]
        },
        'today_value': 14,
        'today_completed_step_ids': <String>[],
        'done_today': false,
        'is_due': true
      };
      final container = ProviderContainer(overrides: [
        apiClientProvider.overrideWithValue(MalvaApiClient(
            baseUrl: 'https://goals.test',
            httpClient: MockClient((r) async {
              if (r.method == 'GET' && r.url.path == '/v1/habit-logs') {
                return http.Response('{"logs":[]}', 200);
              }
              if (r.method == 'GET')
                return posted
                    ? http.Response('{"error":"reload gagal"}', 503)
                    : http.Response(
                        jsonEncode({
                          'goals': [goal]
                        }),
                        200);
              final body = jsonDecode(r.body) as Map<String, dynamic>;
              expect(body['goal_id'], 'g');
              if (numeric) {
                expect(body['value'], 15);
                expect(body.containsKey('completed_step_ids'), isFalse);
              } else {
                expect(body['completed_step_ids'], ['s1']);
                expect(body.containsKey('value'), isFalse);
              }
              posted = true;
              return http.Response(
                  jsonEncode({
                    'log': {
                      'id': 'l',
                      'goal_id': 'g',
                      'logged_on': body['logged_on'],
                      'done': false,
                      'value': numeric ? 15 : 14,
                      'completed_step_ids': numeric ? [] : ['s1']
                    }
                  }),
                  200);
            })))
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
      await tapGoalControl(
          tester,
          numeric
              ? find.byTooltip('Tambah progres Baca')
              : find.text('Siapkan buku'));
      expect(
          find.text(numeric ? 'Progres: 15 / 20 halaman' : '1/2 selesai',
              findRichText: true),
          findsOneWidget);
      expect(posted, isTrue);
    });
  }
  testWidgets(
      'numeric editor persists target note steps and tracking on the server',
      (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final goals = <Map<String, dynamic>>[];
    Map<String, dynamic>? saved;
    final container = ProviderContainer(overrides: [
      apiClientProvider.overrideWithValue(MalvaApiClient(
          baseUrl: 'https://goals.test',
          httpClient: MockClient((r) async {
            if (r.method == 'GET')
              return http.Response(jsonEncode({'goals': goals}), 200);
            saved = jsonDecode(r.body) as Map<String, dynamic>;
            final goal = {...saved!, 'id': 'g', 'is_active': true};
            goals.add(goal);
            return http.Response(jsonEncode({'goal': goal}), 201);
          })))
    ]);
    addTearDown(container.dispose);
    container.read(authStateProvider.notifier).setSession(const AuthSession(
        role: UserRole.patient,
        identifier: 'p',
        displayName: 'Pasien',
        accessToken: 't'));
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child:
            MaterialApp(theme: buildMalvaTheme(), home: const GoalsScreen())));
    await tester.pumpAndSettle();
    await tapGoalControl(tester, find.text('Baru'));
    await tester.enterText(find.byKey(const Key('goal-title')), 'Baca buku');
    await tester.enterText(
        find.byKey(const Key('goal-note')), 'Fokus sebelum tidur');
    await tapGoalControl(tester, find.byKey(const Key('goal-method-numeric')));
    await tester.enterText(find.byKey(const Key('goal-target')), '20');
    await tester.enterText(find.byKey(const Key('goal-unit')), 'halaman');
    await tester.enterText(
        find.byKey(const Key('goal-new-step')), 'Siapkan buku');
    await tapGoalControl(tester, find.text('Tambah Langkah'));
    await tapGoalControl(tester, find.byKey(const Key('goal-lock-past')));
    await tapGoalControl(tester, find.text('Simpan Target'));
    expect(find.text('Baca buku'), findsOneWidget);
    final details = saved!['details'] as Map<String, dynamic>;
    expect(details['target'], 20);
    expect(details['unit'], 'halaman');
    expect(details['method'], 'numeric');
    expect(details['note'], 'Fokus sebelum tidur');
    expect((details['steps'] as List).single['label'], 'Siapkan buku');
    expect(details['lock_past'], isTrue);
  });
}
