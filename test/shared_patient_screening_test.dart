import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:malva_mental_health/src/models.dart';
import 'package:malva_mental_health/src/providers/auth_providers.dart';
import 'package:malva_mental_health/src/screens/portal/shared_patient_data_screen.dart';
import 'package:malva_mental_health/src/services/malva_api_client.dart';
import 'package:malva_mental_health/src/theme.dart';
import 'package:malva_mental_health/src/widgets/therapy_library.dart';

const _session = AuthSession(
    role: UserRole.professional,
    identifier: 'professional',
    displayName: 'Profesional',
    backendUserId: 'pro',
    accessToken: 'token');

Map<String, dynamic> _submission(String patient, String module) => {
      'id': '$patient-$module',
      'patient_id': patient,
      'module_id': module,
      'title': '${patient == 'p1' ? 'Ami' : 'Dina'} ${switch (module) {
        'who5' => 'WHO-5',
        'dass21' => 'DASS-21',
        'abcde' => 'Latihan ABCDE',
        _ => 'Latihan lama',
      }}',
      'answers': module == 'who5' || module == 'dass21'
          ? {
              'scale_version': 2,
              for (var i = 1; i <= (module == 'who5' ? 5 : 21); i++) 'q$i': 2,
            }
          : {'activating': 'Jawaban latihan'},
      'summary': '',
      'created_at': '2026-11-10T08:00:00+07:00',
      'shared_with_professional_id': 'pro',
      'shared_at': '2026-11-10T08:10:00+07:00',
    };

Map<String, dynamic> _screening(String patient) => {
      'id': '$patient-screening',
      'patient_id': patient,
      'overall_level': 'mild',
      'crisis_flag': false,
      'created_at': '2026-11-10T09:00:00+07:00',
      'bundle': {
        'phq9': {
          'type': 'phq9',
          'score': 7,
          'max_score': 27,
          'level': 'mild',
          'summary': 'Gejala depresi ringan.',
          'cf': 0.684,
          'crisis_flag': false,
        },
        'gad7': {
          'type': 'gad7',
          'score': 6,
          'max_score': 21,
          'level': 'mild',
          'summary': 'Gejala kecemasan ringan.',
          'cf': 0.684,
          'crisis_flag': false,
        },
      },
    };

class _Fixture {
  final status = <String, int>{};
  Completer<http.Response>? delayedFirstPatient;
  late final api = MalvaApiClient(
      baseUrl: 'https://backend.test',
      httpClient: MockClient((r) async {
        final path = r.url.path;
        final patient = r.url.queryParameters['patient_id'];
        if (status.containsKey(path)) {
          return http.Response(
              jsonEncode({'error': 'Tidak dibagikan'}), status[path]!);
        }
        if (path == '/v1/therapy-submissions' &&
            patient == 'p1' &&
            delayedFirstPatient != null) return delayedFirstPatient!.future;
        final body = switch (path) {
          '/v1/patient-professional-links' => {
              'links': [
                for (final p in ['p1', 'p2'])
                  {
                    'patient_id': p,
                    'patient_display_name': p == 'p1' ? 'Ami' : 'Dina',
                    'professional_id': 'pro',
                    'status': 'active'
                  }
              ]
            },
          '/v1/therapy-submissions' => {
              'submissions': [
                for (final p in ['p1', 'p2'])
                  if (patient == null || patient == p)
                    for (final module in ['who5', 'dass21', 'abcde', 'legacy'])
                      _submission(p, module),
              ]
            },
          '/v1/screenings' => {
              'screenings': [_screening(patient!)]
            },
          '/v1/mood-checkins' => {'moods': []},
          _ => throw StateError('Unexpected endpoint $path'),
        };
        return http.Response(jsonEncode(body), 200);
      }));
}

