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
// SEKSI "THERAPY RECORD" DI HALAMAN PSYCHOLOGICAL THERAPY
//
// `TherapyCatalogScreen` kini menutup daftar modul dengan
// `SectionLabel('Therapy Record')` + tombol "Lihat semua" +
// `TherapyRecordPreview` (maks 3 kartu read-only, terbaru dulu).
// Preview memakai filter yang sama dengan `TherapySubmissionsScreen`
// (`isTherapyRecordSubmission`) sehingga hasil asesmen (WHO-5) tidak
// ikut tampil.
// ============================================================

/// Sesi pasien uji.
const _session = AuthSession(
  role: UserRole.patient,
  identifier: 'pasien@malva.app',
  displayName: 'Pasien',
  backendUserId: 'user_pasien_1',
  accessToken: 'token_test',
);

/// Satu submission worksheet dalam respons `GET /v1/therapy-submissions`.
Map<String, dynamic> _submission({
  required String id,
  required String moduleId,
  required String title,
  required String createdAt,
  String summary = '',
}) {
  return {
    'id': id,
    'module_id': moduleId,
    'title': title,
    'answers': const <String, dynamic>{},
    'summary': summary,
    'shared_with_professional_id': '',
    'shared_at': null,
    'created_at': createdAt,
  };
}

/// Klien API dengan daftar submission yang di-stub.
MalvaApiClient _apiWith(List<Map<String, dynamic>> submissions) {
  return MalvaApiClient(
    baseUrl: 'http://backend.test',
    httpClient: _FakeClient((request) async {
      if (request.url.path == '/v1/therapy-submissions') {
        return http.Response(
          jsonEncode({'submissions': submissions}),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response(
        '{}',
        200,
        headers: {'content-type': 'application/json'},
      );
    }),
  );
}

/// Bungkus layar dengan provider palsu: klien HTTP uji + sesi pasien.
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
      'seksi Therapy Record muncul setelah daftar modul + tap Lihat semua membuka halaman penuh',
      (tester) async {
    // Viewport tinggi agar seluruh ListView katalog (lazy) ter-build.
    tester.view.physicalSize = const Size(1200, 6000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final api = _apiWith([
      _submission(
        id: 'sub_abcde',
        moduleId: 'abcde',
        title: 'Restrukturisasi Kognitif (ABCDE)',
        createdAt: '2026-10-19T09:00:00.000Z',
        summary: 'Latihan ABCDE',
      ),
    ]);

    await tester.pumpWidget(_buildApp(api, home: const TherapyCatalogScreen()));
    await tester.pumpAndSettle();

    // Seksi 'Therapy Record' tepat satu (SectionLabel), di BAWAH modul pertama.
    expect(find.text('Therapy Record'), findsOneWidget);
    final sectionTop = tester.getTopLeft(find.text('Therapy Record')).dy;
    final firstModuleTop =
        tester.getTopLeft(find.text(allTherapyModules.first.title).first).dy;
    expect(firstModuleTop, lessThan(sectionTop));

    // Tap 'Lihat semua' membuka halaman Therapy Record lengkap.
    await tester.tap(find.text('Lihat semua'));
    await tester.pumpAndSettle();
    expect(find.byType(TherapySubmissionsScreen), findsOneWidget);
  });

  testWidgets(
      'TherapyRecordPreview: maksimal 3 item, terbaru dulu, asesmen WHO-5 tidak muncul',
      (tester) async {
    final api = _apiWith([
      // Hasil asesmen (WHO-5) — harus tersaring keluar dari therapy record.
      _submission(
        id: 'sub_who5',
        moduleId: 'who5',
        title: 'WHO-5 (Well-Being Index)',
        createdAt: '2026-10-21T09:00:00.000Z',
        summary: 'WHO-5 15/25 (60%) — Cukup',
      ),
      for (var i = 1; i <= 4; i++)
        _submission(
          id: 'sub_t$i',
          moduleId: 'abcde',
          title: 'Terapi #$i',
          createdAt: '2026-10-0${i}T09:00:00.000Z',
          summary: 'ringkasan $i',
        ),
    ]);

    await tester.pumpWidget(
      _buildApp(api, home: const Scaffold(body: TherapyRecordPreview())),
    );
    await tester.pumpAndSettle();

    // WHO-5 (asesmen) tidak muncul di therapy record.
    expect(find.text('WHO-5 (Well-Being Index)'), findsNothing);
    expect(find.textContaining('WHO-5'), findsNothing);

    // Terbaru dulu: #4, #3, #2 tampil; #1 (terlama) tersaring oleh batas 3.
    expect(find.text('Terapi #4'), findsOneWidget);
    expect(find.text('Terapi #3'), findsOneWidget);
    expect(find.text('Terapi #2'), findsOneWidget);
    expect(find.text('Terapi #1'), findsNothing);
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
