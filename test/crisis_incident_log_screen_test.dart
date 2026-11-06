import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:malva_mental_health/src/models.dart';
import 'package:malva_mental_health/src/screens/portal/crisis_incident_log_screen.dart';
import 'package:malva_mental_health/src/services/malva_api_client.dart';
import 'package:malva_mental_health/src/theme.dart';

// ============================================================
// W6 — Crisis Incident Log (frontend): SATU permintaan untuk seluruh pasien,
// sumber gabungan SOS + Screening, dan aksi "Tandai sudah ditangani" hanya
// untuk insiden SOS yang belum ditangani (tanpa form catatan wajib).
// ============================================================

const _proSession = AuthSession(
  role: UserRole.professional,
  identifier: 'prof_andi',
  displayName: 'Andi Wijaya, M.Psi',
  backendUserId: 'prof_andi',
  accessToken: 'token_test',
);

http.Response _json(Object body, {int status = 200}) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    );

class _LogBackend {
  int logCalls = 0;
  int resolveCalls = 0;
  bool resolved = false;

  http.Client client() {
    return _FakeClient((request) async {
      if (request.url.path == '/v1/crisis-incidents/sos1/resolve') {
        expect(request.method, 'POST');
        expect(jsonDecode(request.body), {'resolution_notes': ''});
        resolveCalls++;
        resolved = true;
        return _json({
          'incident': {'id': 'sos1', 'status': 'resolved'}
        });
      }
      // Cocokkan berdasarkan prefiks path agar test ini menguji PERILAKU LAYAR
      // (jumlah permintaan + render), bukan kebenaran encoding URL. Kebenaran
      // URL `getCrisisIncidentLog` diuji terpisah di
      // malva_api_client_crisis_log_url_test.dart.
      if (request.url.path.startsWith('/v1/crisis-incident-log')) {
        logCalls++;
        return _json({
          'items': [
            {
              'id': 'sos1',
              'source': 'sos',
              'patient_id': 'p_ami',
              'patient_name': 'Ami',
              'title': 'SOS darurat',
              'detail': 'sos_button',
              'severity': 'crisis',
              'created_at': '2026-10-22T10:00:00+07:00',
              'resolved_at': resolved ? '2026-11-06T10:00:00+07:00' : null,
              'resolution_notes': '',
            },
            {
              'id': 'scr1',
              'source': 'screening',
              'patient_id': 'p_dhiva',
              'patient_name': 'Dhiva',
              'title': 'Screening krisis',
              'detail': 'phq9 20 (Berat)',
              'severity': 'crisis',
              'created_at': '2026-10-21T09:00:00+07:00',
              'resolved_at': null,
              'resolution_notes': '',
            },
          ],
          'counts': {'total': 2, 'unresolved': resolved ? 0 : 1},
        });
      }
      return _json({'error': 'unexpected ${request.url.path}'}, status: 404);
    });
  }
}

Widget _wrap(MalvaApiClient api) {
  return ProviderScope(
    child: MaterialApp(
      theme: buildMalvaTheme(),
      home: CrisisIncidentLogScreen(session: _proSession, apiClient: api),
    ),
  );
}

void main() {
  testWidgets('memuat satu permintaan & menampilkan sumber SOS + Screening',
      (tester) async {
    final backend = _LogBackend();
    final api = MalvaApiClient(
        baseUrl: 'http://backend.test', httpClient: backend.client());

    await tester.pumpWidget(_wrap(api));
    await tester.pumpAndSettle();

    // Inti W6: TEPAT satu panggilan ke endpoint feed (bukan N per pasien).
    expect(backend.logCalls, 1,
        reason: 'layar harus memakai SATU permintaan untuk semua pasien');

    // Kedua pasien dari dua sumber berbeda tampil dalam satu respons.
    expect(find.text('Ami'), findsOneWidget);
    expect(find.text('Dhiva'), findsOneWidget);
    expect(find.text('SOS'), findsWidgets);
    expect(find.text('Screening'), findsWidgets);
  });

  testWidgets('tombol "Tandai sudah ditangani" hanya untuk insiden SOS',
      (tester) async {
    final backend = _LogBackend();
    final api = MalvaApiClient(
        baseUrl: 'http://backend.test', httpClient: backend.client());

    await tester.pumpWidget(_wrap(api));
    await tester.pumpAndSettle();

    // Hanya kartu SOS (belum ditangani) yang punya tombol resolve; kartu
    // screening tidak. Tidak ada form catatan wajib di mana pun.
    expect(find.widgetWithText(OutlinedButton, 'Tandai sudah ditangani'),
        findsOneWidget,
        reason: 'aksi resolve opsional hanya untuk insiden SOS');
    expect(find.byType(TextField), findsNothing,
        reason: 'tidak boleh ada form catatan wajib per-item');
  });

  testWidgets('screening history is not an unresolved SOS task',
      (tester) async {
    final backend = _LogBackend();
    final api = MalvaApiClient(
        baseUrl: 'http://backend.test', httpClient: backend.client());
    await tester.pumpWidget(_wrap(api));
    await tester.pumpAndSettle();

    expect(find.textContaining('Belum ditangani'), findsNothing);
    expect(find.textContaining('belum ditangani'), findsNothing);
    expect(find.text('Riwayat screening'), findsOneWidget);
    expect(find.text('Perlu tindak lanjut'), findsOneWidget);
    expect(find.text('2 catatan • 1 SOS perlu tindak lanjut'), findsOneWidget);
    expect(backend.resolveCalls, 0,
        reason: 'displaying a record must never resolve it automatically');
  });

  testWidgets('SOS can be confirmed without entering per-item feedback',
      (tester) async {
    final backend = _LogBackend();
    final api = MalvaApiClient(
        baseUrl: 'http://backend.test', httpClient: backend.client());
    await tester.pumpWidget(_wrap(api));
    await tester.pumpAndSettle();
    await tester
        .tap(find.widgetWithText(OutlinedButton, 'Tandai sudah ditangani'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    expect(backend.resolveCalls, 0);
    await tester
        .tap(find.widgetWithText(FilledButton, 'Tandai sudah ditangani'));
    await tester.pumpAndSettle();
    expect(backend.resolveCalls, 1);
    expect(backend.logCalls, 2);
    expect(find.text('Riwayat screening'), findsOneWidget);
    expect(find.text('Sudah ditangani'), findsOneWidget);
    expect(find.text('Perlu tindak lanjut'), findsNothing);
    expect(find.widgetWithText(OutlinedButton, 'Tandai sudah ditangani'),
        findsNothing);
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
