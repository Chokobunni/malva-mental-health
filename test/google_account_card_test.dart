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
import 'package:malva_mental_health/src/widgets/google_account_card.dart';

// ============================================================
// GOOGLE ACCOUNT CARD — menautkan Gmail & mengaktifkan Google Meet.
// Memakai klien HTTP palsu + provider override (pola
// test/health_record_sync_test.dart) agar tidak menyentuh GoogleSignIn asli.
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

/// Membungkus widget dalam provider scope + MaterialApp (Scaffold agar
/// SnackBar bisa tampil).
Widget _wrap(MalvaApiClient api, AuthSession session, Widget child) {
  final container = ProviderContainer(
    overrides: [
      apiClientProvider.overrideWithValue(api),
      authStateProvider.overrideWith((ref) {
        final notifier = AuthNotifier();
        notifier.setSession(session);
        return notifier;
      }),
    ],
  );
  addTearDown(container.dispose);
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      theme: buildMalvaTheme(),
      home: Scaffold(
        body: SingleChildScrollView(child: child),
      ),
    ),
  );
}

void main() {
  testWidgets(
      'pasien belum tertaut: tombol Hubungkan Gmail mengirim id_token lalu menampilkan email',
      (tester) async {
    final requests = <http.Request>[];
    final api = MalvaApiClient(
      baseUrl: 'http://backend.test',
      httpClient: _FakeClient((request) async {
        requests.add(request);
        switch ('${request.method} ${request.url.path}') {
          case 'GET /v1/auth/google-identity':
            return _json({'linked': false, 'email': ''});
          case 'POST /v1/auth/bind-google':
            return _json({
              'linked': true,
              'email': 'pasien@gmail.com',
              'linked_at': '2026-10-05T10:00:00.000Z',
              'email_is_placeholder': false,
            });
          default:
            return _json(const {});
        }
      }),
    );

    await tester.pumpWidget(_wrap(
      api,
      _patientSession,
      GoogleAccountCard(
        session: _patientSession,
        idTokenProvider: () async => 'id-token-123',
      ),
    ));
    await tester.pumpAndSettle();

    // Belum tertaut -> tombol Hubungkan Gmail tersedia.
    expect(find.widgetWithText(FilledButton, 'Hubungkan Gmail'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Hubungkan Gmail'));
    await tester.pumpAndSettle();

    // POST /v1/auth/bind-google terkirim dengan id_token yang di-inject.
    final bind = requests.firstWhere((r) =>
        r.method == 'POST' && r.url.path == '/v1/auth/bind-google');
    expect((jsonDecode(bind.body) as Map)['id_token'], 'id-token-123');

    // UI menampilkan email hasil bind.
    expect(find.text('pasien@gmail.com'), findsOneWidget);
    expect(find.text('Terhubung'), findsOneWidget);
  });

  testWidgets('konflik 409 google_sudah_tertaut menampilkan pesan Indonesia',
      (tester) async {
    final api = MalvaApiClient(
      baseUrl: 'http://backend.test',
      httpClient: _FakeClient((request) async {
        switch ('${request.method} ${request.url.path}') {
          case 'GET /v1/auth/google-identity':
            return _json({'linked': false, 'email': ''});
          case 'POST /v1/auth/bind-google':
            return _json({
              'error': 'Akun Google ini sudah terhubung ke akun Malva lain.',
              'code': 'google_sudah_tertaut',
            }, status: 409);
          default:
            return _json(const {});
        }
      }),
    );

    await tester.pumpWidget(_wrap(
      api,
      _patientSession,
      GoogleAccountCard(
        session: _patientSession,
        idTokenProvider: () async => 'id-token-123',
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Hubungkan Gmail'));
    await tester.pumpAndSettle();

    // Pesan actionable dipetakan dari kode mesin, tanpa crash.
    expect(
      find.text('Gmail ini sudah terhubung ke akun Malva lain. '
          'Satu Gmail hanya boleh untuk satu akun.'),
      findsOneWidget,
    );
    // Masih belum tertaut -> tombol tetap ada.
    expect(find.widgetWithText(FilledButton, 'Hubungkan Gmail'), findsOneWidget);
  });

  testWidgets('profesional showMeet: status connected menampilkan Google Meet aktif',
      (tester) async {
    final api = MalvaApiClient(
      baseUrl: 'http://backend.test',
      httpClient: _FakeClient((request) async {
        switch ('${request.method} ${request.url.path}') {
          case 'GET /v1/auth/google-identity':
            return _json({
              'linked': true,
              'email': 'dr.hafid@gmail.com',
              'linked_at': '2026-10-05T10:00:00.000Z',
            });
          case 'GET /v1/google/status':
            return _json({
              'server_configured': true,
              'connected': true,
              'scope': 'https://www.googleapis.com/auth/calendar.events',
            });
          default:
            return _json(const {});
        }
      }),
    );

    await tester.pumpWidget(_wrap(
      api,
      _proSession,
      const GoogleAccountCard(session: _proSession, showMeet: true),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Google Meet aktif'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Aktifkan Google Meet'), findsNothing);
  });

  testWidgets('profesional showMeet: status belum connected menampilkan tombol Aktifkan',
      (tester) async {
    final api = MalvaApiClient(
      baseUrl: 'http://backend.test',
      httpClient: _FakeClient((request) async {
        switch ('${request.method} ${request.url.path}') {
          case 'GET /v1/auth/google-identity':
            return _json({'linked': true, 'email': 'dr.hafid@gmail.com'});
          case 'GET /v1/google/status':
            return _json({'server_configured': true, 'connected': false, 'scope': ''});
          default:
            return _json(const {});
        }
      }),
    );

    await tester.pumpWidget(_wrap(
      api,
      _proSession,
      const GoogleAccountCard(session: _proSession, showMeet: true),
    ));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(FilledButton, 'Aktifkan Google Meet'),
        findsOneWidget);
  });

  testWidgets('tertaut: tombol "Lepas Gmail" tampil saat linked:true',
      (tester) async {
    final api = MalvaApiClient(
      baseUrl: 'http://backend.test',
      httpClient: _FakeClient((request) async {
        switch ('${request.method} ${request.url.path}') {
          case 'GET /v1/auth/google-identity':
            return _json({
              'linked': true,
              'email': 'pasien@gmail.com',
              'linked_at': '2026-10-05T10:00:00.000Z',
            });
          default:
            return _json(const {});
        }
      }),
    );

    await tester.pumpWidget(_wrap(
      api,
      _patientSession,
      const GoogleAccountCard(session: _patientSession),
    ));
    await tester.pumpAndSettle();

    expect(
        find.widgetWithText(OutlinedButton, 'Lepas Gmail'), findsOneWidget);
  });

  testWidgets(
      'tap Lepas Gmail -> dialog konfirmasi -> POST unbind -> kartu jadi Hubungkan Gmail',
      (tester) async {
    final requests = <http.Request>[];
    final api = MalvaApiClient(
      baseUrl: 'http://backend.test',
      httpClient: _FakeClient((request) async {
        switch ('${request.method} ${request.url.path}') {
          case 'GET /v1/auth/google-identity':
            return _json({
              'linked': true,
              'email': 'pasien@gmail.com',
              'linked_at': '2026-10-05T10:00:00.000Z',
            });
          case 'POST /v1/auth/unbind-google':
            requests.add(request);
            return _json({'linked': false, 'email_is_placeholder': false});
          default:
            return _json(const {});
        }
      }),
    );

    await tester.pumpWidget(_wrap(
      api,
      _patientSession,
      const GoogleAccountCard(session: _patientSession),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(OutlinedButton, 'Lepas Gmail'));
    await tester.pumpAndSettle();

    // Dialog konfirmasi muncul.
    expect(find.text('Lepas Gmail?'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Lepas'));
    await tester.pumpAndSettle();

    // Endpoint unbind benar-benar dipanggil.
    expect(
      requests.any((r) =>
          r.method == 'POST' && r.url.path == '/v1/auth/unbind-google'),
      isTrue,
    );
    // Kartu berubah ke kondisi belum tertaut.
    expect(find.widgetWithText(FilledButton, 'Hubungkan Gmail'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Lepas Gmail'), findsNothing);
  });

  testWidgets(
      'unbind 409 perlu_password -> dialog password -> request kedua memuat new_password',
      (tester) async {
    final unbindBodies = <String>[];
    var unbindCalls = 0;
    final api = MalvaApiClient(
      baseUrl: 'http://backend.test',
      httpClient: _FakeClient((request) async {
        switch ('${request.method} ${request.url.path}') {
          case 'GET /v1/auth/google-identity':
            return _json({
              'linked': true,
              'email': 'pasien@gmail.com',
              'linked_at': '2026-10-05T10:00:00.000Z',
            });
          case 'POST /v1/auth/unbind-google':
            unbindCalls++;
            if (unbindCalls == 1) {
              return _json({
                'error':
                    'Tetapkan password baru dulu agar akun tetap bisa dipakai setelah Gmail dilepas.',
                'code': 'perlu_password',
              }, status: 409);
            }
            unbindBodies.add(request.body);
            return _json({'linked': false, 'email_is_placeholder': false});
          default:
            return _json(const {});
        }
      }),
    );

    await tester.pumpWidget(_wrap(
      api,
      _patientSession,
      const GoogleAccountCard(session: _patientSession),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(OutlinedButton, 'Lepas Gmail'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Lepas'));
    await tester.pumpAndSettle();

    // Dialog password baru muncul.
    expect(find.widgetWithText(FilledButton, 'Simpan & Lepas'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'PasswordBaru123!');
    await tester.tap(find.widgetWithText(FilledButton, 'Simpan & Lepas'));
    await tester.pumpAndSettle();

    // Request kedua membawa new_password.
    expect(unbindBodies, hasLength(1));
    expect(
      (jsonDecode(unbindBodies.single) as Map)['new_password'],
      'PasswordBaru123!',
    );
    expect(find.widgetWithText(FilledButton, 'Hubungkan Gmail'), findsOneWidget);
  });

  testWidgets(
      'unbind dengan password akun mengirim current_password tanpa minta password baru',
      (tester) async {
    final unbindBodies = <String>[];
    final api = MalvaApiClient(
      baseUrl: 'http://backend.test',
      httpClient: _FakeClient((request) async {
        switch ('${request.method} ${request.url.path}') {
          case 'GET /v1/auth/google-identity':
            return _json({
              'linked': true,
              'email': 'pasien@gmail.com',
              'linked_at': '2026-10-05T10:00:00.000Z',
            });
          case 'POST /v1/auth/unbind-google':
            unbindBodies.add(request.body);
            return _json({'linked': false, 'email_is_placeholder': false});
          default:
            return _json(const {});
        }
      }),
    );

    await tester.pumpWidget(_wrap(
      api,
      _patientSession,
      const GoogleAccountCard(session: _patientSession),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(OutlinedButton, 'Lepas Gmail'));
    await tester.pumpAndSettle();

    // Dialog konfirmasi punya field password akun opsional.
    await tester.enterText(find.byType(TextField), 'PasswordAkun123!');
    await tester.tap(find.widgetWithText(FilledButton, 'Lepas'));
    await tester.pumpAndSettle();

    // Request memuat current_password, bukan new_password.
    expect(unbindBodies, hasLength(1));
    final body = jsonDecode(unbindBodies.single) as Map;
    expect(body['current_password'], 'PasswordAkun123!');
    expect(body.containsKey('new_password'), isFalse);
    // Tidak ada dialog password baru; kartu langsung jadi belum tertaut.
    expect(find.widgetWithText(FilledButton, 'Simpan & Lepas'), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Hubungkan Gmail'), findsOneWidget);
  });
}

/// Klien HTTP palsu (pola repo, lihat `test/health_record_sync_test.dart`).
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
