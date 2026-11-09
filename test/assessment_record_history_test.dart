import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:malva_mental_health/src/models.dart';
import 'package:malva_mental_health/src/providers/auth_providers.dart';
import 'package:malva_mental_health/src/screens/assessment_history_screen.dart';
import 'package:malva_mental_health/src/screens/assessment_list_screen.dart';
import 'package:malva_mental_health/src/screens/assessment_screen.dart';
import 'package:malva_mental_health/src/services/malva_api_client.dart';
import 'package:malva_mental_health/src/theme.dart';
import 'package:malva_mental_health/src/widgets/therapy_library.dart';

// ============================================================
// ASSESSMENT RECORD — riwayat skrining & asesmen pasien.
//
// `AssessmentHistoryScreen` menggabungkan worksheet assessment
// (DASS-21/WHO-5) + screening PHQ-9/GAD-7, urut tanggal DESC, dan
// TIDAK menampilkan worksheet terapi. `AssessmentHistoryPreview`
// (halaman Assessment) memuat sendiri, menampilkan maksimal 3 entri
// + tombol "Lihat semua". Tap entri membuka bottom sheet detail
// lewat `showAssessmentHistoryDetail`.
// ============================================================

/// Sesi pasien uji.
const _session = AuthSession(
  role: UserRole.patient,
  identifier: 'pasien@malva.app',
  displayName: 'Pasien',
  backendUserId: 'user_pasien_1',
  accessToken: 'token_test',
);

/// Satu submission worksheet (bentuk parse `BackendTherapySubmission`).
Map<String, dynamic> _submission({
  required String id,
  required String moduleId,
  required String title,
  required String createdAt,
  String summary = '',
  Map<String, dynamic> answers = const {},
}) {
  return {
    'id': id,
    'module_id': moduleId,
    'title': title,
    'answers': answers,
    'summary': summary,
    'shared_with_professional_id': '',
    'shared_at': null,
    'created_at': createdAt,
  };
}

/// Jawaban WHO-5 lengkap (5 item, skala 0-5) + penanda versi skala.
Map<String, dynamic> _who5Answers() => const {
      'q1': 3,
      'q2': 3,
      'q3': 2,
      'q4': 4,
      'q5': 3,
      'scale_version': 2,
      'scale_min': 0,
      'scale_max': 5,
    };

/// Satu sesi screening (bentuk parse `BackendScreeningSession`).
Map<String, dynamic> _screening({
  String id = 'scr_1',
  String createdAt = '2026-10-22T10:00:00.000Z',
}) {
  return {
    'id': id,
    'patient_id': 'user_pasien_1',
    'overall_level': 'Sedang',
    'crisis_flag': false,
    'created_at': createdAt,
    'bundle': {
      'phq9': {
        'type': 'phq9',
        'score': 12,
        'max_score': 27,
        'level': 'Sedang',
        'summary': 'Gejala depresi sedang.',
        'crisis_flag': false,
        'cf': 0.8,
        'rule_trace': '',
      },
      'gad7': {
        'type': 'gad7',
        'score': 9,
        'max_score': 21,
        'level': 'Ringan',
        'summary': 'Gejala kecemasan ringan.',
        'crisis_flag': false,
        'cf': 0.7,
        'rule_trace': '',
      },
    },
  };
}

/// Klien API dengan stub worksheet + screening.
MalvaApiClient _api({
  required List<Map<String, dynamic>> submissions,
  required List<Map<String, dynamic>> screenings,
}) {
  return MalvaApiClient(
    baseUrl: 'http://backend.test',
    httpClient: _FakeClient((request) async {
      switch (request.url.path) {
        case '/v1/therapy-submissions':
          return http.Response(
            jsonEncode({'submissions': submissions}),
            200,
            headers: {'content-type': 'application/json'},
          );
        case '/v1/screenings':
          return http.Response(
            jsonEncode({'screenings': screenings}),
            200,
            headers: {'content-type': 'application/json'},
          );
        default:
          return http.Response(
            '{}',
            200,
            headers: {'content-type': 'application/json'},
          );
      }
    }),
  );
}

