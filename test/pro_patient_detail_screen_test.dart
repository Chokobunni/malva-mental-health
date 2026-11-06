import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:malva_mental_health/src/models.dart';
import 'package:malva_mental_health/src/screens/pro_patient_detail_screen.dart';
import 'package:malva_mental_health/src/services/malva_api_client.dart';
import 'package:malva_mental_health/src/theme.dart';

const _session = AuthSession(
  role: UserRole.professional,
  identifier: 'professional',
  displayName: 'Profesional',
  backendUserId: 'professional',
  accessToken: 'test-token',
);

Map<String, dynamic> _screening({bool missingGad = false}) => {
      'id': 'screening-1',
      'patient_id': 'patient',
      'overall_level': 'Ringan',
      'crisis_flag': false,
      'created_at': '2026-11-07T09:00:00+07:00',
      'bundle': {
        'phq9': {
          'type': 'phq9',
          'score': 7,
          'max_score': 27,
          'level': 'Ringan',
          'summary': 'Gejala depresi ringan.',
          'crisis_flag': false,
          'cf': 0.684,
          'rule_trace': 'PHQ9_MILD: 0.72 × 0.95 = 0.684',
        },
        if (!missingGad)
          'gad7': {
            'type': 'gad7',
            'score': 6,
            'max_score': 21,
            'level': 'Ringan',
            'summary': 'Gejala kecemasan ringan.',
            'crisis_flag': false,
            'cf': 0.684,
            'rule_trace': 'GAD7_MILD: 0.72 × 0.95 = 0.684',
          },
      },
    };

Map<String, dynamic> _worksheet(String id, String title) => {
      'id': id,
      'module_id': id,
      'title': title,
      'answers': {
        'scale_version': 2,
        for (var i = 1; i <= (id == 'dass21' ? 21 : 5); i++) 'q$i': 2,
      },
      'summary': '',
      'shared_with_professional_id': 'professional',
      'shared_at': '2026-11-07T09:00:00+07:00',
      'created_at': '2026-11-07T09:00:00+07:00',
    };

class _Responses {
  final statusByPath = <String, int>{};
  bool missingGad = false;

  late final api = MalvaApiClient(
    baseUrl: 'http://backend.test',
    httpClient: MockClient((request) async {
      final path = request.url.path;
      final status = statusByPath[path] ?? 200;
      if (status != 200) {
        return http.Response(
            jsonEncode({'error': 'Data tidak dibagikan'}), status);
      }
      final body = switch (path) {
        '/v1/care-packages' => {'packages': []},
        '/v1/care-sessions' => {'sessions': []},
        '/v1/screenings' => {
            'screenings': [_screening(missingGad: missingGad)]
          },
        '/v1/therapy-submissions' => {
            'submissions': [
              _worksheet('who5', 'WHO-5 dibagikan'),
              _worksheet('dass21', 'DASS-21 dibagikan'),
              _worksheet('abcde', 'Latihan ABCDE'),
            ],
          },
        '/v1/goals' => {'goals': []},
        '/v1/mood-checkins' => {'moods': []},
        '/v1/diary-entries' => {'diaries': []},
        '/v1/professional-notes' => {'notes': []},
        '/v1/medications' => {'medications': []},
        '/v1/timeline' => {'events': []},
        '/v1/messages' => {'messages': []},
        '/v1/health-record' => {
            'health_record': {'diagnosis_summary': 'Diagnosis tersimpan'},
          },
        '/v1/credentials/me' => {'credential': null},
        _ => throw StateError('Unexpected request $path'),
      };
      return http.Response(jsonEncode(body), 200);
    }),
  );
}

