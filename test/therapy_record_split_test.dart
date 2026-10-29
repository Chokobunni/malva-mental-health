import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:malva_mental_health/src/models.dart';
import 'package:malva_mental_health/src/providers/auth_providers.dart';
import 'package:malva_mental_health/src/services/malva_api_client.dart';
import 'package:malva_mental_health/src/theme.dart';
import 'package:malva_mental_health/src/widgets/therapy_library.dart';

// ============================================================
// PEMISAHAN THERAPY RECORD
//
// `TherapySubmissionsScreen` (menu More → Therapy Record) HANYA
// menampilkan worksheet terapi. Hasil assessment (DASS-21/WHO-5)
// punya halamannya sendiri (Assessment Record) — lihat
// `assessment_record_history_test.dart`. Filter ada di getter
// `_therapyItems`: `findTherapyModuleById(id)?.isAssessment != true`
// sehingga modul tak dikenal TETAP tampil (data pasien tidak
// boleh hilang diam-diam).
// ============================================================

/// Sesi pasien uji (token uji, id backend tetap agar stub screening cocok).
const _session = AuthSession(
  role: UserRole.patient,
  identifier: 'pasien@malva.app',
  displayName: 'Pasien',
  backendUserId: 'user_pasien_1',
  accessToken: 'token_test',
);

/// Satu submission worksheet dalam respons `GET /v1/therapy-submissions`
/// (bentuk persis seperti yang di-parse `BackendTherapySubmission.fromJson`).
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

/// Bungkus layar dengan provider palsu: klien HTTP uji + sesi pasien.
Widget _buildApp(MalvaApiClient api) {
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
      home: const TherapySubmissionsScreen(),
    ),
  );
}

/// Klien API dengan daftar submission worksheet yang di-stub.
MalvaApiClient _apiWithSubmissions(List<Map<String, dynamic>> submissions) {
  return MalvaApiClient(
    baseUrl: 'http://backend.test',
    httpClient: _FakeClient((request) async {
      expect(request.url.path, '/v1/therapy-submissions');
      return http.Response(
        jsonEncode({'submissions': submissions}),
        200,
        headers: {'content-type': 'application/json'},
      );
    }),
  );
}

void main() {
  testWidgets(
      'Therapy Record menampilkan worksheet terapi dan menyembunyikan hasil assessment WHO-5',
      (tester) async {
    final api = _apiWithSubmissions([
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
      ),
    ]);

    await tester.pumpWidget(_buildApp(api));
    await tester.pumpAndSettle();

    // Judul layar + worksheet terapi tampil.
    expect(find.text('Therapy Record'), findsOneWidget);
    expect(find.text('Restrukturisasi Kognitif (ABCDE)'), findsOneWidget);

    // Hasil assessment TIDAK muncul di halaman ini.
    expect(find.text('WHO-5 (Well-Being Index)'), findsNothing);
    expect(find.textContaining('WHO-5'), findsNothing);

    // Tidak ada sisa label campuran dari versi lama.
    expect(find.text('Hasil Assessment'), findsNothing);
    expect(find.text('Hasil Therapy'), findsNothing);
  });

  testWidgets(
      'hanya submission assessment -> empty state "Belum ada therapy record" muncul',
      (tester) async {
    final api = _apiWithSubmissions([
      _submission(
        id: 'sub_who5',
        moduleId: 'who5',
        title: 'WHO-5 (Well-Being Index)',
        createdAt: '2026-10-20T09:00:00.000Z',
        summary: 'WHO-5 15/25 (60%) — Cukup',
      ),
    ]);

    await tester.pumpWidget(_buildApp(api));
    await tester.pumpAndSettle();

    expect(find.text('Belum ada therapy record'), findsOneWidget);
    // Judul worksheet asesmen tidak pernah tampil sebagai kartu.
    expect(find.text('WHO-5 (Well-Being Index)'), findsNothing);
  });

  testWidgets(
      'submission dengan modul tak dikenal tetap tampil sebagai therapy record',
      (tester) async {
    final api = _apiWithSubmissions([
      _submission(
        id: 'sub_hantu',
        moduleId: 'modul_hantu',
        title: 'Worksheet Modul Hantu',
        createdAt: '2026-10-18T09:00:00.000Z',
        summary: 'Modul sudah tidak terdaftar di aplikasi',
      ),
    ]);

    await tester.pumpWidget(_buildApp(api));
    await tester.pumpAndSettle();

    // Data pasien tidak boleh hilang hanya karena definisi modul berubah.
    expect(find.text('Worksheet Modul Hantu'), findsOneWidget);
    expect(find.text('Belum ada therapy record'), findsNothing);
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
