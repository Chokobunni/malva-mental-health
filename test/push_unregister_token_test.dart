import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:malva_mental_health/src/services/malva_api_client.dart';
import 'package:malva_mental_health/src/services/push_notification_service.dart';

// ============================================================
// Cabut token FCM perangkat saat logout (feat(notify)).
//
// unregisterDeviceToken() harus:
//   1. mengambil token FCM perangkat (di sini lewat provider yang disuntik),
//   2. memanggil DELETE /v1/device-tokens dengan body {"token": ...},
//   3. selalu memanggil resetRegistration() (registeredUserId kembali null),
//      termasuk ketika jaringan gagal — logout tidak boleh terhalang.
// ============================================================

/// Klien HTTP palsu (pola repo): merekam setiap request.
class _RecordingClient extends http.BaseClient {
  _RecordingClient(this.handler);

  final FutureOr<http.Response> Function(http.Request request) handler;
  final List<http.Request> requests = <http.Request>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final body = request is http.Request ? request.body : '';
    final replay = http.Request(request.method, request.url)
      ..headers.addAll(request.headers)
      ..body = body;
    requests.add(replay);
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

http.Response _ok() => http.Response(
      jsonEncode({'status': 'disabled'}),
      200,
      headers: {'content-type': 'application/json'},
    );

PushNotificationService _service({
  required MalvaApiClient apiClient,
  required Future<String?> Function() tokenProvider,
}) {
  return PushNotificationService(
    apiClient: apiClient,
    navigatorKey: GlobalKey<NavigatorState>(),
    fcmTokenProvider: tokenProvider,
  );
}

void main() {
  test('unregisterDeviceToken memanggil DELETE /v1/device-tokens lalu reset',
      () async {
    final client = _RecordingClient((_) async => _ok());
    final api = MalvaApiClient(
      baseUrl: 'http://backend.test',
      httpClient: client,
    );
    final service = _service(
      apiClient: api,
      tokenProvider: () async => 'fcm_token_123',
    );

    await service.unregisterDeviceToken('access_token_abc');

    expect(client.requests, hasLength(1));
    final req = client.requests.single;
    expect(req.method, 'DELETE');
    expect(req.url.path, '/v1/device-tokens');
    expect(req.headers['Authorization'], 'Bearer access_token_abc');
    expect(jsonDecode(req.body)['token'], 'fcm_token_123');

    // resetRegistration selalu dijalankan di akhir.
    expect(service.registeredUserId, isNull);
  });

  test('access token kosong: tidak ada request, tetap reset', () async {
    final client = _RecordingClient((_) async => _ok());
    final api = MalvaApiClient(
      baseUrl: 'http://backend.test',
      httpClient: client,
    );
    final service = _service(
      apiClient: api,
      tokenProvider: () async => 'fcm_token_123',
    );

    await service.unregisterDeviceToken(null);
    await service.unregisterDeviceToken('');

    expect(client.requests, isEmpty);
    expect(service.registeredUserId, isNull);
  });

  test('token FCM kosong: tidak ada request, tetap reset', () async {
    final client = _RecordingClient((_) async => _ok());
    final api = MalvaApiClient(
      baseUrl: 'http://backend.test',
      httpClient: client,
    );
    final service = _service(
      apiClient: api,
      tokenProvider: () async => null,
    );

    await service.unregisterDeviceToken('access_token_abc');

    expect(client.requests, isEmpty);
    expect(service.registeredUserId, isNull);
  });

  test('kegagalan jaringan TIDAK melempar dan tetap reset', () async {
    final client = _RecordingClient((_) async => http.Response(
          jsonEncode({'error': 'internal server error'}),
          500,
          headers: {'content-type': 'application/json'},
        ));
    final api = MalvaApiClient(
      baseUrl: 'http://backend.test',
      httpClient: client,
    );
    final service = _service(
      apiClient: api,
      tokenProvider: () async => 'fcm_token_123',
    );

    // Tidak boleh melempar — logout tidak terhalang kegagalan jaringan.
    await service.unregisterDeviceToken('access_token_abc');

    // Request tetap dicoba sekali, lalu reset dijalankan.
    expect(client.requests, hasLength(1));
    expect(service.registeredUserId, isNull);
  });
}
