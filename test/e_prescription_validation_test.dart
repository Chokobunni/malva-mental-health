import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:malva_mental_health/src/models.dart';
import 'package:malva_mental_health/src/screens/portal/e_prescription_screen.dart';
import 'package:malva_mental_health/src/services/malva_api_client.dart';
import 'package:malva_mental_health/src/theme.dart';

// ============================================================
// REGRESI: "Nama obat tidak boleh kosong" padahal nama sudah diisi.
//
// Akar masalah: `_ItemEditorState` hanya menulis `_name.text`/`_dosage.text` ke
// `widget.draft` saat `dispose()`. Validasi `_submit` membaca `draft.name` yang
// masih kosong -> menolak resep walau field sudah diisi. Perbaikan: `_sync()`
// menulis ke draft pada setiap perubahan field.
//
// Test ini gagal SEBELUM perbaikan (muncul "Nama obat tidak boleh kosong").
// ============================================================

const _proSession = AuthSession(
  role: UserRole.professional,
  identifier: 'psikiater@malva.app',
  displayName: 'dr. Sp.KJ',
  backendUserId: 'user_pro_1',
  accessToken: 'token_test',
);

const _link = BackendPatientProfessionalLink(
  patientId: 'user_pasien_1',
  professionalUserId: 'user_pro_1',
  professionalId: 'pro_1',
  patientDisplayName: 'Pasien A',
  professionalDisplayName: 'dr. Sp.KJ',
  status: 'active',
);

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

void main() {
  testWidgets(
      'isi nama obat lalu submit tidak memunculkan '
      '"Nama obat tidak boleh kosong"', (tester) async {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = MalvaApiClient(
      baseUrl: 'http://backend.test',
      httpClient: _FakeClient((request) async {
        if (request.method == 'POST' &&
            request.url.path == '/v1/e-prescriptions') {
          return _json({
            'prescription': {
              'id': 'rx_1',
              'status': 'issued',
              'items': <Object>[],
            },
          });
        }
        return _json({'error': 'unexpected'}, status: 404);
      }),
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: buildMalvaTheme(),
          home: EPrescriptionFormScreen(
            session: _proSession,
            apiClient: api,
            links: const [_link],
            preselectedPatientId: 'user_pasien_1',
            preselectedPatientName: 'Pasien A',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Field "Nama obat" adalah TextField pertama (dropdown pasien bukan
    // TextField).
    final nameField = find.byType(TextField).at(0);
    await tester.ensureVisible(nameField);
    await tester.enterText(nameField, 'Quetiapine');
    await tester.pump();

    await tester.enterText(find.byKey(const Key('rx-dose')), '10');
    final submit = find.text('Lanjut Atur Jadwal Resep');
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();

    expect(find.text('Nama obat tidak boleh kosong.'), findsNothing,
        reason: 'nama sudah diisi; validasi tidak boleh gagal karena draft '
            'belum tersinkron dari controller');
    expect(find.text('Atur Rutinitas'), findsOneWidget);
  });
}
