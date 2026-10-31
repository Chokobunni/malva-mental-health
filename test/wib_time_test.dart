import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:malva_mental_health/src/models.dart';
import 'package:malva_mental_health/src/providers/auth_providers.dart';
import 'package:malva_mental_health/src/providers/providers.dart';
import 'package:malva_mental_health/src/screens/my_care_screen.dart';
import 'package:malva_mental_health/src/services/malva_api_client.dart';
import 'package:malva_mental_health/src/services/server_clock.dart';
import 'package:malva_mental_health/src/theme.dart';
import 'package:malva_mental_health/src/time/wib.dart';

// ============================================================
// PAKET GABUNGAN DI MYCARE
//
// Aturan bisnis: bila pasien membeli paket kedua dari profesional yang sama
// dan paket lama masih aktif, kuota digabung dan MyCare menampilkan SATU
// kartu gabungan (total/terpakai/sisa dijumlahkan). Regresi untuk kasus
// 4 + 4 pertemuan dengan 1 dipakai -> kartu `7/8 sesi tersisa` +
// catatan `Digabung dari 2 paket`.
// ============================================================

const _session = AuthSession(
  role: UserRole.patient,
  identifier: 'pasien@malva.app',
  displayName: 'Pasien',
  backendUserId: 'user_pasien_1',
  accessToken: 'token_test',
);

Map<String, dynamic> _package({
  required String id,
  required int total,
  required int used,
  required String expiresAt,
}) =>
    {
      'id': id,
      'patient_id': 'user_pasien_1',
      'professional_id': 'pro_123',
      'patient_name': 'Pasien',
      'professional_name': 'Dr. Sinta',
      'total_sessions': total,
      'used_sessions': used,
      'remaining_sessions': total - used,
      'refund_value': 0,
      'refunded_amount': 0,
      'validity_days': 42,
      'price': 400000,
      'status': 'active',
      'starts_at': '2026-09-01T10:00:00+07:00',
      'expires_at': expiresAt,
      'created_at': '2026-09-01T10:00:00+07:00',
    };

MalvaApiClient _apiWith(List<Map<String, dynamic>> packages) {
  return MalvaApiClient(
    baseUrl: 'http://backend.test',
    httpClient: _FakeClient((request) async {
      switch (request.url.path) {
        case '/v1/care-packages':
          return _json({'packages': packages});
        case '/v1/care-sessions':
          return _json({'sessions': <dynamic>[]});
        case '/v1/patient-professional-links':
          return _json({'links': <dynamic>[]});
        default:
          return _json(<String, dynamic>{});
      }
    }),
  );
}

http.Response _json(Object body) => http.Response(
      jsonEncode(body),
      200,
      headers: {'content-type': 'application/json'},
    );

Widget _buildApp(MalvaApiClient api) {
  final container = ProviderContainer(
    overrides: [
      apiClientProvider.overrideWithValue(api),
      authStateProvider.overrideWith((ref) {
        final notifier = AuthNotifier();
        notifier.setSession(_session);
        return notifier;
      }),
    ],
  );
  addTearDown(container.dispose);
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      theme: buildMalvaTheme(),
      home: MyCareScreen(session: _session, apiClient: api),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
    ServerClock.reset();
  });

  tearDown(ServerClock.reset);

  testWidgets('dua paket aktif profesional sama digabung jadi satu kartu 7/8',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    // Masa berlaku RELATIF terhadap sekarang: paket yang sudah lewat
    // `expires_at` tidak ikut digabung (lihat `_isUsablePackage` di MyCare).
    final api = _apiWith([
      _package(
          id: 'pkg_lama',
          total: 4,
          used: 1,
          expiresAt: wibIso(wibNow().add(const Duration(days: 7)))),
      _package(
          id: 'pkg_baru',
          total: 4,
          used: 0,
          expiresAt: wibIso(wibNow().add(const Duration(days: 30)))),
    ]);

    await tester.pumpWidget(_buildApp(api));
    // Biarkan future _load() selesai tanpa mengandalkan pumpAndSettle
    // (refresh indicator ListView bisa menahannya).
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.text('Dr. Sinta'), findsOneWidget);
    // UI merender SATU Text berisi sisa sesi + tanggal berlaku
    // (mis. '7/8 sesi tersisa • s/d 31/10/2026'), jadi pakai textContaining.
    expect(find.textContaining('7/8 sesi tersisa'), findsOneWidget);
    expect(find.text('Digabung dari 2 paket'), findsOneWidget);
  });

  testWidgets('satu paket aktif tampil normal tanpa label gabungan',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final api = _apiWith([
      _package(
          id: 'pkg_satu',
          total: 4,
          used: 1,
          expiresAt: wibIso(wibNow().add(const Duration(days: 7)))),
    ]);

    await tester.pumpWidget(_buildApp(api));
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.text('Dr. Sinta'), findsOneWidget);
    // Idem: satu Text berisi sisa sesi + tanggal berlaku.
    expect(find.textContaining('3/4 sesi tersisa'), findsOneWidget);
    expect(find.textContaining('Digabung'), findsNothing);
  });

  testWidgets('paket aktif yang sudah kedaluwarsa TIDAK ikut digabung ke kartu',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final api = _apiWith([
      // status 'active' tetapi masa berlaku sudah lewat: sisa sesinya hangus,
      // jadi tidak boleh menambah kuota gabungan.
      _package(
          id: 'pkg_kedaluwarsa',
          total: 4,
          used: 1,
          expiresAt: wibIso(wibNow().subtract(const Duration(days: 1)))),
      _package(
          id: 'pkg_valid',
          total: 4,
          used: 0,
          expiresAt: wibIso(wibNow().add(const Duration(days: 30)))),
    ]);

    await tester.pumpWidget(_buildApp(api));
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    // Kuota sah hanya dari paket yang masih berlaku: tidak ada kartu 7/8 dan
    // tidak ada label gabungan.
    expect(find.textContaining('7/8 sesi tersisa'), findsNothing);
    expect(find.textContaining('Digabung dari 2 paket'), findsNothing);
    expect(find.textContaining('4/4 sesi tersisa'), findsOneWidget);
    // Paket kedaluwarsa tetap tampil sebagai kartu terpisah (riwayat pasien).
    expect(find.textContaining('3/4 sesi tersisa'), findsOneWidget);
  });

  test('toWib mengubah ...Z menjadi WIB tanpa bergantung zona perangkat', () {
    initializeWib();
    final wib = toWib(DateTime.parse('2026-10-29T20:20:00Z'));
    expect(wib.day, 30);
    expect(wib.hour, 3);
    expect(wib.timeZoneOffset, const Duration(hours: 7));
    expect(wibApiDateTime(wib), '2026-10-30T03:20');
    expect(toWib(wib), wib);
    expect(toWibOrNull(null), isNull);
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