/// Bungkus layar dengan provider palsu (klien HTTP uji + sesi pasien).
Widget _buildApp(MalvaApiClient api, {required Widget home}) {
  return ProviderScope(
    overrides: [
      apiClientProvider.overrideWithValue(api),
      authStateProvider.overrideWith((ref) {
        final notifier = AuthNotifier();
        notifier.setSession(_session);
        return notifier;
      }),
    ],
    child: MaterialApp(
      theme: buildMalvaTheme(),
      home: home,
    ),
  );
}

void main() {
  test('full assessment export retains older assessments behind 100 worksheets',
      () async {
    final api = MalvaApiClient(
        baseUrl: 'http://backend.test',
        httpClient: _FakeClient((request) async {
          final body = request.url.path == '/v1/therapy-submissions'
              ? {
                  'submissions': [
                    for (var i = 0; i < 100; i++)
                      _submission(
                          id: 'therapy-$i',
                          moduleId: 'abcde',
                          title: 'Worksheet',
                          createdAt: '2026-11-08T09:00:00+07:00'),
                    if (request.url.queryParameters['limit'] == '0')
                      _submission(
                          id: 'older-who5',
                          moduleId: 'who5',
                          title: 'WHO lama',
                          createdAt: '2025-01-01T09:00:00+07:00',
                          answers: _who5Answers())
                  ]
                }
              : {'screenings': []};
          return http.Response(jsonEncode(body), 200);
        }));
    final entries = await loadAssessmentHistory(
        api: api,
        accessToken: 'token',
        patientId: 'patient-1',
        requireAllSources: true);
    expect(entries, hasLength(1));
    expect(entries.single.title, 'WHO lama');
  });
  test(
      'PDF loader can require every assessment source while history retains partial results',
      () async {
    final api = MalvaApiClient(
        baseUrl: 'http://backend.test',
        httpClient: _FakeClient((request) async {
          if (request.url.path == '/v1/therapy-submissions')
            return http.Response('{"error":"Unavailable"}', 500);
          return http.Response(
              jsonEncode({
                'screenings': [_screening()]
              }),
              200);
        }));
    final partial = await loadAssessmentHistory(
        api: api, accessToken: 'test-token', patientId: 'user_pasien_1');
    expect(partial.length, 1);
    await expectLater(
        loadAssessmentHistory(
            api: api,
            accessToken: 'test-token',
            patientId: 'user_pasien_1',
            requireAllSources: true),
        throwsA(isA<MalvaApiException>()));
  });
  testWidgets(
      'patient record filters retain retakes, sort both ways and reveal bounded results',
      (tester) async {
    tester.view.physicalSize = const Size(800, 5000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = _api(submissions: [
      for (var i = 1; i <= 6; i++)
        _submission(
            id: 'who-$i',
            moduleId: 'who5',
            title: 'Retake $i',
            createdAt: '2026-11-0${i}T09:00:00+07:00',
            answers: _who5Answers()),
      _submission(
          id: 'unknown',
          moduleId: 'who5',
          title: 'Unknown date',
          createdAt: '',
          answers: _who5Answers()),
    ], screenings: [
      _screening()
    ]);
    await tester
        .pumpWidget(_buildApp(api, home: const AssessmentHistoryScreen()));
    await tester.pumpAndSettle();
    expect(find.byType(AssessmentHistoryCard), findsNWidgets(5));
    expect(find.text('Retake 1'), findsNothing);
    await tester.tap(find.textContaining('Tampilkan lebih banyak'));
    await tester.pumpAndSettle();
    expect(find.text('Retake 1'), findsOneWidget);
    expect(find.text('Tanggal tidak tercatat'), findsOneWidget);
    final dropdown =
        tester.widget<DropdownButton<bool>>(find.byType(DropdownButton<bool>));
    dropdown.onChanged!(true);
    await tester.pumpAndSettle();
    final cards = tester
        .widgetList<AssessmentHistoryCard>(find.byType(AssessmentHistoryCard))
        .toList();
    expect(cards.first.entry.title, 'Screening PHQ-9 + GAD-7');
    expect(cards[1].entry.title, 'Retake 1');
    await tester.tap(find.widgetWithText(FilterChip, 'WHO-5'));
    await tester.pumpAndSettle();
    expect(find.byType(AssessmentHistoryCard), findsOneWidget);
    await tester.tap(find.widgetWithText(FilterChip, 'PHQ-9 + GAD-7'));
    await tester.pumpAndSettle();
    expect(find.text('Tidak ada hasil untuk filter ini.'), findsOneWidget);
  });
  test('history excludes incomplete and invalid WHO/DASS legacy submissions',
      () async {
    final validDass = <String, dynamic>{
      for (var i = 1; i <= 21; i++) 'q$i': 1,
      'scale_version': 2,
    };
    final invalidAnswers = <(String, Map<String, dynamic>)>[
      ('who5', {}),
      ('who5', {'scale_version': 2}),
      ('who5', {..._who5Answers()}..remove('q5')),
      ('who5', {..._who5Answers(), 'q1': -1}),
      ('who5', {..._who5Answers(), 'q1': 6}),
      ('who5', {..._who5Answers(), 'q1': 1.5}),
      ('who5', {..._who5Answers(), 'q1': '3'}),
      ('dass21', {}),
      ('dass21', {...validDass}..remove('q21')),
      ('dass21', {...validDass, 'q21': 4}),
    ];
    final api = _api(
      submissions: [
        for (var i = 0; i < invalidAnswers.length; i++)
          _submission(
            id: 'invalid_$i',
            moduleId: invalidAnswers[i].$1,
            title: 'Invalid $i',
            createdAt: '2026-11-07T09:00:00+07:00',
            summary: 'Hasil normal lama',
            answers: invalidAnswers[i].$2,
          ),
        _submission(
          id: 'complete_who',
          moduleId: 'who5',
          title: 'Complete WHO',
          createdAt: '2026-11-07T10:00:00+07:00',
          answers: _who5Answers(),
        ),
        _submission(
          id: 'complete_dass',
          moduleId: 'dass21',
          title: 'Complete DASS',
          createdAt: '2026-11-07T11:00:00+07:00',
          answers: validDass,
        ),
      ],
      screenings: const [],
    );

    final entries = await loadAssessmentHistory(
      api: api,
      accessToken: 'token_test',
      patientId: 'user_pasien_1',
    );

    expect(
        entries.map((entry) => entry.title), ['Complete DASS', 'Complete WHO']);
    expect(entries.last.answers['q5'], 3);
    expect(entries.first.answers['q21'], 1);
  });

  test('history collapses repeated delivery IDs but preserves genuine retakes',
      () async {
    Map<String, dynamic> who(String id, String title, String createdAt) =>
        _submission(
          id: id,
          moduleId: 'who5',
          title: title,
          createdAt: createdAt,
          answers: _who5Answers(),
        );
    final first = who('who_1', 'First', '2026-11-07T09:00:00+07:00');
    final retake = who('who_2', 'Retake', '2026-11-07T10:00:00+07:00');
    final entries = await loadAssessmentHistory(
      api: _api(
        submissions: [
          first,
          first,
          retake,
          who('', 'Without ID A', '2026-11-07T11:00:00+07:00'),
          who('', 'Without ID B', '2026-11-07T12:00:00+07:00'),
        ],
        screenings: const [],
      ),
      accessToken: 'token_test',
    );

    expect(entries.map((entry) => entry.title),
        ['Without ID B', 'Without ID A', 'Retake', 'First']);
  });

  testWidgets(
      'PHQ/GAD patient detail shares record layout, scores, safety and stored CF',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final screening = _screening();
    final bundle = screening['bundle'] as Map<String, dynamic>;
    final phq = bundle['phq9'] as Map<String, dynamic>;
    final gad = bundle['gad7'] as Map<String, dynamic>;
    phq.addAll(<String, Object>{
      'score': 16,
      'level': 'moderately_severe',
      'summary': 'Gejala depresi cukup berat.',
      'crisis_flag': true,
      'cf': 0.95,
    });
    gad.addAll(<String, Object>{'score': 7, 'level': 'mild', 'cf': 0.684});
    screening['crisis_flag'] = true;
    await tester.pumpWidget(_buildApp(
      _api(submissions: const [], screenings: [screening]),
      home: const AssessmentHistoryScreen(),
    ));
    await tester.pumpAndSettle();

    expect(find.text('PHQ-9 16/27 (Cukup berat) • GAD-7 7/21 (Ringan)'),
        findsOneWidget);
    await tester.tap(find.text('Screening PHQ-9 + GAD-7'));
    await tester.pumpAndSettle();

    expect(find.text('Detail Record'), findsOneWidget);
    expect(find.text('PHQ-9 Total Score'), findsOneWidget);
    expect(find.text('GAD-7 Total Score'), findsOneWidget);
    expect(find.text('16'), findsOneWidget);
    expect(find.text('7'), findsOneWidget);
    expect(find.text('Cukup Berat'), findsOneWidget);
    expect(find.text('Ringan'), findsOneWidget);
    expect(find.text('KRISIS'), findsOneWidget);
    expect(find.text('INDIKATOR KESELAMATAN: YA'), findsOneWidget);
    expect(find.text('PHQ-9 · Dukungan rule internal (CF)'), findsOneWidget);
    expect(find.text('GAD-7 · Dukungan rule internal (CF)'), findsOneWidget);
    expect(find.textContaining('0.95', findRichText: true), findsOneWidget);
    expect(find.textContaining('0.68', findRichText: true), findsOneWidget);
    expect(find.text('moderately_severe'), findsNothing);
    expect(find.text('mild'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'unified Screening keeps WHO, PHQ/GAD and DASS manually reachable',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 3200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = _api(submissions: const [], screenings: const []);
    await tester.pumpWidget(
      _buildApp(api, home: const AssessmentListScreen()),
    );
    await tester.pumpAndSettle();

    expect(find.text('Screening'), findsOneWidget);
    expect(find.text('Screening Utama'), findsNothing);
    expect(find.text('Assessment Lanjutan'), findsNothing);
    final who = find.text('WHO-5 (Well-Being Index)');
    final phqGad = find.text('PHQ-9 + GAD-7');
    final dass = find.text('DASS-21 (Depression Anxiety Stress Scales)');
    expect(tester.getTopLeft(who).dy, lessThan(tester.getTopLeft(phqGad).dy));
    expect(tester.getTopLeft(phqGad).dy, lessThan(tester.getTopLeft(dass).dy));

    for (final entry in [who, phqGad, dass]) {
      await tester.tap(entry);
      await tester.pumpAndSettle();
      if (entry == phqGad) {
        expect(find.byType(AssessmentScreen), findsOneWidget);
      } else {
        final detail = tester.widget<TherapyDetailScreen>(
          find.byType(TherapyDetailScreen),
        );
        expect(detail.module.id, entry == who ? 'who5' : 'dass21');
      }
      Navigator.of(tester.element(find.byType(Scaffold).last)).pop();
      await tester.pumpAndSettle();
    }
  });

  testWidgets(
      'Assessment Record menampilkan worksheet asesmen + screening, menyembunyikan worksheet terapi, urut DESC',
      (tester) async {
    final api = _api(
      submissions: [
        _submission(
          id: 'sub_abcde',
          moduleId: 'abcde',
          title: 'Restrukturisasi Kognitif (ABCDE)',
          createdAt: '2026-10-19T09:00:00.000Z',
          summary: 'Latihan ABCDE minggu ini',
        ),
        _submission(
          id: 'sub_who5',
          moduleId: 'who5',
          title: 'WHO-5 (Well-Being Index)',
          createdAt: '2026-10-20T09:00:00.000Z',
          summary: 'WHO-5 15/25 (60%) — Cukup',
          answers: _who5Answers(),
        ),
      ],
      screenings: [_screening()],
    );

    await tester.pumpWidget(
      _buildApp(api, home: const AssessmentHistoryScreen()),
    );
    await tester.pumpAndSettle();

    expect(find.text('Assessment Record'), findsOneWidget);
    expect(find.text('WHO-5 (Well-Being Index)'), findsOneWidget);
    expect(find.text('Screening PHQ-9 + GAD-7'), findsOneWidget);

    // Worksheet terapi tidak masuk assessment record.
    expect(find.text('Restrukturisasi Kognitif (ABCDE)'), findsNothing);

    // Urut tanggal DESC: screening (22/10) di atas worksheet WHO-5 (20/10).
    final screeningTop =
        tester.getTopLeft(find.text('Screening PHQ-9 + GAD-7')).dy;
    final who5Top = tester.getTopLeft(find.text('WHO-5 (Well-Being Index)')).dy;
    expect(screeningTop, lessThan(who5Top));
  });

  testWidgets(
      'AssessmentListScreen: hanya SATU "Lihat semua", disclaimer di atas Assessment Record, tap membuka halaman lengkap',
      (tester) async {
    // Viewport tinggi agar seluruh ListView (lazy) di halaman Assessment
    // ter-build — disclaimer, seksi record, dan tombol semuanya terukur.
    tester.view.physicalSize = const Size(1200, 3200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final api = _api(
      submissions: [
        _submission(
          id: 'sub_who5',
          moduleId: 'who5',
          title: 'WHO-5 (Well-Being Index)',
          createdAt: '2026-10-20T09:00:00.000Z',
          summary: 'WHO-5 15/25 (60%) — Cukup',
          answers: _who5Answers(),
        ),
      ],
      screenings: [_screening()],
    );

    await tester.pumpWidget(
      _buildApp(api, home: const AssessmentListScreen()),
    );
    await tester.pumpAndSettle();

    // Hanya SATU tombol "Lihat semua" — aksi pada SectionLabel Assessment
    // Record. Footer di dalam preview sudah dihapus.
    expect(find.text('Lihat semua'), findsOneWidget);

    // Disclaimer berada DI ATAS judul 'Assessment Record'.
    final disclaimerTop =
        tester.getTopLeft(find.textContaining('alat bantu screening')).dy;
    final sectionTop = tester.getTopLeft(find.text('Assessment Record')).dy;
    expect(disclaimerTop, lessThan(sectionTop));

    // Tap "Lihat semua" membuka halaman Assessment Record lengkap.
    await tester.tap(find.text('Lihat semua'));
    await tester.pumpAndSettle();
    expect(find.byType(AssessmentHistoryScreen), findsOneWidget);
    expect(find.text('WHO-5 (Well-Being Index)'), findsOneWidget);
  });

  testWidgets(
      'tap entri asesmen -> bottom sheet berisi AssessmentResultCard + disclaimer',
      (tester) async {
    final api = _api(
      submissions: [
        _submission(
          id: 'sub_who5',
          moduleId: 'who5',
          title: 'WHO-5 (Well-Being Index)',
          createdAt: '2026-10-20T09:00:00.000Z',
          summary: 'WHO-5 15/25 (60%) — Cukup',
          answers: _who5Answers(),
        ),
      ],
      screenings: const [],
    );

    await tester.pumpWidget(
      _buildApp(api, home: const AssessmentHistoryScreen()),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('WHO-5 (Well-Being Index)'));
    await tester.pumpAndSettle();

    expect(find.text('Hasil WHO-5'), findsOneWidget);
    expect(
        find.text(
            'Skor assessment adalah alat bantu screening, bukan diagnosis.'),
        findsOneWidget);
  });

  testWidgets('tap entri screening -> bottom sheet berisi skor PHQ-9 dan GAD-7',
      (tester) async {
    final api = _api(submissions: const [], screenings: [_screening()]);

    await tester.pumpWidget(
      _buildApp(api, home: const AssessmentHistoryScreen()),
    );
    await tester.pumpAndSettle();

    // Ringkasan skor tampil di kartu daftar.
    expect(find.text('PHQ-9 12/27 (Sedang) • GAD-7 9/21 (Ringan)'),
        findsOneWidget);

    await tester.tap(find.text('Screening PHQ-9 + GAD-7'));
    await tester.pumpAndSettle();

    expect(find.text('PHQ-9 Total Score'), findsOneWidget);
    expect(find.text('GAD-7 Total Score'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
    expect(find.text('9'), findsOneWidget);
    expect(find.textContaining('Screening ini menandai risiko krisis'),
        findsNothing);
  });
}

/// Klien HTTP palsu (pola repo, lihat `malva_api_client_test.dart`).
class _FakeClient extends http.BaseClient {
  _FakeClient(this.handler);

  final FutureOr<http.Response> Function(http.Request request) handler;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final body = request is http.Request ? request.body : '';
    final replay = http.Request(request.method, request.url)
      ..headers.addAll(request.headers)
      ..body = body;
    final response = await handler(replay);
    return http.StreamedResponse(
      Stream.value(response.bodyBytes),
      response.statusCode,
      headers: response.headers,
      reasonPhrase: response.reasonPhrase,
      request: replay,
    );
  }
}
