import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:malva_mental_health/src/services/malva_api_client.dart';

// ============================================================
// W6 — REGRESI: `getCrisisIncidentLog` harus mengirim `limit` sebagai QUERY
// PARAMETER sungguhan, bukan menempelkannya ke path.
//
// Temuan QA: implementasi awal memakai
//   _send('GET', '/v1/crisis-incident-log?limit=$limit', ...)
// padahal `_send` memakai `Uri.replace(path: ...)` yang meng-escape '?' menjadi
// %3F. Akibatnya URL menjadi `/v1/crisis-incident-log%3Flimit=50`; backend
// tidak mencocokkan rute itu dan malah mengembalikan halaman HTML status (200),
// sehingga layar Crisis Incident Log SELALU gagal memuat.
//
// Test ini mengunci bentuk URL yang benar. GAGAL pada implementasi buggy,
// LULUS setelah `getCrisisIncidentLog` memakai `_sendUri` + `queryParameters`.
// ============================================================

class _CapturingClient extends http.BaseClient {
  _CapturingClient(this.handler);

  final FutureOr<http.Response> Function(http.Request request) handler;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final replay = http.Request(request.method, request.url)
      ..headers.addAll(request.headers);
    final response = await handler(replay);
    return http.StreamedResponse(
      Stream.value(response.bodyBytes),
      response.statusCode,
      headers: response.headers,
      request: replay,
    );
  }
}

void main() {
  test(
      'getCrisisIncidentLog mengirim limit sebagai query parameter, bukan path',
      () async {
    Uri? captured;
    final api = MalvaApiClient(
      baseUrl: 'http://backend.test',
      httpClient: _CapturingClient((request) async {
        captured = request.url;
        return http.Response(
          jsonEncode({
            'items': <dynamic>[],
            'counts': {'total': 0, 'unresolved': 0},
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    await api.getCrisisIncidentLog(accessToken: 'token_test', limit: 50);

    expect(captured, isNotNull);
    // Path TIDAK boleh mengandung query ter-encode (%3F) maupun '?'.
    expect(captured!.path, '/v1/crisis-incident-log',
        reason: 'path tidak boleh memuat query ter-encode (%3F)');
    // limit HARUS jadi query parameter sungguhan.
    expect(captured!.queryParameters['limit'], '50',
        reason: 'limit harus dikirim sebagai query parameter, bukan di path');
  });
}
