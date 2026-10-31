import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:malva_mental_health/src/models.dart';
import 'package:malva_mental_health/src/providers/auth_providers.dart';
import 'package:malva_mental_health/src/screens/my_care_screen.dart';
import 'package:malva_mental_health/src/services/malva_api_client.dart';
import 'package:malva_mental_health/src/theme.dart';

// ============================================================
// FILTER STATUS SESI DI MYCARE
//
// Yang dikunci:
//   - Chip filter status di atas daftar SESI, dijalankan di klien atas data
//     yang sudah dimuat (tanpa round-trip tambahan).
//   - Chip PER TAB: tab Jadwal hanya memuat sesi `scheduled` sehingga hanya
//     punya "Semua"+"Aktif"; tab Riwayat punya Selesai/Dibatalkan/Tidak hadir
//     (plus "Aktif" bila ada sesi `pending_payment`, yang juga masuk _past).
//   - State filter DIPISAH per tab: pilihan "Dibatalkan" di Riwayat tidak
//     boleh membawa empty state yang salah ke tab Jadwal.
//   - "Dibatalkan" hanya menampilkan sesi batal; filter tanpa hasil
//     menampilkan empty state SPESIFIK; "Semua" mengembalikan seluruh sesi.
//   - Kartu paket (tab "Paket") tidak ikut difilter.
// ============================================================

const _patientSession = AuthSession(
  role: UserRole.patient,
  identifier: 'pasien@malva.app',
  displayName: 'Pasien',
  backendUserId: 'user_pasien_1',
  accessToken: 'token_test',
);

Map<String, dynamic> _sessionJson({
  required String id,
  required String status,
  required String professionalName,
  required String scheduledAt,
}) =>
    <String, dynamic>{
      'id': id,
      'patient_id': 'user_pasien_1',
      'professional_id': 'user_pro_1',
      'professional_name': professionalName,
      'session_type': 'chat',
      'scheduled_at': scheduledAt,
      'duration_minutes': 30,
      'status': status,
    };

Map<String, dynamic> _aktif() => _sessionJson(
      id: 'sess_aktif',
      status: 'scheduled',
      professionalName: 'dr. Aktif',
      scheduledAt: '2099-01-02T10:00:00+07:00',
    );

Map<String, dynamic> _selesai() => _sessionJson(
      id: 'sess_selesai',
      status: 'completed',
      professionalName: 'dr. Selesai',
      scheduledAt: '2026-01-05T10:00:00+07:00',
    );

Map<String, dynamic> _batal() => _sessionJson(
      id: 'sess_batal',
      status: 'cancelled_by_patient',
      professionalName: 'dr. Batal',
      scheduledAt: '2026-01-06T10:00:00+07:00',
    );

Map<String, dynamic> _tidakHadir() => _sessionJson(
      id: 'sess_hadir',
      status: 'no_show',
      professionalName: 'dr. Tidak Hadir',
      scheduledAt: '2026-01-07T10:00:00+07:00',
    );

/// Sesi `pending_payment` TIDAK berstatus `scheduled`, jadi masuk tab Riwayat.
Map<String, dynamic> _menungguBayar() => _sessionJson(
      id: 'sess_bayar',
      status: 'pending_payment',
      professionalName: 'dr. Menunggu Bayar',
      scheduledAt: '2026-01-08T10:00:00+07:00',
    );

http.Response _json(Object body, {int status = 200}) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    );

http.Client _careClient(List<Map<String, dynamic>> sessions) {
  return _FakeClient((request) async {
    switch ('${request.method} ${request.url.path}') {
      case 'GET /v1/care-packages':
        return _json({'packages': const []});
      case 'GET /v1/care-sessions':
        return _json({'sessions': sessions});
      case 'GET /v1/patient-professional-links':
        return _json({'links': const []});
    }
    return _json({'error': 'unexpected'}, status: 404);
  });
}

Widget _wrap(MalvaApiClient api) {
  final container = ProviderContainer(
    overrides: [apiClientProvider.overrideWithValue(api)],
  );
  addTearDown(container.dispose);
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      theme: buildMalvaTheme(),
      home: MyCareScreen(session: _patientSession, apiClient: api),
    ),
  );
}

Future<void> _openTab(WidgetTester tester, String tab) async {
  await tester.tap(find.widgetWithText(ChoiceChip, tab));
  await tester.pumpAndSettle();
}

