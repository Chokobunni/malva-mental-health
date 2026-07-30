import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:malva_mental_health/src/models.dart';
import 'package:malva_mental_health/src/services/malva_api_client.dart';

void main() {
  test('register parses backend auth response', () async {
    final api = MalvaApiClient(
      baseUrl: 'http://backend.test',
      httpClient: _FakeClient((request) async {
        expect(request.url.path, '/v1/auth/register');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['role'], 'patient');
        return http.Response(
          jsonEncode({
            'user': {
              'id': 'user_1',
              'email': 'pasien@malva.app',
              'role': 'patient',
              'display_name': 'Pasien Malva',
            },
            'access_token': 'token_123',
            'refresh_token': 'refresh_123',
          }),
          201,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    final result = await api.register(
      role: UserRole.patient,
      email: 'pasien@malva.app',
      password: 'Malva1234',
      displayName: 'Pasien Malva',
    );

    expect(result.userId, 'user_1');
    expect(result.accessToken, 'token_123');
    expect(result.refreshToken, 'refresh_123');
    expect(result.role, UserRole.patient);
  });

  test('refreshSession posts refresh token and parses rotated tokens',
      () async {
    final api = MalvaApiClient(
      baseUrl: 'http://backend.test',
      httpClient: _FakeClient((request) async {
        expect(request.url.path, '/v1/auth/refresh');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['refresh_token'], 'refresh_old');
        return http.Response(
          jsonEncode({
            'user': {
              'id': 'user_1',
              'email': 'pasien@malva.app',
              'role': 'patient',
              'display_name': 'Pasien Malva',
            },
            'access_token': 'token_new',
            'refresh_token': 'refresh_new',
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    final result = await api.refreshSession(refreshToken: 'refresh_old');

    expect(result.accessToken, 'token_new');
    expect(result.refreshToken, 'refresh_new');
  });

  test('submitScreening parses backend screening response', () async {
    final api = MalvaApiClient(
      baseUrl: 'http://backend.test',
      httpClient: _FakeClient((request) async {
        expect(request.url.path, '/v1/screenings');
        expect(request.headers['authorization'], 'Bearer token_123');
        return http.Response(
          jsonEncode({
            'screening': {
              'id': 'screening_1',
              'overall_level': 'moderate',
              'crisis_flag': false,
            },
          }),
          201,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    final result = await api.submitScreening(
      accessToken: 'token_123',
      phq9Answers: const [1, 1, 1, 1, 1, 0, 0, 0, 0],
      gad7Answers: const [2, 2, 2, 2, 2, 0, 0],
      isInitial: true,
      source: 'test',
    );

    expect(result.id, 'screening_1');
    expect(result.overallLevel, 'moderate');
    expect(result.crisisFlag, isFalse);
  });

  test('realtimeUri switches https API URL to wss', () {
    final api = MalvaApiClient(baseUrl: 'https://api.malva.id');

    final uri = api.realtimeUri('token_123');

    expect(uri.toString(),
        'wss://api.malva.id/v1/realtime/ws?access_token=token_123');
  });

  test('listScreenings parses PHQ-9 and GAD-7 history', () async {
    final api = MalvaApiClient(
      baseUrl: 'http://backend.test',
      httpClient: _FakeClient((request) async {
        expect(request.url.path, '/v1/screenings');
        expect(request.url.queryParameters['limit'], '10');
        expect(request.headers['authorization'], 'Bearer token_123');
        return http.Response(
          jsonEncode({
            'screenings': [
              {
                'id': 'screening_1',
                'patient_id': 'patient_1',
                'overall_level': 'moderate',
                'crisis_flag': false,
                'created_at': '2026-07-13T01:00:00Z',
                'bundle': {
                  'phq9': {
                    'type': 'phq9',
                    'score': 8,
                    'max_score': 27,
                    'level': 'mild',
                    'summary': 'Ringan',
                    'crisis_flag': false,
                  },
                  'gad7': {
                    'type': 'gad7',
                    'score': 12,
                    'max_score': 21,
                    'level': 'moderate',
                    'summary': 'Sedang',
                    'crisis_flag': false,
                  },
                },
              }
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    final sessions = await api.listScreenings(
      accessToken: 'token_123',
      limit: 10,
    );

    expect(sessions, hasLength(1));
    expect(sessions.single.phq9.score, 8);
    expect(sessions.single.gad7.level, 'moderate');
  });

  test('linkProfessional posts professional id and parses link', () async {
    final api = MalvaApiClient(
      baseUrl: 'http://backend.test',
      httpClient: _FakeClient((request) async {
        expect(request.url.path, '/v1/patient-professional-links');
        expect(request.headers['authorization'], 'Bearer token_123');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['professional_id'], '1234567890123456');
        return http.Response(
          jsonEncode({
            'link': {
              'patient_id': 'patient_1',
              'professional_user_id': 'professional_1',
              'professional_id': '1234567890123456',
              'patient_display_name': 'Pasien Malva',
              'professional_display_name': 'dr. Malva',
              'status': 'active',
            },
          }),
          201,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    final link = await api.linkProfessional(
      accessToken: 'token_123',
      professionalId: '1234567890123456',
    );

    expect(link.professionalId, '1234567890123456');
    expect(link.professionalDisplayName, 'dr. Malva');
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
      reasonPhrase: response.reasonPhrase,
      request: replay,
    );
  }
}
