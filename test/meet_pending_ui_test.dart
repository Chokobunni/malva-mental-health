import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:malva_mental_health/src/models.dart';
import 'package:malva_mental_health/src/providers/auth_providers.dart';
import 'package:malva_mental_health/src/services/google_auth_service.dart';
import 'package:malva_mental_health/src/services/malva_api_client.dart';
import 'package:malva_mental_health/src/theme.dart';
import 'package:malva_mental_health/src/widgets/google_account_card.dart';
import 'package:malva_mental_health/src/widgets/meet_join_button.dart';

// ============================================================
// SESI VIDEO "MENUNGGU LINK" & IZIN GOOGLE CALENDAR
//
// Aturan bisnis yang dikunci di sini (keputusan pemilik produk):
//   - Kondisi akun Google milik PROFESIONAL tidak boleh memblokir PASIEN.
//     Sesi video tetap terjadwal; link Meet dibuat menyusul.
//   - Pasien TIDAK diberi tombol yang membuka URL kosong: ia melihat
//     "Menunggu link video". Profesional melihat tombol "Buat link Meet".
//   - Kegagalan `403 access_denied` (consent screen Google masih Testing /
//     akun belum jadi Test user) diterjemahkan menjadi pesan actionable,
//     bukan error teknis mentah.
// ============================================================

const _proSession = AuthSession(
  role: UserRole.professional,
  identifier: 'dr.hafid@malva.app',
  displayName: 'dr. Hafid',
  backendUserId: 'user_pro_1',
  accessToken: 'token_test',
);

BackendCareSession _videoSession({String meetingUrl = ''}) =>
    BackendCareSession.fromJson(<String, dynamic>{
      'id': 'sess_video_1',
      'patient_id': 'user_pasien_1',
      'professional_id': 'user_pro_1',
      'patient_name': 'Pasien',
      'professional_name': 'dr. Hafid',
      'session_type': 'video',
      'scheduled_at': '2099-01-01T10:00:00+07:00',
      'duration_minutes': 30,
      'status': 'scheduled',
      'meeting_url': meetingUrl,
    });

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
    child: MaterialApp(
      theme: buildMalvaTheme(),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );
}

