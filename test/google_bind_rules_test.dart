import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:malva_mental_health/src/models.dart';
import 'package:malva_mental_health/src/providers/auth_providers.dart';
import 'package:malva_mental_health/src/screens/professional_completion_screen.dart';
import 'package:malva_mental_health/src/screens/settings_screens.dart';
import 'package:malva_mental_health/src/services/malva_api_client.dart';
import 'package:malva_mental_health/src/theme.dart';
import 'package:malva_mental_health/src/widgets/google_account_card.dart';

// ============================================================
// ATURAN BIND GMAIL & STR/SIP — test QA independen (bukan milik engineer).
//
// Membuktikan perilaku nyata yang dijanjikan produk:
//  - Pasien TIDAK melihat bagian Google Meet, hanya ajakan menghubungkan Gmail.
//  - Profesional melihat tombol "Aktifkan Google Meet" saat belum connected,
//    dan tombol itu hilang/berubah saat connected.
//  - Konflik 409 `email_sudah_dipakai` dan `akun_sudah_taut_google_lain`
//    menampilkan pesan Indonesia yang BERBEDA (bukan generik).
//  - SettingsScreen menampilkan tile "Akun Google" untuk pasien DAN profesional.
//  - ProfessionalCompletionScreen menangani `str_sip_sudah_terdaftar` tanpa
//    kolom "password akun lama" dan menampilkan pesan aturan.
//
// Pola sama dengan test/health_record_sync_test.dart & test/google_account_card_test.dart:
// fake http.BaseClient + override apiClientProvider / authStateProvider.
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
  refreshToken: 'refresh_test',
);

http.Response _json(Object body, {int status = 200}) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    );