Future<void> _tapFilter(WidgetTester tester, String label) async {
  await tester.tap(find.widgetWithText(ChoiceChip, label));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('filter "Dibatalkan" hanya menampilkan sesi yang dibatalkan',
      (tester) async {
    final api = MalvaApiClient(
        baseUrl: 'http://backend.test',
        httpClient:
            _careClient([_aktif(), _selesai(), _batal(), _tidakHadir()]));
    await tester.pumpWidget(_wrap(api));
    await tester.pumpAndSettle();
    await _openTab(tester, 'Riwayat');

    // Sebelum difilter: ketiga sesi riwayat tampil.
    expect(find.text('dr. Selesai'), findsOneWidget);
    expect(find.text('dr. Batal'), findsOneWidget);
    expect(find.text('dr. Tidak Hadir'), findsOneWidget);

    await _tapFilter(tester, 'Dibatalkan 1');

    expect(find.text('dr. Batal'), findsOneWidget,
        reason: 'sesi yang dibatalkan tetap tampil');
    expect(find.text('dr. Selesai'), findsNothing,
        reason: 'sesi selesai tidak boleh ikut di filter Dibatalkan');
    expect(find.text('dr. Tidak Hadir'), findsNothing,
        reason: 'sesi tidak hadir tidak boleh ikut di filter Dibatalkan');
  });

  testWidgets('filter tanpa hasil menampilkan empty state spesifik',
      (tester) async {
    // Tanpa sesi no_show: chip "Tidak hadir" ada tapi kosong.
    final api = MalvaApiClient(
        baseUrl: 'http://backend.test',
        httpClient: _careClient([_aktif(), _selesai(), _batal()]));
    await tester.pumpWidget(_wrap(api));
    await tester.pumpAndSettle();
    await _openTab(tester, 'Riwayat');

    await _tapFilter(tester, 'Tidak hadir');

    expect(find.text('Belum ada sesi tidak hadir'), findsOneWidget,
        reason: 'filter kosong harus menjelaskan keadaannya');
    expect(find.text('Belum ada riwayat sesi'), findsNothing,
        reason:
            'empty state generik tidak boleh dipakai saat filter spesifik aktif');
  });

  testWidgets('filter "Semua" mengembalikan seluruh sesi', (tester) async {
    final api = MalvaApiClient(
        baseUrl: 'http://backend.test',
        httpClient:
            _careClient([_aktif(), _selesai(), _batal(), _tidakHadir()]));
    await tester.pumpWidget(_wrap(api));
    await tester.pumpAndSettle();
    await _openTab(tester, 'Riwayat');

    await _tapFilter(tester, 'Dibatalkan 1');
    expect(find.text('dr. Selesai'), findsNothing);

    await _tapFilter(tester, 'Semua 3');

    expect(find.text('dr. Selesai'), findsOneWidget);
    expect(find.text('dr. Batal'), findsOneWidget);
    expect(find.text('dr. Tidak Hadir'), findsOneWidget);
  });

  testWidgets('filter tidak muncul di tab Paket (kartu paket tidak difilter)',
      (tester) async {
    final api = MalvaApiClient(
        baseUrl: 'http://backend.test',
        httpClient:
            _careClient([_aktif(), _selesai(), _batal(), _tidakHadir()]));
    await tester.pumpWidget(_wrap(api));
    await tester.pumpAndSettle();

    // Tab awal = Paket.
    expect(find.widgetWithText(ChoiceChip, 'Semua 4'), findsNothing);
    expect(find.widgetWithText(ChoiceChip, 'Dibatalkan 1'), findsNothing);
    expect(find.text('Belum ada paket'), findsOneWidget);
  });

  // ------------------------------------------------------------------
  // Chip PER TAB + state filter terpisah
  // ------------------------------------------------------------------

  testWidgets('tab Jadwal hanya punya chip yang relevan (tanpa Dibatalkan)',
      (tester) async {
    final api = MalvaApiClient(
        baseUrl: 'http://backend.test',
        httpClient:
            _careClient([_aktif(), _selesai(), _batal(), _tidakHadir()]));
    await tester.pumpWidget(_wrap(api));
    await tester.pumpAndSettle();
    await _openTab(tester, 'Jadwal');

    expect(find.widgetWithText(ChoiceChip, 'Semua 1'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Aktif 1'), findsOneWidget);
    // Chip mustahil terisi tidak boleh muncul di tab ini.
    expect(find.widgetWithText(ChoiceChip, 'Dibatalkan'), findsNothing,
        reason: 'tab Jadwal tidak pernah memuat sesi dibatalkan');
    expect(find.widgetWithText(ChoiceChip, 'Tidak hadir'), findsNothing,
        reason: 'tab Jadwal tidak pernah memuat sesi tidak hadir');
    expect(find.widgetWithText(ChoiceChip, 'Selesai'), findsNothing,
        reason: 'tab Jadwal tidak pernah memuat sesi selesai');
  });

  testWidgets('pilihan "Dibatalkan" di Riwayat tidak bocor ke tab Jadwal',
      (tester) async {
    final api = MalvaApiClient(
        baseUrl: 'http://backend.test',
        httpClient:
            _careClient([_aktif(), _selesai(), _batal(), _tidakHadir()]));
    await tester.pumpWidget(_wrap(api));
    await tester.pumpAndSettle();

    await _openTab(tester, 'Riwayat');
    await _tapFilter(tester, 'Dibatalkan 1');
    expect(find.text('dr. Batal'), findsOneWidget);

    await _openTab(tester, 'Jadwal');

    // Tab Jadwal memakai filternya sendiri ("Semua") -> daftar sesi aktif,
    // BUKAN empty state "Belum ada sesi yang dibatalkan".
    expect(find.text('dr. Aktif'), findsOneWidget);
    expect(find.text('Belum ada sesi yang dibatalkan'), findsNothing,
        reason: 'empty state milik tab Riwayat tidak boleh muncul di Jadwal');
    expect(find.widgetWithText(ChoiceChip, 'Semua 1'), findsOneWidget,
        reason: 'chip "Semua" di Jadwal harus terpilih kembali');
  });

  testWidgets('state filter tiap tab independen dan bertahan saat berpindah',
      (tester) async {
    final api = MalvaApiClient(
        baseUrl: 'http://backend.test',
        httpClient:
            _careClient([_aktif(), _selesai(), _batal(), _tidakHadir()]));
    await tester.pumpWidget(_wrap(api));
    await tester.pumpAndSettle();

    // Riwayat: pilih "Tidak hadir".
    await _openTab(tester, 'Riwayat');
    await _tapFilter(tester, 'Tidak hadir 1');
    expect(find.text('dr. Tidak Hadir'), findsOneWidget);
    expect(find.text('dr. Batal'), findsNothing);

    // Jadwal: filter sendiri, semua sesi aktif tampil.
    await _openTab(tester, 'Jadwal');
    expect(find.text('dr. Aktif'), findsOneWidget);
    expect(find.text('dr. Tidak Hadir'), findsNothing);

    // Kembali ke Riwayat: pilihan "Tidak hadir" masih berlaku.
    await _openTab(tester, 'Riwayat');
    expect(find.text('dr. Tidak Hadir'), findsOneWidget);
    expect(find.text('dr. Selesai'), findsNothing,
        reason:
            'filter Riwayat tidak boleh ter-reset oleh kunjungan ke Jadwal');
  });

  testWidgets('sesi pending_payment (masuk tab Riwayat) mendapat chip Aktif',
      (tester) async {
    // pending_payment bukan `scheduled`, jadi ia ada di Riwayat. Tanpa chip
    // "Aktif" di sana, sesi itu hanya terlihat di "Semua" dan tak bisa difilter.
    final api = MalvaApiClient(
        baseUrl: 'http://backend.test',
        httpClient: _careClient([_aktif(), _menungguBayar(), _selesai()]));
    await tester.pumpWidget(_wrap(api));
    await tester.pumpAndSettle();
    await _openTab(tester, 'Riwayat');

    expect(find.widgetWithText(ChoiceChip, 'Aktif 1'), findsOneWidget,
        reason: 'chip Aktif muncul karena ada sesi pending_payment di Riwayat');

    await _tapFilter(tester, 'Aktif 1');
    expect(find.text('dr. Menunggu Bayar'), findsOneWidget);
    expect(find.text('dr. Selesai'), findsNothing);
  });
}

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
      request: request,
    );
  }
}
