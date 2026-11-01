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

  http.Client client() {
    return _FakeClient((request) async {
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
              'resolved_at': null,
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
          'counts': {'total': 2, 'unresolved': 2},
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
