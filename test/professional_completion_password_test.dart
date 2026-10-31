import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:malva_mental_health/src/models.dart';
import 'package:malva_mental_health/src/providers/auth_providers.dart';
import 'package:malva_mental_health/src/screens/professional_completion_screen.dart';
import 'package:malva_mental_health/src/services/malva_api_client.dart';
import 'package:malva_mental_health/src/theme.dart';

// ============================================================
// PELENGKAPAN PROFIL PROFESIONAL — PASSWORD WAJIB.
// Profesional yang masuk lewat Google harus menetapkan password agar bisa
// login berikutnya memakai nomor STR. Test ini memakai klien HTTP palsu +
// override apiClientProvider (pola test/google_account_card_test.dart).
// ============================================================

const _session = AuthSession(
  role: UserRole.professional,
  identifier: 'hanami@malva.app',
  displayName: 'Hanami',
  backendUserId: 'user_pro_1',
  accessToken: 'token_test',
  refreshToken: 'refresh_test',
);

/// Klien HTTP palsu: mencatat body permintaan lalu membalas 200.
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

Widget _wrap(MalvaApiClient api, void Function(AuthSession) onCompleted) {
  return ProviderScope(
    overrides: [apiClientProvider.overrideWithValue(api)],
    child: MaterialApp(
      theme: buildMalvaTheme(),
      home: ProfessionalCompletionScreen(
        session: _session,
        apiClient: api,
        onCompleted: onCompleted,
      ),
    ),
  );
}

/// Layar tinggi agar seluruh isi ListView (termasuk kolom password dan tombol
/// simpan di bawah) ikut dibangun — ListView bersifat lazy.
void _useTallScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// Urutan TextField di layar: 0 nama, 1 STR, 2 SIP, 3 password, 4 konfirmasi.
Future<void> _fillRequiredExceptPassword(WidgetTester tester) async {
  final fields = find.byType(TextField);
  await tester.enterText(fields.at(0), 'dr. Hanami, Sp.KJ');
  await tester.enterText(fields.at(1), 'STR-1234567890');
  await tester.enterText(fields.at(2), 'SIP-1234567890');
}

void main() {
  testWidgets('menolak password kosong dan tidak memanggil API',
      (tester) async {
    _useTallScreen(tester);
    final bodies = <String>[];
    final api = MalvaApiClient(
      httpClient: _FakeClient((request) {
        bodies.add(request.body);
        return http.Response(
          jsonEncode({
            'user': {'id': 'user_pro_1', 'email': 'hanami@malva.app'}
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
      baseUrl: 'http://localhost:8080',
    );
    await tester.pumpWidget(_wrap(api, (_) {}));
    await tester.pumpAndSettle();

    await _fillRequiredExceptPassword(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Simpan & Lanjutkan'));
    await tester.pump();

    expect(find.text('Password wajib diisi.'), findsOneWidget);
    expect(bodies, isEmpty,
        reason: 'API tidak boleh dipanggil saat password kosong');
  });

  testWidgets('menolak konfirmasi password yang berbeda', (tester) async {
    _useTallScreen(tester);
    final bodies = <String>[];
    final api = MalvaApiClient(
      httpClient: _FakeClient((request) {
        bodies.add(request.body);
        return http.Response(
          jsonEncode({
            'user': {'id': 'user_pro_1', 'email': 'hanami@malva.app'}
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
      baseUrl: 'http://localhost:8080',
    );
    await tester.pumpWidget(_wrap(api, (_) {}));
    await tester.pumpAndSettle();

    await _fillRequiredExceptPassword(tester);
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(3), 'RahasiaKlinik123!');
    await tester.enterText(fields.at(4), 'BedaPassword123!');
    await tester.tap(find.widgetWithText(FilledButton, 'Simpan & Lanjutkan'));
    await tester.pump();

    expect(find.text('Konfirmasi password tidak sama.'), findsOneWidget);
    expect(bodies, isEmpty,
        reason: 'API tidak boleh dipanggil saat konfirmasi berbeda');
  });

  testWidgets('mengirim password ke API saat form valid', (tester) async {
    _useTallScreen(tester);
    final bodies = <String>[];
    final api = MalvaApiClient(
      httpClient: _FakeClient((request) {
        bodies.add(request.body);
        return http.Response(
          jsonEncode({
            'user': {
              'id': 'user_pro_1',
              'email': 'hanami@malva.app',
              'display_name': 'dr. Hanami, Sp.KJ',
            }
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
      baseUrl: 'http://localhost:8080',
    );
    AuthSession? completed;
    await tester.pumpWidget(_wrap(api, (updated) => completed = updated));
    await tester.pumpAndSettle();

    await _fillRequiredExceptPassword(tester);
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(3), 'RahasiaKlinik123!');
    await tester.enterText(fields.at(4), 'RahasiaKlinik123!');
    await tester.tap(find.widgetWithText(FilledButton, 'Simpan & Lanjutkan'));
    await tester.pumpAndSettle();

    expect(bodies, hasLength(1));
    final body = jsonDecode(bodies.single) as Map<String, dynamic>;
    expect(body['password'], 'RahasiaKlinik123!');
    expect(body['str_number'], 'STR-1234567890');
    expect(body['sip_number'], 'SIP-1234567890');
    expect(completed, isNotNull);
    expect(completed!.role, UserRole.professional);
  });
}
