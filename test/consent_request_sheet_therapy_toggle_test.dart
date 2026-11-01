import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:malva_mental_health/src/models.dart';
import 'package:malva_mental_health/src/providers/providers.dart';
import 'package:malva_mental_health/src/screens/booking/consent_request_sheet.dart';
import 'package:malva_mental_health/src/services/malva_api_client.dart';
import 'package:malva_mental_health/src/theme.dart';

// ============================================================
// W2 — Toggle "Therapy History" pada sheet consent paket continuous.
//
// Yang dikunci:
//   1. Sheet menampilkan toggle "Therapy History" (worksheet CBT/DBT).
//   2. Default MATI (opt-in eksplisit, bukan opt-out diam-diam).
//   3. Saat pasien menyalakannya lalu menyimpan, payload PUT
//      /v1/privacy/consents mengirim `share_therapy_records: true`.
// ============================================================

const _patientSession = AuthSession(
  role: UserRole.patient,
  identifier: 'pasien@malva.app',
  displayName: 'Pasien',
  backendUserId: 'user_pasien_1',
  accessToken: 'token_test',
);

http.Response _json(Object body, {int status = 200}) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    );

/// Fake backend consent: hanya menangani PUT (sheet tidak melakukan GET).
class _ConsentBackend {
  int putCalls = 0;
  Map<String, dynamic>? lastPutBody;

  http.Client client() {
    return _FakeClient((request) async {
      final key = '${request.method} ${request.url.path}';
      if (key == 'PUT /v1/privacy/consents') {
        putCalls++;
        lastPutBody = jsonDecode(request.body) as Map<String, dynamic>;
        return _json({
          'consent': {
            'professional_id': 'user_pro_1',
            ...lastPutBody!,
          },
        });
      }
      return _json({'error': 'unexpected $key'}, status: 404);
    });
  }
}

Widget _wrap(MalvaApiClient api) {
  final container = ProviderContainer(
    overrides: [
      apiClientProvider.overrideWithValue(api),
      authStateProvider.overrideWith((ref) {
        final notifier = AuthNotifier()..setSession(_patientSession);
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
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () => showConsentRequestSheet(
                context: context,
                professionalId: 'user_pro_1',
              ),
              child: const Text('Buka'),
            ),
          ),
        ),
      ),
    ),
  );
}

/// Switch yang berada di baris toggle "Therapy History".
Finder _therapySwitch() {
  final row = find
      .ancestor(of: find.text('Therapy History'), matching: find.byType(Row))
      .first;
  return find.descendant(of: row, matching: find.byType(Switch));
}

void main() {
  setUp(() {
    // setContinuousSupportConsent menulis ke secure storage — pakai mock.
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
  });

  testWidgets('sheet menampilkan toggle Therapy History (default mati)',
      (tester) async {
    final backend = _ConsentBackend();
    final api = MalvaApiClient(
        baseUrl: 'http://backend.test', httpClient: backend.client());

    await tester.pumpWidget(_wrap(api));
    await tester.tap(find.text('Buka'));
    await tester.pumpAndSettle();

    expect(find.text('Therapy History'), findsOneWidget,
        reason: 'toggle Therapy History harus ada di sheet consent');
    expect(tester.widget<Switch>(_therapySwitch()).value, isFalse,
        reason: 'default opt-in: izin mati sampai pasien menyalakannya');
  });

  testWidgets('menyalakan Therapy History mengirim share_therapy_records=true',
      (tester) async {
    final backend = _ConsentBackend();
    final api = MalvaApiClient(
        baseUrl: 'http://backend.test', httpClient: backend.client());

    await tester.pumpWidget(_wrap(api));
    await tester.tap(find.text('Buka'));
    await tester.pumpAndSettle();

    // Nyalakan toggle Therapy History (gulir dulu agar terlihat).
    final therapySwitch = _therapySwitch();
    await tester.ensureVisible(therapySwitch);
    await tester.pumpAndSettle();
    await tester.tap(therapySwitch);
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(_therapySwitch()).value, isTrue);

    // Simpan.
    final saveButton = find.widgetWithText(FilledButton, 'Allow & Continue');
    await tester.ensureVisible(saveButton);
    await tester.pumpAndSettle();
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    expect(backend.putCalls, 1);
    expect(backend.lastPutBody?['share_therapy_records'], isTrue,
        reason: 'toggle Therapy History ON harus terkirim di payload PUT');
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
      request: replay,
    );
  }
}