Future<void> _pump(WidgetTester tester, _Responses responses) async {
  tester.view.physicalSize = const Size(1200, 12000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ProviderScope(
    child: MaterialApp(
      theme: buildMalvaTheme(),
      home: ProPatientDetailScreen(
        patientId: 'patient',
        patientName: 'Pasien',
        session: _session,
        apiClient: responses.api,
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('groups clinical data and shows real PHQ/GAD CF and rule trace',
      (tester) async {
    await _pump(tester, _Responses());
    final health = find.text('Health Record & Obat');
    final daily = find.text('Pemantauan harian');
    final screening = find.text('Screening WHO-5, GAD-7, PHQ-9, DASS-21');
    final notes = find.text('Catatan sesi');
    expect(health, findsOneWidget);
    expect(screening, findsOneWidget);
    expect(tester.getTopLeft(health).dy, lessThan(tester.getTopLeft(daily).dy));
    expect(
        tester.getTopLeft(daily).dy, lessThan(tester.getTopLeft(screening).dy));
    expect(
        tester.getTopLeft(screening).dy, lessThan(tester.getTopLeft(notes).dy));
    expect(find.text('WHO-5 dibagikan'), findsOneWidget);
    expect(find.text('DASS-21 dibagikan'), findsOneWidget);
    expect(find.text('Latihan ABCDE'), findsOneWidget);
    expect(find.text('Hasil DASS-21 / WHO-5 & tren'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('screening-screening-1')));
    await tester.pumpAndSettle();
    expect(find.text('PHQ-9: 7/27'), findsOneWidget);
    expect(find.text('GAD-7: 6/21'), findsOneWidget);
    expect(find.text('Dukungan aturan (CF): 68%'), findsNWidgets(2));
    expect(find.text('PHQ9_MILD: 0.72 × 0.95 = 0.684'), findsOneWidget);
    expect(find.textContaining('bukan probabilitas diagnosis'), findsWidgets);
  });

  testWidgets('failed clinical section stays unavailable until retry succeeds',
      (tester) async {
    final responses = _Responses()
      ..statusByPath['/v1/screenings'] = 500
      ..statusByPath['/v1/mood-checkins'] = 500
      ..statusByPath['/v1/health-record'] = 500;
    await _pump(tester, responses);
    expect(find.text('WHO-5 dibagikan'), findsOneWidget);
    expect(find.text('Screening PHQ-9 / GAD-7 belum dapat dimuat.'),
        findsOneWidget);
    expect(find.text('Mood belum dapat dimuat.'), findsOneWidget);
    expect(find.text('Health Record belum dapat dimuat.'), findsOneWidget);
    expect(find.textContaining('Sebagian data gagal dimuat'), findsNothing);
    expect(find.text('Belum ada screening'), findsNothing);
    expect(find.text('Belum ada data / tidak dibagikan'), findsNothing);
    responses.statusByPath.clear();
    await tester.tap(find.byTooltip('Muat ulang'));
    await tester.pumpAndSettle();
    expect(find.text('PHQ-9 7 • GAD-7 6'), findsOneWidget);
    expect(find.text('Diagnosis tersimpan'), findsOneWidget);
    expect(find.text('Mood belum dapat dimuat.'), findsNothing);
  });

  testWidgets('unshared screening does not hide other consented data',
      (tester) async {
    final responses = _Responses()..statusByPath['/v1/screenings'] = 403;
    await _pump(tester, responses);
    expect(find.text('Screening PHQ-9 / GAD-7 tidak dibagikan pasien.'),
        findsOneWidget);
    expect(find.text('WHO-5 dibagikan'), findsOneWidget);
    expect(find.text('Diagnosis tersimpan'), findsOneWidget);
    expect(find.text('Belum ada screening'), findsNothing);
  });

  testWidgets('missing instrument never appears as a normal zero score',
      (tester) async {
    await _pump(tester, _Responses()..missingGad = true);
    expect(find.textContaining('GAD-7 0'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('screening-screening-1')));
    await tester.pumpAndSettle();
    expect(find.text('GAD-7: hasil belum tersedia.'), findsOneWidget);
    expect(find.text('GAD-7: 0/0'), findsNothing);
  });
}
