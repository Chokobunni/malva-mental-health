import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:malva_mental_health/src/models.dart';
import 'package:malva_mental_health/src/providers/auth_providers.dart';
import 'package:malva_mental_health/src/screens/my_care_screen.dart';
import 'package:malva_mental_health/src/services/malva_api_client.dart';
import 'package:malva_mental_health/src/theme.dart';

// ============================================================
// CONSENT KATEGORI "THERAPY RECORD" DI MANAGE DATA
//
// Yang dikunci:
//   - Toggle "Therapy Record (Psikologis)" tampil bersama kategori lain.
//   - Nilai awalnya mengikuti server (opt-in: default MATI).
//   - Perubahan pasien ikut terkirim di payload PUT /v1/privacy/consents
//     sebagai `share_therapy_records`.
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

/// Fake backend consent: GET mengembalikan izin awal, PUT merekam payload.
class _ConsentBackend {
  _ConsentBackend({this.shareTherapyRecords = false});

  final bool shareTherapyRecords;
  Map<String, dynamic>? lastPutBody;
  int putCalls = 0;

  http.Client client() {
    return _FakeClient((request) async {
      final key = '${request.method} ${request.url.path}';
      if (key == 'GET /v1/privacy/consents') {
        return _json({
          'consent': {
            'professional_id': 'user_pro_1',
            'share_screenings': true,
            'share_mood_diary': false,
            'share_medications': false,
            'share_timeline': false,
            'share_health_record': false,
            'share_goals': false,
            'share_therapy_records': shareTherapyRecords,
          },
        });
      }
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
      home: const Scaffold(
        body: ManageDataSheet(
          professionalId: 'user_pro_1',
          professionalName: 'dr. Hafid',
        ),
      ),
    ),
  );
}

Finder _therapyToggle() =>
    find.widgetWithText(SwitchListTile, 'Therapy Record (Psikologis)');

bool _switchValue(WidgetTester tester, Finder toggle) =>
    tester.widget<SwitchListTile>(toggle).value;

void main() {
  testWidgets(
      'toggle Therapy Record tampil & nilai awal mengikuti server (mati)',
      (tester) async {
    final backend = _ConsentBackend(shareTherapyRecords: false);
    final api = MalvaApiClient(
        baseUrl: 'http://backend.test', httpClient: backend.client());

    await tester.pumpWidget(_wrap(api));
    await tester.pumpAndSettle();

    expect(_therapyToggle(), findsOneWidget,
        reason: 'kategori Therapy Record harus ada di Manage Data');
    expect(_switchValue(tester, _therapyToggle()), isFalse,
        reason: 'default opt-in: izin mati sampai pasien menyalakannya');
    // Kategori lain tetap ada (tidak ada yang hilang).
    expect(
        find.widgetWithText(SwitchListTile, 'Health Record'), findsOneWidget);
    expect(find.widgetWithText(SwitchListTile, 'Timeline'), findsOneWidget);
  });

  testWidgets(
      'nilai awal mengikuti server (hidup) lalu ikut terkirim saat disimpan',
      (tester) async {
    final backend = _ConsentBackend(shareTherapyRecords: true);
    final api = MalvaApiClient(
        baseUrl: 'http://backend.test', httpClient: backend.client());

    await tester.pumpWidget(_wrap(api));
    await tester.pumpAndSettle();

    expect(_switchValue(tester, _therapyToggle()), isTrue,
        reason: 'nilai awal harus dari server, bukan default lokal');

    // Pasien mematikan izin lalu menyimpan.
    await tester.tap(_therapyToggle());
    await tester.pumpAndSettle();
    expect(_switchValue(tester, _therapyToggle()), isFalse);

    await tester.tap(find.widgetWithText(FilledButton, 'Simpan'));
    await tester.pumpAndSettle();

    expect(backend.putCalls, 1);
    expect(backend.lastPutBody?['share_therapy_records'], isFalse,
        reason: 'perubahan toggle harus ikut terkirim di payload');
    expect(backend.lastPutBody?['share_screenings'], isTrue,
        reason: 'kategori lain tetap dikirim apa adanya');
  });

  testWidgets('menyalakan izin mengirim share_therapy_records=true',
      (tester) async {
    final backend = _ConsentBackend(shareTherapyRecords: false);
    final api = MalvaApiClient(
        baseUrl: 'http://backend.test', httpClient: backend.client());

    await tester.pumpWidget(_wrap(api));
    await tester.pumpAndSettle();

    await tester.tap(_therapyToggle());
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Simpan'));
    await tester.pumpAndSettle();

    expect(backend.lastPutBody?['share_therapy_records'], isTrue);
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
      request: request,
    );
  }
}