Future<ProviderContainer> _pump(WidgetTester tester, _Fixture fixture) async {
  tester.view.physicalSize = const Size(393, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final container = ProviderContainer();
  addTearDown(container.dispose);
  container.read(authStateProvider.notifier).setSession(_session);
  await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
          theme: buildMalvaTheme(),
          home: SharedPatientDataScreen(
              session: _session, apiClient: fixture.api))));
  await tester.pumpAndSettle();
  return container;
}

Future<void> _openTab(WidgetTester tester, String title) async {
  final tab = find.widgetWithText(Tab, title);
  expect(tab, findsOneWidget);
  await tester.ensureVisible(tab);
  await tester.tap(tab);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
      'therapy excludes assessments and keeps unknown legacy worksheets',
      (tester) async {
    await _pump(tester, _Fixture());
    await _openTab(tester, 'Terapi');
    expect(find.text('Ami WHO-5'), findsNothing);
    expect(find.text('Ami DASS-21'), findsNothing);
    expect(find.text('Ami Latihan ABCDE'), findsOneWidget);
    expect(find.text('Ami Latihan lama'), findsOneWidget);
  });

  testWidgets(
      'selected patient screening includes both sources and opens actual CF details',
      (tester) async {
    final owner = await _pump(tester, _Fixture());
    await _openTab(tester, 'Screening');
    expect(find.text('Ami WHO-5'), findsOneWidget);
    expect(find.text('Ami DASS-21'), findsOneWidget);
    expect(find.text('Dina WHO-5'), findsNothing);
    expect(find.text('Ami Latihan ABCDE'), findsNothing);
    expect(find.text('Screening PHQ-9 + GAD-7'), findsOneWidget);
    await tester.tap(find.text('Screening PHQ-9 + GAD-7'));
    await tester.pumpAndSettle();
    expect(find.text('PHQ-9 Total Score'), findsOneWidget);
    expect(find.text('GAD-7 Total Score'), findsOneWidget);
    expect(find.text('PHQ-9 · Dukungan rule internal (CF)'), findsOneWidget);
    expect(find.text('GAD-7 · Dukungan rule internal (CF)'), findsOneWidget);
    expect(find.text('Bagikan ke Profesional'), findsNothing);
    owner.read(authStateProvider.notifier).clearSession();
    await tester.pumpAndSettle();
    expect(find.text('PHQ-9 Total Score'), findsNothing);
  });

  for (final deniedSource in ['/v1/screenings', '/v1/therapy-submissions']) {
    testWidgets(
        'screening keeps consented source when $deniedSource is forbidden',
        (tester) async {
      final fixture = _Fixture()..status[deniedSource] = 403;
      await _pump(tester, fixture);
      await _openTab(tester, 'Screening');
      if (deniedSource == '/v1/screenings') {
        expect(find.text('Ami WHO-5'), findsOneWidget);
        await tester.tap(find.text('Ami WHO-5'));
        await tester.pumpAndSettle();
        expect(find.byType(AssessmentResultCard), findsOneWidget);
      } else {
        expect(find.text('Screening PHQ-9 + GAD-7'), findsOneWidget);
        expect(find.text('Ami WHO-5'), findsNothing);
      }
      expect(find.textContaining('Gagal membuka'), findsNothing);
    });
  }

  testWidgets('switching patient discards an old delayed screening load',
      (tester) async {
    final fixture = _Fixture()
      ..delayedFirstPatient = Completer<http.Response>();
    await _pump(tester, fixture);
    final tab = find.widgetWithText(Tab, 'Screening');
    expect(tab, findsOneWidget);
    await tester.ensureVisible(tab);
    await tester.tap(tab);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Dina').last);
    await tester.pumpAndSettle();
    expect(find.text('Dina WHO-5'), findsOneWidget);
    fixture.delayedFirstPatient!.complete(http.Response(
        jsonEncode({
          'submissions': [_submission('p1', 'who5')]
        }),
        200));
    await tester.pumpAndSettle();
    expect(find.text('Dina WHO-5'), findsOneWidget);
    expect(find.text('Ami WHO-5'), findsNothing);
  });
}
