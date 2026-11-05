import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:malva_mental_health/src/models.dart';
import 'package:malva_mental_health/src/providers/providers.dart';
import 'package:malva_mental_health/src/screens/my_care_screen.dart';
import 'package:malva_mental_health/src/screens/pro_schedule_screen.dart';
import 'package:malva_mental_health/src/services/malva_api_client.dart';
import 'package:malva_mental_health/src/services/server_clock.dart';
import 'package:malva_mental_health/src/theme.dart';
import 'package:malva_mental_health/src/time/wib.dart';

// ============================================================
// Hadir tidak menyelesaikan sesi: status tetap scheduled dan aksi tetap aktif
// selama jendela waktu. Status completed selalu terminal, termasuk data legacy
// yang sudah completed sebelum durasi terjadwal berakhir. Riwayat tetap terbaca.
//
// Kehadiran tiap peserta dibaca dari field sendiri; completed bukan sinonim Hadir.
// ============================================================

const _patientSession = AuthSession(
  role: UserRole.patient,
  identifier: 'pasien@malva.app',
  displayName: 'Pasien',
  backendUserId: 'user_pasien_1',
  accessToken: 'token_test',
);

const _proSession = AuthSession(
  role: UserRole.professional,
  identifier: 'prof@malva.app',
  displayName: 'dr. Profesional',
  backendUserId: 'user_pro_1',
  accessToken: 'token_test',
);

String _two(int v) => v.toString().padLeft(2, '0');

String _isoWib(DateTime value) {
  final d = toWib(value);
  return '${d.year}-${_two(d.month)}-${_two(d.day)}'
      'T${_two(d.hour)}:${_two(d.minute)}:${_two(d.second)}+07:00';
}

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
      'patient_name': 'Pasien sesi',
      'professional_name': professionalName,
      'session_type': 'chat',
      'scheduled_at': scheduledAt,
      'duration_minutes': 30,
      'status': status,
      'summary_for_patient': 'Ringkasan tersimpan $id',
    };

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

/// Klien palsu untuk layar Jadwal profesional. Sesi `past` dikembalikan lewat
/// scope `past` (yang di layar masuk ke daftar "Riwayat sesi", `past: true`).
MalvaApiClient _proScheduleApi(List<Map<String, dynamic>> past) {
  return MalvaApiClient(
    baseUrl: 'http://backend.test',
    httpClient: _FakeClient((request) async {
      final path = request.url.path;
      final scope = request.url.queryParameters['scope'] ?? '';
      switch (path) {
        case '/v1/care-sessions':
          if (scope == 'past') return _json({'sessions': past});
          return _json({'sessions': <dynamic>[]});
        case '/v1/professional/schedules':
          return _json({'schedules': <dynamic>[]});
        case '/v1/pricing':
          return _json({'pricing': <String, dynamic>{}});
        case '/v1/professional/time-off':
          return _json({'time_off': <dynamic>[]});
      }
      return _json({'error': 'unexpected $path'}, status: 404);
    }),
  );
}

