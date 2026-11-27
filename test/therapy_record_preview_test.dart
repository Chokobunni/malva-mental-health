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
      'preview edits existing worksheet and deletes it after confirmation',
      (tester) async {
    final item = _submission(
      id: 'sub_abcde',
      moduleId: 'abcde',
      title: 'Latihan tersimpan',
      createdAt: '2026-11-20T09:00:00+07:00',
    )..['answers'] = {
        'activating': 'Jawaban lama',
        'legacy_key': 'Pertahankan'
      };
    final writes = <String>[];
    var deleted = false;
    final api = MalvaApiClient(
      baseUrl: 'http://backend.test',
      httpClient: _FakeClient((request) {
        switch (request.method) {
          case 'GET':
            return http.Response(
                jsonEncode({
                  'submissions': [if (!deleted) item],
                }),
                200);
          case 'PUT':
            writes.add('PUT ${request.url.path}');
            final payload = jsonDecode(request.body) as Map<String, dynamic>;
            item['answers'] = payload['answers'];
            return http.Response(jsonEncode({'submission': item}), 200);
          case 'DELETE':
            writes.add('DELETE ${request.url.path}');
            deleted = true;
            return http.Response('{}', 200);
          default:
            fail('Unexpected ${request.method}');
        }
      }),
    );
    await tester.pumpWidget(
        _buildApp(api, home: const Scaffold(body: TherapyRecordPreview())));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Edit'));
    await tester.pumpAndSettle();
    final field = find.byWidgetPredicate((widget) =>
        widget is TextField && widget.controller?.text == 'Jawaban lama');
    await tester.scrollUntilVisible(field, 250,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('Jawaban lama'), findsOneWidget);
    await tester.enterText(field, 'Jawaban diperbarui');
    final save = find.text('Simpan Perubahan');
    await tester.scrollUntilVisible(save, 300,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(item['answers'], containsPair('activating', 'Jawaban diperbarui'));
    expect(item['answers'], containsPair('legacy_key', 'Pertahankan'));
    expect(find.text('Latihan tersimpan'), findsOneWidget);
    await tester.tap(find.byTooltip('Hapus'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Hapus'));
    await tester.pumpAndSettle();
    expect(find.text('Latihan tersimpan'), findsNothing);
    expect(writes, [
      'PUT /v1/therapy-submissions/sub_abcde',
      'DELETE /v1/therapy-submissions/sub_abcde',
    ]);
  });
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
    expect(find.text('Riwayat Terapi'), findsOneWidget);
    final sectionTop = tester.getTopLeft(find.text('Riwayat Terapi')).dy;
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