/// ProviderContainer dengan klien API palsu + sesi (bila diberikan).
ProviderContainer _container(
  MalvaApiClient api, {
  AuthSession? session,
}) {
  final container = ProviderContainer(
    overrides: [
      apiClientProvider.overrideWithValue(api),
      if (session != null)
        authStateProvider.overrideWith((ref) {
          final notifier = AuthNotifier();
          notifier.setSession(session);
          return notifier;
        }),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

Widget _app(ProviderContainer container, Widget child) {
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

/// Membungkus satu kartu Google dalam konteks pasien/profesional.
Future<void> _pumpCard(
  WidgetTester tester,
  MalvaApiClient api,
  AuthSession session, {
  bool showMeet = false,
  Future<String?> Function()? idTokenProvider,
}) async {
  final container = _container(api, session: session);
  await tester.pumpWidget(_app(
    container,
    GoogleAccountCard(
      session: session,
      showMeet: showMeet,
      idTokenProvider: idTokenProvider,
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  // ---------------------------------------------------------
  // 1. PASIEN: tidak ada bagian Google Meet sama sekali.
  // ---------------------------------------------------------
  testWidgets('pasien tidak melihat bagian Google Meet, hanya ajakan hubungkan Gmail',
      (tester) async {
    final api = MalvaApiClient(
      baseUrl: 'http://backend.test',
      httpClient: _FakeClient((request) async {
        if (request.method == 'GET' &&
            request.url.path == '/v1/auth/google-identity') {
          return _json({'linked': false, 'email': ''});
        }
        return _json(const {});
      }),
    );

    await _pumpCard(tester, api, _patientSession);

    // Ajakan menghubungkan Gmail tampil.
    expect(find.text('Hubungkan Gmail'), findsWidgets);
    // Tidak ada jejak Google Meet untuk pasien.
    expect(find.textContaining('Google Meet'), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Aktifkan Google Meet'), findsNothing);
  });

  // ---------------------------------------------------------
  // 2a. PROFESIONAL: tombol "Aktifkan Google Meet" muncul saat belum connected.
  // ---------------------------------------------------------
  testWidgets('profesional belum connected: tombol Aktifkan Google Meet tampil',
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

    await _pumpCard(tester, api, _proSession, showMeet: true);

    expect(find.widgetWithText(FilledButton, 'Aktifkan Google Meet'), findsOneWidget);
    expect(find.text('Google Meet aktif'), findsNothing);
  });

  // ---------------------------------------------------------
  // 2b. PROFESIONAL: saat connected, tombol hilang dan status berubah.
  // ---------------------------------------------------------
  testWidgets('profesional connected: tombol Aktifkan hilang, status aktif tampil',
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

    await _pumpCard(tester, api, _proSession, showMeet: true);

    expect(find.text('Google Meet aktif'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Aktifkan Google Meet'), findsNothing);
  });

  // ---------------------------------------------------------
  // 3. Konflik 409: dua kode berbeda -> dua pesan Indonesia berbeda.
  // ---------------------------------------------------------
  testWidgets('409 email_sudah_dipakai dan akun_sudah_taut_google_lain beri pesan berbeda',
      (tester) async {
    Future<String> messageFor(String code, String serverError) async {
      final api = MalvaApiClient(
        baseUrl: 'http://backend.test',
        httpClient: _FakeClient((request) async {
          switch ('${request.method} ${request.url.path}') {
            case 'GET /v1/auth/google-identity':
              return _json({'linked': false, 'email': ''});
            case 'POST /v1/auth/bind-google':
              return _json({'error': serverError, 'code': code}, status: 409);
            default:
              return _json(const {});
          }
        }),
      );

      await _pumpCard(
        tester,
        api,
        _patientSession,
        idTokenProvider: () async => 'id-token-123',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Hubungkan Gmail'));
      await tester.pumpAndSettle();
      // Ambil teks SnackBar yang tampil.
      final snack = tester.widget<Text>(
        find.descendant(
          of: find.byType(SnackBar),
          matching: find.byType(Text),
        ),
      );
      return snack.data ?? '';
    }

    final emailTaken = await messageFor(
      'email_sudah_dipakai',
      'Email Google ini sudah dipakai akun Malva lain.',
    );
    // Reset widget tree sebelum skenario kedua.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();

    final identityBound = await messageFor(
      'akun_sudah_taut_google_lain',
      'Akun ini sudah terhubung ke akun Google lain. Hubungi admin bila ingin mengganti.',
    );

    // Pesan berbeda, spesifik, dan berbahasa Indonesia (bukan generik).
    expect(emailTaken, contains('sudah dipakai akun Malva lain'));
    expect(identityBound, contains('sudah terhubung ke Gmail lain'));
    expect(emailTaken, isNot(equals(identityBound)));
  });

  // ---------------------------------------------------------
  // 4. SettingsScreen: tile "Akun Google" tampil untuk kedua role.
  // ---------------------------------------------------------
  for (final entry in {
    'pasien': _patientSession,
    'profesional': _proSession,
  }.entries) {
    testWidgets('SettingsScreen menampilkan tile "Akun Google" untuk ${entry.key}',
        (tester) async {
      final api = MalvaApiClient(
        baseUrl: 'http://backend.test',
        httpClient: _FakeClient((request) async {
          if (request.method == 'GET' &&
              request.url.path == '/v1/auth/google-identity') {
            return _json({'linked': false, 'email': ''});
          }
          return _json(const {});
        }),
      );
      final container = _container(api, session: entry.value);

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildMalvaTheme(),
          home: SettingsScreen(onLogout: () {}, session: entry.value),
        ),
      ));
      await tester.pumpAndSettle();

      // Tile ada di bagian "Account" yang mungkin di luar viewport ListView;
      // gulir sampai terlihat sebelum memeriksa.
      await tester.scrollUntilVisible(
        find.text('Akun Google'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      expect(find.text('Akun Google'), findsOneWidget);
    });
  }

  // ---------------------------------------------------------
  // 5. ProfessionalCompletionScreen: `str_sip_sudah_terdaftar`.
  // ---------------------------------------------------------
  testWidgets(
      'complete-professional: str_sip_sudah_terdaftar tampilkan aturan, tanpa kolom password',
      (tester) async {
    final requests = <http.Request>[];
    final api = MalvaApiClient(
      baseUrl: 'http://backend.test',
      httpClient: _FakeClient((request) async {
        requests.add(request);
        if (request.method == 'POST' &&
            request.url.path == '/v1/auth/complete-professional') {
          return _json({
            'error': 'Nomor STR atau SIP ini sudah terdaftar pada akun profesional lain.',
            'code': 'str_sip_sudah_terdaftar',
          }, status: 409);
        }
        return _json(const {});
      }),
    );
    final container = _container(api, session: _proSession);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildMalvaTheme(),
        home: ProfessionalCompletionScreen(
          session: _proSession,
          apiClient: api,
          onCompleted: (_) {},
        ),
      ),
    ));
    await tester.pumpAndSettle();

    // Tidak ada kolom "password akun lama" lagi.
    expect(find.textContaining(RegExp('password', caseSensitive: false)),
        findsNothing);

    // Isi STR & SIP (name sudah ter-prefill dari sesi).
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(1), 'STR-DUP-1');
    await tester.enterText(fields.at(2), 'SIP-DUP-1');
    await tester.tap(find.widgetWithText(FilledButton, 'Simpan & Lanjutkan'));
    await tester.pumpAndSettle();

    // Request benar-benar dikirim ke endpoint completion.
    expect(
      requests.any((r) =>
          r.method == 'POST' &&
          r.url.path == '/v1/auth/complete-professional'),
      isTrue,
    );

    // Pesan aturan STR/SIP muncul (inline errorText dan/atau SnackBar).
    expect(
      find.textContaining('Satu STR/SIP hanya boleh untuk satu akun'),
      findsWidgets,
    );
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