void main() {
  group('MeetJoinButton — sesi video tanpa link', () {
    testWidgets('pasien melihat "Menunggu link video", bukan tombol buat link',
        (tester) async {
      final api = MalvaApiClient(
        baseUrl: 'http://backend.test',
        httpClient: _FakeClient((request) async => _json(const {})),
      );

      await tester.pumpWidget(_wrap(
        api,
        MeetJoinButton(
          session: _videoSession(),
          accessToken: 'token_test',
          canCreateLink: false,
          onSessionChanged: (_) {},
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Menunggu link video'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Buat link Meet'), findsNothing);
      // Tidak ada tombol "Gabung" yang akan membuka URL kosong.
      expect(
          find.widgetWithText(FilledButton, 'Gabung video call'), findsNothing);
    });

    testWidgets('profesional melihat tombol "Buat link Meet"', (tester) async {
      final api = MalvaApiClient(
        baseUrl: 'http://backend.test',
        httpClient: _FakeClient((request) async => _json(const {})),
      );

      await tester.pumpWidget(_wrap(
        api,
        MeetJoinButton(
          session: _videoSession(),
          accessToken: 'token_test',
          onSessionChanged: (_) {},
        ),
      ));
      await tester.pumpAndSettle();

      expect(
          find.widgetWithText(FilledButton, 'Buat link Meet'), findsOneWidget);
      expect(find.text('Menunggu link video'), findsNothing);
    });
  });

  group('GoogleAuthService — 403 access_denied', () {
    test('mengenali pesan access_denied Google', () {
      expect(
        GoogleAuthService.looksLikeAccessDenied(
          'Error 403: access_denied — Malva has not completed the Google '
          'verification process.',
        ),
        isTrue,
      );
      expect(
        GoogleAuthService.looksLikeAccessDenied(
          'The app is currently being tested and can only be accessed by '
          'developer-approved testers.',
        ),
        isTrue,
      );
      expect(GoogleAuthService.looksLikeAccessDenied('network error'), isFalse);
      expect(GoogleAuthService.looksLikeAccessDenied(null), isFalse);
    });

    test('pesan menyebut langkah perbaikan & tautan konsol, bukan kode mentah',
        () {
      final message = GoogleAuthService.accessDeniedMessage(
        'Error 403: access_denied',
      );
      expect(message, contains('access_denied'));
      expect(message, contains('Test users'));
      expect(message, contains('mem-publish'));
      expect(
        message,
        contains(
          'https://console.cloud.google.com/apis/credentials/consent'
          '?project=malva-7084e',
        ),
      );
      expect(message, contains('docs/GOOGLE_CALENDAR_SETUP.md'));
    });
  });

  group('GoogleAccountCard — keadaan Google Meet', () {
    testWidgets(
        'reason token_expired: penjelasan kedaluwarsa + tombol hubungkan',
        (tester) async {
      final api = MalvaApiClient(
        baseUrl: 'http://backend.test',
        httpClient: _FakeClient((request) async {
          switch ('${request.method} ${request.url.path}') {
            case 'GET /v1/auth/google-identity':
              return _json({'linked': true, 'email': 'dr.hafid@gmail.com'});
            case 'GET /v1/professionals/user_pro_1/meet-status':
              return _json({'ready': false, 'reason': 'token_expired'});
            case 'GET /v1/google/status':
              return _json({
                'server_configured': true,
                'connected': false,
                'scope': '',
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

      expect(find.textContaining('kedaluwarsa'), findsOneWidget);
      expect(
        find.widgetWithText(FilledButton, 'Hubungkan Google Calendar'),
        findsOneWidget,
      );
      expect(find.text('Google Meet aktif'), findsNothing);
    });

    testWidgets('reason server_not_configured: pesan admin tanpa tombol',
        (tester) async {
      final api = MalvaApiClient(
        baseUrl: 'http://backend.test',
        httpClient: _FakeClient((request) async {
          switch ('${request.method} ${request.url.path}') {
            case 'GET /v1/auth/google-identity':
              return _json({'linked': true, 'email': 'dr.hafid@gmail.com'});
            case 'GET /v1/professionals/user_pro_1/meet-status':
              return _json({'ready': false, 'reason': 'server_not_configured'});
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

      expect(find.textContaining('Admin belum mengaktifkan'), findsOneWidget);
      expect(
        find.widgetWithText(FilledButton, 'Hubungkan Google Calendar'),
        findsNothing,
      );
    });
  });

  group('MalvaApiClient — status Meet & meet_pending', () {
    test('professionalMeetStatus membaca ready & reason', () async {
      final api = MalvaApiClient(
        baseUrl: 'http://backend.test',
        httpClient: _FakeClient((request) async {
          expect(request.url.path, '/v1/professionals/user_pro_1/meet-status');
          return _json({'ready': false, 'reason': 'no_calendar_scope'});
        }),
      );

      final status = await api.professionalMeetStatus(
        accessToken: 'token_test',
        professionalId: 'user_pro_1',
      );
      expect(status.ready, isFalse);
      expect(status.reason, 'no_calendar_scope');
    });

    test('scheduleSession meneruskan meet_pending dari server', () async {
      final api = MalvaApiClient(
        baseUrl: 'http://backend.test',
        httpClient: _FakeClient((request) async {
          return _json({
            'session': {
              'id': 'sess_1',
              'patient_id': 'user_pasien_1',
              'professional_id': 'user_pro_1',
              'session_type': 'video',
              'scheduled_at': '2099-01-01T10:00:00+07:00',
              'duration_minutes': 30,
              'status': 'scheduled',
              'meeting_url': '',
            },
            'meet_pending': true,
          }, status: 201);
        }),
      );

      final result = await api.scheduleSession(
        accessToken: 'token_test',
        packageId: 'pkg_1',
        scheduledAt: '2099-01-01T10:00',
        sessionType: 'video',
      );
      expect(result.meetPending, isTrue);
      expect(result.session.meetingUrl, isEmpty);
    });

    test('professionalMeetStatus membaca google_email & hint', () async {
      final api = MalvaApiClient(
        baseUrl: 'http://backend.test',
        httpClient: _FakeClient((request) async {
          return _json({
            'ready': false,
            'reason': 'no_calendar_scope',
            'google_email': 'andiwijayapsikolog@gmail.com',
            'hint': 'Tekan Hubungkan Google Calendar.',
          });
        }),
      );

      final status = await api.professionalMeetStatus(
        accessToken: 'token_test',
        professionalId: 'user_pro_1',
      );
      expect(status.googleEmail, 'andiwijayapsikolog@gmail.com');
      expect(status.hint, 'Tekan Hubungkan Google Calendar.');
    });

    test('setManualMeetLink mengirim PUT meet_url dan membaca sesi', () async {
      String? method;
      String? body;
      final api = MalvaApiClient(
        baseUrl: 'http://backend.test',
        httpClient: _FakeClient((request) async {
          method = request.method;
          body = request.body;
          return _json({
            'session': {
              'id': 'sess_1',
              'patient_id': 'user_pasien_1',
              'professional_id': 'user_pro_1',
              'session_type': 'video',
              'scheduled_at': '2099-01-01T10:00:00+07:00',
              'duration_minutes': 30,
              'status': 'scheduled',
              'meeting_url': 'https://meet.google.com/abc-defg-hij',
            },
            'manual': true,
          });
        }),
      );

      final session = await api.setManualMeetLink(
        accessToken: 'token_test',
        sessionId: 'sess_1',
        meetUrl: 'https://meet.google.com/abc-defg-hij',
      );
      expect(method, 'PUT');
      expect(body, contains('meet.google.com/abc-defg-hij'));
      expect(session.meetingUrl, 'https://meet.google.com/abc-defg-hij');
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
