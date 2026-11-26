import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:malva_mental_health/features/diagnosis/icd10_service.dart';
import 'package:malva_mental_health/src/models.dart';
import 'package:malva_mental_health/src/screens/pro_patient_detail_screen.dart';
import 'package:malva_mental_health/src/services/malva_api_client.dart';
import 'package:malva_mental_health/src/theme.dart';
import 'package:malva_mental_health/src/time/wib.dart';

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
          'answers': [
            for (var i = 0; i < 9; i++)
              {
                'question_id': [
                  'phq_interest',
                  'phq_low_mood',
                  'phq_sleep',
                  'phq_energy',
                  'phq_appetite',
                  'phq_self_worth',
                  'phq_focus',
                  'phq_motor',
                  'phq_self_harm'
                ][i],
                'position': i + 1,
                'score': i == 2 ? 2 : 0
              }
          ],
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
  bool psychiatrist = false;
  bool verified = false;
  String diagnosis = 'Diagnosis tersimpan';
  final diagnosisWrites = <String>[];
  final statusByPath = <String, int>{};
  bool missingGad = false;
  final requested = <String>[];
  final consent = <String, bool>{
    'share_screenings': true,
    'share_mood_diary': true,
    'share_medications': true,
    'share_health_record': true,
    'share_therapy_records': true,
    'share_goals': true,
  };
  final packages = <Map<String, dynamic>>[];
  final sessions = <Map<String, dynamic>>[];
  final extraWorksheets = <Map<String, dynamic>>[];
  final allergies = <Map<String, dynamic>>[];

  late final api = MalvaApiClient(
    baseUrl: 'http://backend.test',
    httpClient: MockClient((request) async {
      final path = request.url.path;
      requested.add(path);
      if (path == '/v1/health-record' && request.method == 'PUT') {
        final data = jsonDecode(request.body) as Map<String, dynamic>;
        expect(data['patient_id'], 'patient');
        diagnosis = data['diagnosis_summary'] as String;
        diagnosisWrites.add(diagnosis);
      }
      final status = statusByPath[path] ?? 200;
      if (status != 200) {
        return http.Response(
            jsonEncode({'error': 'Data tidak dibagikan'}), status);
      }
      final body = switch (path) {
        '/v1/care-packages' => {'packages': packages},
        '/v1/care-sessions' => {'sessions': sessions},
        '/v1/screenings' => {
            'screenings': [_screening(missingGad: missingGad)]
          },
        '/v1/therapy-submissions' => {
            'submissions': [
              _worksheet('who5', 'WHO-5 dibagikan'),
              _worksheet('dass21', 'DASS-21 dibagikan'),
              _worksheet('abcde', 'Latihan ABCDE'),
              ...extraWorksheets,
            ],
          },
        '/v1/goals' => {'goals': []},
        '/v1/health-record/access' => {'consent': consent},
        '/v1/diary-entries' => {'diaries': []},
        '/v1/professional-notes' => {'notes': []},
        '/v1/medications' => {'medications': []},
        '/v1/medication-logs' => {'medication_logs': []},
        '/v1/health-record/allergies' => {'items': allergies},
        '/v1/timeline' => {'events': []},
        '/v1/messages' => {'messages': []},
        '/v1/health-record' => {
            'health_record': {'diagnosis_summary': diagnosis},
          },
        '/v1/credentials/me' => {
            'credential': psychiatrist || verified
                ? {
                    'specialization': psychiatrist ? 'Sp.KJ' : 'M.Psi',
                    'verification_status': 'VERIFIED',
                  }
                : null
          },
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
  TestWidgetsFlutterBinding.ensureInitialized();
  // The production asset is decoded in an isolate outside the fake clock.
  setUpAll(() async => Icd10Service().load());

  testWidgets('unused valid package opens ICD-10 selection in Isi diagnosis',
      (tester) async {
    final now = wibNow();
    final responses = _Responses()
      ..verified = true
      ..packages.add({
        'id': 'unused',
        'patient_id': 'patient',
        'professional_id': 'professional',
        'total_sessions': 4,
        'used_sessions': 0,
        'remaining_sessions': 4,
        'status': 'active',
        'starts_at': wibIso(now.subtract(const Duration(days: 1))),
        'expires_at': wibIso(now.add(const Duration(days: 42))),
      });
    await _pump(tester, responses);
    await tester.tap(find.text('Isi diagnosis'));
    await tester.pumpAndSettle();
    final dialog = find.byType(AlertDialog);
    expect(dialog, findsOneWidget);
    final search =
        find.descendant(of: dialog, matching: find.byType(TextField));
    await tester.enterText(search, 'F411');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Generalized anxiety disorder'));
    await tester.pumpAndSettle();
    await tester.enterText(search, 'F431');
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Post-traumatic stress disorder'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Simpan Diagnosis'));
    await tester.pumpAndSettle();
    expect(responses.diagnosisWrites, [
      'F41.1 - Generalized anxiety disorder\nF43.1 - Post-traumatic stress disorder',
    ]);
    await tester.tap(find.text('Isi diagnosis'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Primary'), findsOneWidget);
    expect(find.textContaining('Secondary'), findsOneWidget);
  });

  for (final offset in [-90, -10, 90]) {
    testWidgets('single-session diagnosis availability at start offset $offset',
        (tester) async {
      final responses = _Responses()
        ..verified = true
        ..sessions.add({
          'id': 'single',
          'patient_id': 'patient',
          'professional_id': 'professional',
          'scheduled_at': wibIso(wibNow().add(Duration(minutes: offset))),
          'status': 'scheduled',
          'session_type': 'video',
          'duration_minutes': 60,
        });
      await _pump(tester, responses);
      final button = tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Isi diagnosis'));
      if (offset == -10) {
        expect(button.onPressed, isNotNull);
      } else {
        expect(button.onPressed, isNull);
      }
    });
  }

  testWidgets('prescribe from patient detail opens the new medicine wizard',
      (tester) async {
    final responses = _Responses()..psychiatrist = true;
    await _pump(tester, responses);
    await tester.tap(find.text('Resepkan obat'));
    await tester.pumpAndSettle();
    expect(find.text('Detail Obat'), findsWidgets);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Pasien'), findsWidgets);
    expect(find.text('Lanjut Atur Jadwal Resep'), findsOneWidget);
  });
  testWidgets(
      'package sessions remain grouped with real progress and no-show date',
      (tester) async {
    final responses = _Responses()
      ..packages.addAll([
        {
          'id': 'package-a',
          'total_sessions': 4,
          'remaining_sessions': 3,
          'used_sessions': 1,
          'validity_days': 42,
          'status': 'active'
        },
        {
          'id': 'package-b',
          'total_sessions': 8,
          'remaining_sessions': 6,
          'used_sessions': 2,
          'validity_days': 42,
          'status': 'active'
        },
      ])
      ..sessions.addAll([
        {
          'id': 'a',
          'package_id': 'package-a',
          'session_type': 'video',
          'scheduled_at': '2026-11-12T15:00:00+07:00',
          'status': 'scheduled'
        },
        {
          'id': 'b',
          'package_id': 'package-b',
          'session_type': 'video',
          'scheduled_at': '2026-10-24T09:00:00+07:00',
          'status': 'no_show'
        },
      ]);
    await _pump(tester, responses);
    expect(find.text('Paket & Sesi Konsultasi'), findsOneWidget);
    expect(find.textContaining('3/4 sesi tersisa'), findsOneWidget);
    expect(find.text('12 Nov 2026'), findsNothing);
    expect(find.text('24 Okt 2026'), findsNothing);
    expect(find.text('09:00 WIB'), findsNothing);
  });

  testWidgets(
      'daily monitoring omits removed patient shares and timeline requests',
      (tester) async {
    final responses = _Responses();
    await _pump(tester, responses);
    expect(responses.requested, isNot(contains('/v1/timeline')));
    expect(responses.requested, isNot(contains('/v1/messages')));
    expect(responses.requested, isNot(contains('/v1/diary-entries')));
    expect(responses.requested, isNot(contains('/v1/professional-notes')));
    expect(find.text('Catatan sesi'), findsNothing);
    expect(find.text('Tulis catatan sesi'), findsNothing);
    expect(find.byKey(const ValueKey('shares-section')), findsNothing);
    expect(find.byKey(const ValueKey('timeline-section')), findsNothing);
  });

  testWidgets(
      'screening omits symptom summary and retains recorded answer details',
      (tester) async {
    await _pump(tester, _Responses());
    await tester.tap(find.text('Lihat hasil').first);
    await tester.pumpAndSettle();
    expect(find.text('Gejala teridentifikasi'), findsNothing);
    expect(find.text('Pola tidur terganggu'), findsNothing);
    expect(find.text('Risiko menyakiti diri'), findsNothing);
    await tester.tap(find.text('Lihat detail jawaban').first);
    await tester.pumpAndSettle();
    expect(find.text('Pola tidur terganggu'), findsOneWidget);
    expect(find.textContaining('Lebih dari separuh hari'), findsWidgets);
  });
  testWidgets(
      'clinical access summary uses eligibility flags, not record counts',
      (tester) async {
    final responses = _Responses()..consent['share_goals'] = false;
    await _pump(tester, responses);
    expect(find.text('Pemantauan harian'), findsNothing);
    expect(responses.requested, isNot(contains('/v1/mood-checkins')));
    expect(responses.requested, isNot(contains('/v1/goals')));
    expect(find.text('5 dari 6 kategori dibagikan'), findsOneWidget);
    expect(find.text('Akses Sebagian'), findsOneWidget);
    responses.consent['share_goals'] = true;
    await tester.tap(find.byTooltip('Muat ulang'));
    await tester.pumpAndSettle();
    expect(find.text('6 dari 6 kategori dibagikan'), findsOneWidget);
    expect(find.text('Akses Penuh'), findsOneWidget);
  });

  testWidgets(
      'clinical assessment filters keep PHQ GAD combined and show more dated retakes',
      (tester) async {
    final responses = _Responses();
    for (var i = 1; i <= 6; i++) {
      responses.extraWorksheets.add({
        ..._worksheet('who5', 'WHO retake $i'),
        'id': 'retake-$i',
        'created_at': '2026-11-08T0$i:00:00+07:00'
      });
    }
    await _pump(tester, responses);
    expect(find.text('WHO retake 1'), findsNothing);
    expect(find.text('Tunjukkan Lebih (6 lagi)'), findsOneWidget);
    expect(find.text('WHO retake 3'), findsOneWidget);
    expect(find.text('WHO retake 2'), findsNothing);
    await tester.tap(find.text('Tunjukkan Lebih (6 lagi)'));
    await tester.pumpAndSettle();
    expect(find.text('WHO retake 1'), findsOneWidget);
    expect(find.text('Asesmen • 08/11/2026 01:00'), findsOneWidget);
    expect(find.text('Tunjukkan Lebih (1 lagi)'), findsOneWidget);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Terapi'));
    await tester.pumpAndSettle();
    expect(find.text('WHO retake 1'), findsNothing);
    expect(find.text('Skrining PHQ-9 + GAD-7'), findsNothing);
    expect(find.text('Latihan ABCDE'), findsOneWidget);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Asesmen'));
    await tester.enterText(find.byType(TextField), 'DASS');
    await tester.pumpAndSettle();
    expect(find.text('DASS-21 dibagikan'), findsOneWidget);
    expect(find.text('WHO retake 6'), findsNothing);
  });
  testWidgets(
      'groups clinical data and keeps CF without raw traces or technical prose',
      (tester) async {
    await _pump(tester, _Responses());
    final health = find.text('Diagnosis Klinis (ICD-10)');

    final screening = find.text('Arsip Klinis & Skrining');
    expect(find.text('Catatan sesi'), findsNothing);
    expect(health, findsOneWidget);
    expect(screening, findsOneWidget);
    expect(tester.getTopLeft(health).dy,
        lessThan(tester.getTopLeft(screening).dy));
    expect(find.text('WHO-5 dibagikan'), findsOneWidget);
    expect(find.text('DASS-21 dibagikan'), findsOneWidget);
    expect(find.text('Latihan ABCDE'), findsOneWidget);
    expect(find.text('Hasil DASS-21 / WHO-5 & tren'), findsNothing);
    await tester.tap(find.text('Lihat hasil').first);
    await tester.pumpAndSettle();
    expect(find.text('Rincian Hasil'), findsOneWidget);
    expect(find.text('Skor Total PHQ-9'), findsOneWidget);
    expect(find.text('Skor Total GAD-7'), findsOneWidget);
    expect(find.text('PHQ-9 · Dukungan aturan internal (CF)'), findsOneWidget);
    expect(find.text('GAD-7 · Dukungan aturan internal (CF)'), findsOneWidget);
    expect(find.textContaining('0.68', findRichText: true), findsNWidgets(2));
    expect(find.text('PHQ9_MILD: 0.72 × 0.95 = 0.684'), findsNothing);
    expect(find.textContaining('bukan probabilitas diagnosis'), findsNothing);
    expect(find.text('Gejala teridentifikasi'), findsNothing);
    expect(find.text('Pola tidur terganggu'), findsNothing);
    expect(find.text('Indikator klinis'), findsNWidgets(2));
    await tester.tap(find.text('Lihat detail jawaban').first);
    await tester.pumpAndSettle();
    expect(find.text('Pola tidur terganggu'), findsOneWidget);
    expect(find.textContaining('2 • Lebih dari separuh hari'), findsOneWidget);
  });

  testWidgets('failed clinical section stays unavailable until retry succeeds',
      (tester) async {
    final responses = _Responses()
      ..statusByPath['/v1/screenings'] = 500
      ..statusByPath['/v1/health-record/access'] = 500
      ..statusByPath['/v1/health-record'] = 500;
    await _pump(tester, responses);
    expect(find.text('WHO-5 dibagikan'), findsOneWidget);
    expect(find.text('Skrining PHQ-9 / GAD-7 belum dapat dimuat.'),
        findsOneWidget);
    expect(find.text('Status izin pasien belum dapat dimuat.'), findsOneWidget);
    expect(find.text('Rekam Medis belum dapat dimuat.'), findsOneWidget);
    expect(find.textContaining('Sebagian data gagal dimuat'), findsNothing);
    expect(find.text('Belum ada skrining'), findsNothing);
    expect(find.text('Belum ada data / tidak dibagikan'), findsNothing);
    responses.statusByPath.clear();
    await tester.tap(find.byTooltip('Muat ulang'));
    await tester.pumpAndSettle();
    expect(find.text('PHQ-9 7/27 (Ringan)'), findsOneWidget);
    expect(find.text('Diagnosis tersimpan'), findsOneWidget);
    expect(find.text('Status izin pasien belum dapat dimuat.'), findsNothing);
  });

  testWidgets(
      'package expiry clears diagnosis and allergies for unverified professional',
      (tester) async {
    final now = wibNow();
    final responses = _Responses()
      ..packages.add({
        'id': 'active',
        'patient_id': 'patient',
        'professional_id': 'professional',
        'total_sessions': 1,
        'status': 'active',
        'starts_at': wibIso(now.subtract(const Duration(days: 1))),
        'expires_at': wibIso(now.add(const Duration(seconds: 5))),
      })
      ..allergies.add({
        'id': 'a1',
        'reaction_type': 'allergy',
        'substance': 'Ibuprofen',
        'symptoms': 'Ruam',
        'severity': 'high',
        'reported_by': 'patient',
      });
    await _pump(tester, responses);
    expect(find.text('Ibuprofen'), findsOneWidget);
    expect(find.text('Diagnosis tersimpan'), findsOneWidget);
    responses.statusByPath['/v1/health-record'] = 403;
    responses.statusByPath['/v1/health-record/allergies'] = 403;
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
    expect(find.text('Ibuprofen'), findsNothing);
    expect(find.text('Diagnosis tersimpan'), findsNothing);
    expect(find.text('Alergi & Reaksi Obat tidak dibagikan pasien.'),
        findsOneWidget);
    expect(responses.requested.where((path) => path == '/v1/care-sessions'),
        hasLength(1));
  });

  testWidgets('unshared screening does not hide other consented data',
      (tester) async {
    final responses = _Responses()..statusByPath['/v1/screenings'] = 403;
    await _pump(tester, responses);
    expect(find.text('Skrining PHQ-9 / GAD-7 tidak dibagikan pasien.'),
        findsOneWidget);
    expect(find.text('WHO-5 dibagikan'), findsOneWidget);
    expect(find.text('Diagnosis tersimpan'), findsOneWidget);
    expect(find.text('Belum ada skrining'), findsNothing);
  });

  testWidgets('missing instrument never appears as a normal zero score',
      (tester) async {
    await _pump(tester, _Responses()..missingGad = true);
    expect(find.textContaining('GAD-7 0'), findsNothing);
    await tester.tap(find.text('Lihat hasil').first);
    await tester.pumpAndSettle();
    expect(find.text('GAD-7: hasil belum tersedia.'), findsOneWidget);
    expect(find.text('GAD-7: 0/0'), findsNothing);
  });
}
