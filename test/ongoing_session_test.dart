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
import 'package:malva_mental_health/src/theme.dart';
import 'package:malva_mental_health/src/time/wib.dart';

// ============================================================
// SESI BERJALAN: tombol Gabung/Chat tetap ada setelah profesional "Hadir".
//
// Akar masalah: kartu sesi hanya menampilkan aksi bila `session.isScheduled`.
// Begitu profesional menekan "Hadir" (status completed) di dalam jendela waktu,
// tombol Gabung/Chat hilang padahal sesi belum benar-benar usai. Perbaikan:
// tampilkan aksi selama `isCareSessionOngoing` (scheduled ATAU completed di
// dalam jendela waktu).
//
// Test ini gagal SEBELUM perbaikan (completed di jendela -> tanpa tombol Join).
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
      'professional_name': professionalName,
      'session_type': 'chat',
      'scheduled_at': scheduledAt,
      'duration_minutes': 30,
      'status': status,
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
  setUpAll(initializeWib);

  testWidgets('sesi completed di dalam jendela tetap menampilkan tombol Join',
      (tester) async {
    final now = wibNow();
    final api = MalvaApiClient(
      baseUrl: 'http://backend.test',
      httpClient: _careClient([
        // Completed TEPAT SEKARANG -> masih di jendela (mulai -10m s/d +60m).
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

    // Hanya sesi yang masih di jendela yang menampilkan tombol Join/Chat.
    expect(find.text('Join'), findsOneWidget,
        reason: 'sesi completed yang masih di jendela harus tetap punya '
            'tombol Join (chat tetap hidup sampai jendela habis)');
    expect(find.text('Kirim'), findsOneWidget);
  });

  testWidgets('sesi completed di luar jendela tidak menampilkan tombol',
      (tester) async {
    final now = wibNow();
    final api = MalvaApiClient(
      baseUrl: 'http://backend.test',
      httpClient: _careClient([
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

    expect(find.text('dr. Lewat'), findsOneWidget);
    expect(find.text('Join'), findsNothing,
        reason: 'jendela sudah tutup; tombol Join tidak boleh muncul');
  });

  // ------------------------------------------------------------------
  // REGRESI: sesi completed yang tampil di daftar "Riwayat sesi" (past: true)
  // tetap harus menampilkan aksi "Join / Chat" selama masih di jendela waktu.
  //
  // Sebelum perbaikan, kartu memakai `if (!past && live)` sehingga sesi yang
  // sudah ditandai "Hadir" (completed) — yang setelah reload masuk daftar past
  // — kehilangan tombol Join/Chat. Test ini gagal sebelum `if (live)`.
  // ------------------------------------------------------------------
  testWidgets(
      'kartu Jadwal profesional: sesi past yang masih berjalan tetap '
      'menampilkan "Join / Chat"', (tester) async {
    final now = wibNow();
    final pastSession = _sessionJson(
      id: 's_past_live',
      status: 'completed',
      professionalName: 'dr. Hadir',
      // 5 menit lalu, durasi 30 -> masih di jendela (s/d +55m).
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

    // Aksi ada di section "Riwayat sesi" (bawah lipatan) — gulir dulu.
    await tester.scrollUntilVisible(
      find.text('Join / Chat'),
      300,
      scrollable: find.byType(Scrollable).first,
    );

    expect(find.text('Join / Chat'), findsOneWidget,
        reason: 'sesi past (completed) yang masih di jendela harus tetap '
            'punya tombol Join / Chat');
    // Hadir/Tidak hadir TIDAK ditawarkan ulang untuk sesi completed.
    expect(find.text('Hadir'), findsNothing);
    expect(find.text('Tidak hadir'), findsNothing);
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
