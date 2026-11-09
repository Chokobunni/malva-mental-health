import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:malva_mental_health/src/models.dart';
import 'package:malva_mental_health/src/providers/auth_providers.dart';
import 'package:malva_mental_health/src/screens/care_package_screen.dart';
import 'package:malva_mental_health/src/services/malva_api_client.dart';
import 'package:malva_mental_health/src/theme.dart';
import 'package:malva_mental_health/src/widgets/google_account_card.dart';

// ============================================================
// UI: JADWAL SESI VIDEO SAAT GOOGLE PROFESIONAL BELUM SIAP
//
// Yang dikunci:
//   - Sheet penjadwalan menampilkan CATATAN INFO (bukan error) saat
//     meet-status belum siap, dan tombol "Pilih Jadwal" tetap bisa dipakai
//     setelah slot dipilih. Pasien tidak boleh buntu.
//   - Kartu Akun Google membedakan 3 keadaan; keadaan "siap" menampilkan
//     "Google Meet aktif".
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
  identifier: 'dr.hafid@malva.app',
  displayName: 'dr. Hafid',
  backendUserId: 'user_pro_1',
  accessToken: 'token_test',
);

http.Response _json(Object body, {int status = 200}) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    );

Widget _wrap(MalvaApiClient api, Widget child, {AuthSession? session}) {
  final container = ProviderContainer(
    overrides: [
      apiClientProvider.overrideWithValue(api),
      authStateProvider.overrideWith((ref) {
        final notifier = AuthNotifier();
        if (session != null) notifier.setSession(session);
        return notifier;
      }),
    ],
  );
  addTearDown(container.dispose);
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp(theme: buildMalvaTheme(), home: child),
  );
}

Map<String, dynamic> _activePackageJson() => <String, dynamic>{
      'id': 'pkg_1',
      'patient_id': 'user_pasien_1',
      'professional_id': 'user_pro_1',
      'professional_name': 'dr. Hafid',
      'patient_name': 'Pasien',
      'total_sessions': 4,
      'used_sessions': 0,
      'remaining_sessions': 4,
      'validity_days': 42,
      'price': 400000,
      'status': 'active',
      'starts_at': '2026-01-01T00:00:00+07:00',
      'expires_at': '2099-12-31T00:00:00+07:00',
    };

/// Fake client yang meniru backend saat Google profesional belum aktif.
http.Client _pendingMeetClient() {
  return _FakeClient((request) async {
    final key = '${request.method} ${request.url.path}';
    if (key == 'GET /v1/care-packages') {
      return _json({
        'packages': [_activePackageJson()]
      });
    }
    if (key == 'GET /v1/care-sessions') {
      return _json({'sessions': const []});
    }
    if (key == 'GET /v1/doctors/user_pro_1/availability') {
      return _json({
        'days': [
          {
            'date': '2099-01-02',
            'day_of_week': 5,
            'off': false,
            'free_slots': 3
          }
        ]
      });
    }
    if (key == 'GET /v1/doctors/user_pro_1/slots') {
      return _json({
        'slots': [
          {'time': '10:00', 'available': true},
          {'time': '11:00', 'available': true},
        ]
      });
    }
    if (key == 'GET /v1/professionals/user_pro_1/meet-status') {
      return _json({'ready': false, 'reason': 'no_calendar_scope'});
    }
    return _json(const {});
  });
}

void main() {
  group('_SessionSchedulerSheet — catatan info saat Meet belum siap', () {
    testWidgets(
        'menampilkan catatan info (bukan error) & Pilih Jadwal tetap aktif',
        (tester) async {
      final api = MalvaApiClient(
        baseUrl: 'http://backend.test',
        httpClient: _pendingMeetClient(),
      );

      await tester.pumpWidget(_wrap(
        api,
        CarePackageScreen(
          package: BackendCarePackage.fromJson(_activePackageJson()),
          session: _patientSession,
          apiClient: api,
        ),
        session: _patientSession,
      ));
      await tester.pumpAndSettle();

      // Buka sheet penjadwalan.
      final openButton = find.widgetWithText(FilledButton, 'Jadwalkan Sesi');
      expect(openButton, findsOneWidget);
      await tester.ensureVisible(openButton);
      await tester.tap(openButton);
      await tester.pumpAndSettle();

      // Video satu jam dipilih otomatis; catatan muncul saat Meet belum siap.
      expect(find.text('Video • 1 jam per sesi'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'Chat'), findsNothing);

      expect(
        find.textContaining('Video tetap bisa dijadwalkan'),
        findsOneWidget,
        reason: 'catatan info harus tampil saat Meet profesional belum siap',
      );

      // Pilih slot -> tombol "Pilih Jadwal" harus AKTIF (Meet tidak memblokir).
      await tester.tap(find.widgetWithText(ChoiceChip, '10:00'));
      await tester.pumpAndSettle();

      final pickButton = find.widgetWithText(FilledButton, 'Pilih Jadwal');
      expect(pickButton, findsOneWidget);
      final button = tester.widget<FilledButton>(pickButton);
      expect(button.onPressed, isNotNull,
          reason: 'status Meet tidak boleh menonaktifkan tombol Pilih Jadwal');
    });
  });

  group('GoogleAccountCard — keadaan siap', () {
    testWidgets('reason ready menampilkan "Google Meet aktif"', (tester) async {
      final api = MalvaApiClient(
        baseUrl: 'http://backend.test',
        httpClient: _FakeClient((request) async {
          switch ('${request.method} ${request.url.path}') {
            case 'GET /v1/auth/google-identity':
              return _json({'linked': true, 'email': 'dr.hafid@gmail.com'});
            case 'GET /v1/professionals/user_pro_1/meet-status':
              return _json({'ready': true, 'reason': 'ready'});
            case 'GET /v1/google/status':
              return _json({
                'server_configured': true,
                'connected': true,
                'calendar_ready': true,
                'scope': 'https://www.googleapis.com/auth/calendar.events',
              });
            default:
              return _json(const {});
          }
        }),
      );

      await tester.pumpWidget(_wrap(
        api,
        const GoogleAccountCard(session: _proSession, showMeet: true),
        session: _proSession,
      ));
      await tester.pumpAndSettle();

      expect(find.text('Google Meet aktif'), findsOneWidget);
      expect(
        find.widgetWithText(FilledButton, 'Hubungkan Google Calendar'),
        findsNothing,
      );
    });
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
      reasonPhrase: response.reasonPhrase,
      request: replay,
    );
  }
}
