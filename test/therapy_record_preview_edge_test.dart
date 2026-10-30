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
// QA — T2: SEKSI "THERAPY RECORD" DI HALAMAN KATALOG TERAPI + UJI TEPI
//
// Membuktikan `TherapyRecordPreview`:
//   - empty state saat 0 item (halaman katalog tidak blank).
//   - error state saat server 500 (tidak crash, tetap ada tombol Coba).
//   - tidak error saat token kosong (belum login) → ajakan login.
//   - modul tak dikenal tetap dianggap terapi (data pasien tidak hilang).
//   - hasil asesmen (WHO-5) tersaring keluar.
//   - kartu read-only (tanpa tombol Bagikan/Hapus) & maks 3 kartu terbaru.
//   - tap "Lihat semua"/kartu membuka TherapySubmissionsScreen.
// ============================================================

const _session = AuthSession(
  role: UserRole.patient,
  identifier: 'pasien@malva.app',
  displayName: 'Pasien',
  backendUserId: 'user_pasien_1',
  accessToken: 'token_test',
);

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

MalvaApiClient _apiWith(
  List<Map<String, dynamic>> submissions, {
  int status = 200,
}) {
  return MalvaApiClient(
    baseUrl: 'http://backend.test',
    httpClient: _FakeClient((request) async {
      if (request.url.path == '/v1/therapy-submissions') {
        return http.Response(
          jsonEncode({'submissions': submissions}),
          status,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response('{}', 200,
          headers: {'content-type': 'application/json'});
    }),
  );
}

Widget _app(MalvaApiClient api, {required Widget home, bool withSession = true}) {
  return ProviderScope(
    overrides: [
      apiClientProvider.overrideWithValue(api),
      authStateProvider.overrideWith((ref) {
        final notifier = AuthNotifier();
        if (withSession) notifier.setSession(_session);
        return notifier;
      }),
    ],
    child: MaterialApp(theme: buildMalvaTheme(), home: home),
  );
}

void _tallViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 8000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets('T2: empty state saat 0 submission, katalog tetap tampil',
      (tester) async {
    _tallViewport(tester);
    final api = _apiWith([]);
    await tester.pumpWidget(
      _app(api, home: const TherapyCatalogScreen()),
    );
    await tester.pumpAndSettle();

    // Seksi Therapy Record tetap ada + empty state.
    expect(find.text('Therapy Record'), findsOneWidget);
    expect(find.textContaining('Belum ada therapy record'), findsOneWidget);
    // Katalog tidak blank: modul pertama tetap tampil.
    expect(find.text(allTherapyModules.first.title), findsWidgets);
  });

  testWidgets('T2: error state (server 500) tidak membuat katalog blank/crash',
      (tester) async {
    _tallViewport(tester);
    final api = _apiWith([], status: 500);
    await tester.pumpWidget(
      _app(api, home: const TherapyCatalogScreen()),
    );
    await tester.pumpAndSettle();

    // Kartu error tampil + tombol Coba, tanpa crash.
    expect(find.textContaining('Therapy record belum bisa dimuat'), findsOneWidget);
    expect(find.text('Coba'), findsOneWidget);
    // Katalog tetap ter-render (tidak blank).
    expect(find.text(allTherapyModules.first.title), findsWidgets);
    expect(find.text('Therapy Record'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('T2: token kosong (belum login) → ajakan login, bukan crash',
      (tester) async {
    _tallViewport(tester);
    final api = _apiWith([
      _submission(
        id: 'sub_1',
        moduleId: 'abcde',
        title: 'Terapi ABCDE',
        createdAt: '2026-10-19T09:00:00.000Z',
      ),
    ]);
    await tester.pumpWidget(
      _app(api, home: const TherapyCatalogScreen(), withSession: false),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Login dulu untuk melihat therapy record'),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'T2: modul tak dikenal tetap dianggap terapi, asesmen WHO-5 tersaring',
      (tester) async {
    final api = _apiWith([
      _submission(
        id: 'sub_who5',
        moduleId: 'who5',
        title: 'WHO-5 (Well-Being Index)',
        createdAt: '2026-10-21T09:00:00.000Z',
      ),
      _submission(
        id: 'sub_unknown',
        moduleId: 'modul_yang_tidak_ada_di_katalog',
        title: 'Worksheet Modul Lama',
        createdAt: '2026-10-20T09:00:00.000Z',
      ),
    ]);
    await tester.pumpWidget(
      _app(
        api,
        home: const Scaffold(body: SingleChildScrollView(child: TherapyRecordPreview())),
      ),
    );
    await tester.pumpAndSettle();

    // Modul tak dikenal TIDAK dibuang (data pasien tidak hilang).
    expect(find.text('Worksheet Modul Lama'), findsOneWidget);
    // Asesmen WHO-5 dibuang dari therapy record.
    expect(find.textContaining('WHO-5'), findsNothing);
  });

  testWidgets('T2: kartu pratinjau read-only (tanpa tombol Bagikan/Hapus)',
      (tester) async {
    final api = _apiWith([
      _submission(
        id: 'sub_1',
        moduleId: 'abcde',
        title: 'Terapi ABCDE',
        createdAt: '2026-10-19T09:00:00.000Z',
      ),
    ]);
    await tester.pumpWidget(
      _app(
        api,
        home: const Scaffold(body: SingleChildScrollView(child: TherapyRecordPreview())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Terapi ABCDE'), findsOneWidget);
    // Pratinjau tidak memuat aksi berbahaya (itu hanya di halaman penuh).
    expect(find.text('Bagikan'), findsNothing);
    expect(find.text('Hapus'), findsNothing);
  });

  testWidgets('T2: maksimal 3 kartu & urut terbaru dulu', (tester) async {
    final api = _apiWith([
      for (var i = 1; i <= 4; i++)
        _submission(
          id: 'sub_t$i',
          moduleId: 'abcde',
          title: 'Terapi #$i',
          createdAt: '2026-10-0${i}T09:00:00.000Z',
        ),
    ]);
    await tester.pumpWidget(
      _app(
        api,
        home: const Scaffold(body: SingleChildScrollView(child: TherapyRecordPreview())),
      ),
    );
    await tester.pumpAndSettle();

    // Terbaru (#4,#3,#2) tampil; #1 (terlama) di luar batas 3.
    expect(find.text('Terapi #4'), findsOneWidget);
    expect(find.text('Terapi #3'), findsOneWidget);
    expect(find.text('Terapi #2'), findsOneWidget);
    expect(find.text('Terapi #1'), findsNothing);
  });

  testWidgets('T2: tap kartu pratinjau membuka TherapySubmissionsScreen',
      (tester) async {
    final api = _apiWith([
      _submission(
        id: 'sub_1',
        moduleId: 'abcde',
        title: 'Terapi ABCDE',
        createdAt: '2026-10-19T09:00:00.000Z',
      ),
    ]);
    await tester.pumpWidget(
      _app(
        api,
        home: const Scaffold(body: SingleChildScrollView(child: TherapyRecordPreview())),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Terapi ABCDE'));
    await tester.pumpAndSettle();
    expect(find.byType(TherapySubmissionsScreen), findsOneWidget);
  });
}

/// Klien HTTP palsu (pola repo).
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
