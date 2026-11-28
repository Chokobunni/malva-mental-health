import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:malva_mental_health/src/models.dart';
import 'package:malva_mental_health/src/platform/platform_providers.dart';
import 'package:malva_mental_health/src/providers/providers.dart';
import 'package:malva_mental_health/src/screens/pro_schedule_screen.dart';
import 'package:malva_mental_health/src/services/malva_api_client.dart';
import 'package:malva_mental_health/src/theme.dart';
import 'package:malva_mental_health/src/time/wib.dart';

import 'platform/secure_store_test.dart' show InMemorySecureStore;

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

  testWidgets('completed package prompt appears once after reopening Jadwal',
      (tester) async {
    final api = _proScheduleApi([
      {
        'id': 'completed-package',
        'patient_id': 'patient',
        'professional_id': 'user_pro_1',
        'patient_name': 'Pasien Paket',
        'package_id': 'package',
        'session_type': 'video',
        'scheduled_at': _isoWib(wibNow().subtract(const Duration(hours: 2))),
        'duration_minutes': 60,
        'status': 'completed',
        'patient_attendance': 'attended',
        'professional_attendance': 'attended',
      }
    ]);
    final storage = InMemorySecureStore();
    final container = ProviderContainer(overrides: [
      apiClientProvider.overrideWithValue(api),
      secureStoreProvider.overrideWithValue(storage),
    ]);
    addTearDown(container.dispose);
    container.read(authStateProvider.notifier).setSession(_proSession);

    Future<void> openSchedule() async {
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildMalvaTheme(),
          home: Scaffold(
              body: ProScheduleScreen(session: _proSession, apiClient: api)),
        ),
      ));
      await tester.pumpAndSettle();
    }

    await openSchedule();
    final dialog = find.byType(AlertDialog);
    expect(find.descendant(of: dialog, matching: find.text('Sesi Selesai')),
        findsOneWidget);
    expect(find.text('Rekomendasikan sesi lanjutan'), findsNothing);
    await tester.tap(find.text('Nanti'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    await openSchedule();
    expect(dialog, findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'future professional card explains check-in and hides live actions',
      (tester) async {
    final api = _proScheduleApi([
      {
        'id': 'future-session',
        'patient_id': 'patient',
        'professional_id': 'user_pro_1',
        'patient_name': 'Pasien Mendatang',
        'session_type': 'video',
        'scheduled_at': '2099-01-02T10:00:00+07:00',
        'duration_minutes': 30,
        'status': 'scheduled',
      }
    ]);
    final container = ProviderContainer(
        overrides: [apiClientProvider.overrideWithValue(api)]);
    container.read(authStateProvider.notifier).setSession(_proSession);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
            theme: buildMalvaTheme(),
            home: Scaffold(
                body:
                    ProScheduleScreen(session: _proSession, apiClient: api)))));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Lihat Detail Sesi'), 180,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('Terjadwal'), findsOneWidget);
    expect(find.text('Check-in dibuka 10 menit sebelum sesi.'), findsOneWidget);
    expect(find.text('Kehadiran saya'), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Gabung Sesi'), findsNothing);
    expect(find.text('Aksi lain'), findsNothing);
    expect(find.text('Profil'), findsNothing);
    expect(find.text('Reschedule'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    container.dispose();
  });

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

  testWidgets(
      'kartu sesi attended: satu konfirmasi kehadiran, tanpa "Tidak hadir", '
      'tetap ada "Chat"', (tester) async {
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
      'professional_attendance': 'attended',
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
      find.widgetWithText(FilledButton, 'Chat'),
      300,
      scrollable: find.byType(Scrollable).first,
    );

    expect(find.text('Kehadiran saya: Hadir'), findsOneWidget);
    expect(find.text('Hadir'), findsNothing,
        reason: 'kehadiran yang sama tidak perlu pill kedua');
    expect(find.text('Tidak hadir'), findsNothing,
        reason:
            'tombol "Tidak hadir" tidak boleh ditawarkan lagi setelah hadir');
    expect(find.widgetWithText(FilledButton, 'Chat'), findsOneWidget,
        reason: 'sesi tetap berjalan setelah hadir; aksi Chat harus ada');
    await tester.pumpWidget(const SizedBox());
  });
}