void main() {
  setUp(() {
    initializeWib();
    ServerClock.reset();
  });
  tearDown(ServerClock.reset);

  testWidgets('sesi completed menutup aksi walau masih di dalam jendela',
      (tester) async {
    final now = ServerClock.now();
    final api = MalvaApiClient(
      baseUrl: 'http://backend.test',
      httpClient: _careClient([
        // Data legacy completed pada jadwal sekarang tetap terminal.
        _sessionJson(
          id: 's_in',
          status: 'completed',
          professionalName: 'dr. Berjalan',
          scheduledAt: _isoWib(now),
        ),
        // Completed 3 jam lalu -> jendela sudah tutup, tanpa tombol.
        _sessionJson(
          id: 's_out',
          status: 'completed',
          professionalName: 'dr. Lewat',
          scheduledAt: _isoWib(now.subtract(const Duration(hours: 3))),
        ),
      ]),
    );
    await tester.pumpWidget(_wrap(api));
    await tester.pumpAndSettle();
    await _openTab(tester, 'Riwayat');

    // Kedua sesi tampil di Riwayat.
    expect(find.text('dr. Berjalan'), findsOneWidget);
    expect(find.text('dr. Lewat'), findsOneWidget);

    expect(find.text('Ringkasan: Ringkasan tersimpan s_in'), findsOneWidget);
    expect(find.text('Ringkasan: Ringkasan tersimpan s_out'), findsOneWidget);
    expect(find.text('Join'), findsNothing,
        reason: 'completed menutup akses tanpa menunggu akhir jendela');
    expect(find.text('Kirim'), findsNothing);
    expect(find.widgetWithText(OutlinedButton, 'Hadir'), findsNothing);
    expect(find.widgetWithText(OutlinedButton, 'Tidak hadir'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'kehadiran saya pada sesi scheduled tidak menutup Join atau Kirim',
      (tester) async {
    final now = ServerClock.now();
    final api = MalvaApiClient(
      baseUrl: 'http://backend.test',
      httpClient: _careClient([
        _sessionJson(
          id: 's_attended',
          status: 'scheduled',
          professionalName: 'dr. Berjalan',
          scheduledAt: _isoWib(now.subtract(const Duration(minutes: 5))),
        )..['patient_attendance'] = 'attended',
      ]),
    );
    await tester.pumpWidget(_wrap(api));
    await tester.pumpAndSettle();
    await _openTab(tester, 'Jadwal');

    expect(find.text('dr. Berjalan'), findsOneWidget);
    expect(find.text('Kehadiran saya: Hadir'), findsOneWidget);
    expect(find.text('Join'), findsOneWidget,
        reason: 'konfirmasi hadir mempertahankan status scheduled');
    expect(find.text('Kirim'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Hadir'), findsNothing);
    expect(find.widgetWithText(OutlinedButton, 'Tidak hadir'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  // ------------------------------------------------------------------
  // Riwayat profesional mempertahankan kartu completed beserta ringkasannya,
  // tetapi tidak membuka kembali aksi sesi, walau jadwalnya baru lima menit lalu.
  // ------------------------------------------------------------------
  testWidgets(
      'kartu Riwayat profesional completed tetap terbaca tanpa aksi sesi',
      (tester) async {
    final now = ServerClock.now();
    final pastSession = _sessionJson(
      id: 's_past_live',
      status: 'completed',
      professionalName: 'dr. Hadir',
      // Data legacy completed di dalam jendela tetap terminal.
      scheduledAt: _isoWib(now.subtract(const Duration(minutes: 5))),
    );
    final api = _proScheduleApi([pastSession]);

    final container = ProviderContainer(
      overrides: [apiClientProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);
    container.read(malvaStoreProvider.notifier).applySession(_proSession);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildMalvaTheme(),
          home: Scaffold(
            body: ProScheduleScreen(session: _proSession, apiClient: api),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Gulir ke kartu yang harus tetap ada, bukan tombol yang memang dilarang.
    final card = find.byKey(const ValueKey('past-s_past_live'));
    await tester.scrollUntilVisible(card, 300,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    expect(card, findsOneWidget);

    expect(find.text('Pasien sesi'), findsOneWidget);
    expect(find.text('Ringkasan: Ringkasan tersimpan s_past_live'),
        findsOneWidget);
    expect(find.text('Join / Chat'), findsNothing,
        reason: 'completed terminal walau waktu terjadwal belum habis');
    // Hadir/Tidak hadir TIDAK ditawarkan ulang untuk sesi completed.
    expect(find.text('Hadir'), findsNothing);
    expect(find.text('Tidak hadir'), findsNothing);
    expect(find.text('Sesi selesai'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}

class _FakeClient extends http.BaseClient {
  _FakeClient(this.handler);

  final FutureOr<http.Response> Function(http.Request request) handler;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final replay = http.Request(request.method, request.url)
      ..headers.addAll(request.headers);
    if (request is http.Request) {
      replay.bodyBytes = request.bodyBytes;
    }
    final response = await handler(replay);
    return http.StreamedResponse(
      Stream<List<int>>.value(response.bodyBytes),
      response.statusCode,
      headers: response.headers,
      request: request,
    );
  }
}
