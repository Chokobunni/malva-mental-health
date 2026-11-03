import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:malva_mental_health/src/models.dart';
import 'package:malva_mental_health/src/providers/providers.dart';
import 'package:malva_mental_health/src/screens/pro_schedule_screen.dart';
import 'package:malva_mental_health/src/services/malva_api_client.dart';
import 'package:malva_mental_health/src/theme.dart';
import 'package:malva_mental_health/src/time/wib.dart';

// ============================================================
// "HADIR" HANYA MENANDAI KEHADIRAN
//
//   - `BackendCareSession` mem-parse `attended_marked_at` -> `isAttended`.
//   - Kartu sesi yang sudah ditandai hadir menampilkan pill "Hadir", TIDAK
//     menampilkan tombol "Tidak hadir" (dan "Hadir"), tetapi TETAP menampilkan
//     "Join / Chat" karena sesi masih berjalan sampai waktunya habis.
// ============================================================

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

http.Response _json(Object body, {int status = 200}) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    );

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

MalvaApiClient _proScheduleApi(List<Map<String, dynamic>> today) {
  return MalvaApiClient(
    baseUrl: 'http://backend.test',
    httpClient: _FakeClient((request) async {
      final path = request.url.path;
      final scope = request.url.queryParameters['scope'] ?? '';
      switch (path) {
        case '/v1/care-sessions':
          if (scope == 'today') return _json({'sessions': today});
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

  test('BackendCareSession mem-parse attended_marked_at -> isAttended', () {
    final attended = BackendCareSession.fromJson(<String, dynamic>{
      'id': 'cs_1',
      'patient_id': 'p',
      'professional_id': 'q',
      'status': 'scheduled',
      'attended_marked_at': '2026-07-10T14:30:00+07:00',
    });
    expect(attended.isAttended, isTrue);
    expect(attended.status, 'scheduled');

    final notAttended = BackendCareSession.fromJson(<String, dynamic>{
      'id': 'cs_2',
      'patient_id': 'p',
      'professional_id': 'q',
      'status': 'scheduled',
    });
    expect(notAttended.isAttended, isFalse);
  });

  testWidgets('kartu sesi attended: pill "Hadir", tanpa "Tidak hadir", '
      'tetap ada "Join / Chat"', (tester) async {
    final now = wibNow();
    final attendedSession = <String, dynamic>{
      'id': 'cs_attended',
      'patient_id': 'user_pasien_1',
      'professional_id': 'user_pro_1',
      'patient_name': 'Pasien Hadir',
      'session_type': 'chat',
      'scheduled_at': _isoWib(now.subtract(const Duration(minutes: 5))),
      'duration_minutes': 30,
      'status': 'scheduled',
      'attended_marked_at': _isoWib(now.subtract(const Duration(minutes: 5))),
    };
    final api = _proScheduleApi([attendedSession]);

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

    await tester.scrollUntilVisible(
      find.text('Join / Chat'),
      300,
      scrollable: find.byType(Scrollable).first,
    );

    expect(find.text('Hadir'), findsOneWidget,
        reason: 'pill "Hadir" harus tampil untuk sesi yang sudah hadir');
    expect(find.text('Tidak hadir'), findsNothing,
        reason: 'tombol "Tidak hadir" tidak boleh ditawarkan lagi setelah hadir');
    expect(find.text('Join / Chat'), findsOneWidget,
        reason: 'sesi tetap berjalan setelah hadir; Join / Chat harus ada');
  });
}
