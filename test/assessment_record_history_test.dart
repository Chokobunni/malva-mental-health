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
import 'package:malva_mental_health/src/services/malva_api_client.dart';
import 'package:malva_mental_health/src/theme.dart';

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
    expect(find.text('Skor assessment adalah alat bantu screening, bukan diagnosis.'),
        findsOneWidget);
  });

  testWidgets(
      'tap entri screening -> bottom sheet berisi skor PHQ-9 dan GAD-7',
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

    expect(find.text('PHQ-9 — Depresi'), findsOneWidget);
    expect(find.text('GAD-7 — Kecemasan'), findsOneWidget);
    expect(find.text('12/27'), findsOneWidget);
    expect(find.text('9/21'), findsOneWidget);
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
