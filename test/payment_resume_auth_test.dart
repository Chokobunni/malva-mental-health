import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:malva_mental_health/src/services/malva_api_client.dart';

http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status,
        headers: {'content-type': 'application/json'});
Map<String, Object> _auth(String account) => {
      'user': {
        'id': account,
        'email': '$account@example.test',
        'role': 'patient',
        'display_name': account
      },
      'access_token': 'fresh-$account',
      'refresh_token': 'rotated-$account'
    };

void main() {
  test(
      'concurrent resume requests share refresh and both retry the fresh token',
      () async {
    final pending = Completer<http.Response>();
    final started = Completer<void>();
    var refreshes = 0;
    final api = MalvaApiClient(
        baseUrl: 'http://backend.test',
        httpClient: MockClient((request) async {
          if (request.url.path == '/v1/auth/refresh') {
            refreshes++;
            if (!started.isCompleted) started.complete();
            return pending.future;
          }
          return request.headers['authorization'] == 'Bearer fresh-A'
              ? _json({'bookings': []})
              : _json({'error': 'unauthorized'}, 401);
        }));
    api.setRefreshToken('refresh-A');
    final requests = Future.wait([
      api.listBookings(accessToken: 'expired-A'),
      api.listBookings(accessToken: 'expired-A')
    ]);
    await started.future;
    await Future<void>.delayed(Duration.zero);
    pending.complete(_json(_auth('A')));
    await requests;
    expect(refreshes, 1);
  });
  test(
      'payment resume refreshes once and reuses the fresh access token for follow-on payment',
      () async {
    final headers = <String?>[];
    var refreshes = 0;
    final api = MalvaApiClient(
        baseUrl: 'http://backend.test',
        httpClient: MockClient((request) async {
          if (request.url.path == '/v1/auth/refresh') {
            refreshes++;
            return _json(_auth('A'));
          }
          headers.add(request.headers['authorization']);
          if (request.headers['authorization'] != 'Bearer fresh-A')
            return _json({'error': 'unauthorized'}, 401);
          return request.url.path == '/v1/bookings'
              ? _json({'bookings': []})
              : _json({
                  'payment': {
                    'id': 'payment',
                    'booking_id': 'booking',
                    'reference': 'REF-1',
                    'status': 'pending'
                  },
                  'breakdown': {}
                });
        }));
    api.setRefreshToken('refresh-A');
    await api.listBookings(accessToken: 'expired-A');
    await api.createPayment(
        accessToken: 'expired-A', bookingId: 'booking', paymentMethod: 'qris');
    expect(refreshes, 1);
    expect(headers, ['Bearer expired-A', 'Bearer fresh-A', 'Bearer fresh-A']);
  });

  test('revoked refresh terminates payment resume without awaiting itself',
      () async {
    var refreshes = 0;
    final api = MalvaApiClient(
        baseUrl: 'http://backend.test',
        httpClient: MockClient((request) async {
          if (request.url.path == '/v1/auth/refresh') refreshes++;
          return _json({'error': 'unauthorized'}, 401);
        }));
    api.setRefreshToken('revoked');
    await expectLater(
        api.listBookings(accessToken: 'expired').timeout(
            const Duration(milliseconds: 100),
            onTimeout: () => throw StateError('refresh awaited itself')),
        throwsA(isA<MalvaApiException>()));
    expect(refreshes, 1);
  });

  test(
      'late account A refresh cannot replace account B credentials or retry A request',
      () async {
    final pending = Completer<http.Response>();
    final started = Completer<void>();
    final refreshTokens = <Object?>[];
    final callbacks = <String>[];
    final api = MalvaApiClient(
        baseUrl: 'http://backend.test',
        onTokenRefreshed: (access, refresh) => callbacks.add(access),
        httpClient: MockClient((request) async {
          if (request.url.path == '/v1/auth/refresh') {
            final token = (jsonDecode(request.body) as Map)['refresh_token'];
            refreshTokens.add(token);
            if (token == 'refresh-A') {
              started.complete();
              return pending.future;
            }
            return _json(_auth('B'));
          }
          if (request.headers['authorization'] == 'Bearer fresh-B')
            return _json({'bookings': []});
          return _json({'error': 'unauthorized'}, 401);
        }));
    api.setRefreshToken('refresh-A');
    final old = api.listBookings(accessToken: 'expired-A');
    final rejected = expectLater(old, throwsA(isA<MalvaApiException>()));
    await started.future;
    api.setRefreshToken('refresh-B');
    pending.complete(_json(_auth('A')));
    await rejected;
    expect(callbacks, isEmpty);
    await api.listBookings(accessToken: 'expired-B');
    expect(refreshTokens, ['refresh-A', 'refresh-B']);
    expect(callbacks, ['fresh-B']);
  });

  test('late A unauthorized response never consumes B refresh token', () async {
    final response = Completer<http.Response>();
    final started = Completer<void>();
    var refreshes = 0;
    final api = MalvaApiClient(
        baseUrl: 'http://backend.test',
        httpClient: MockClient((request) async {
          if (request.url.path == '/v1/auth/refresh') {
            refreshes++;
            return _json(_auth('B'));
          }
          if (!started.isCompleted) started.complete();
          return response.future;
        }));
    api.setRefreshToken('refresh-A');
    final old = api.listBookings(accessToken: 'expired-A');
    final rejected = expectLater(old, throwsA(isA<MalvaApiException>()));
    await started.future;
    api.setRefreshToken('refresh-B');
    response.complete(_json({'error': 'unauthorized'}, 401));
    await rejected;
    expect(refreshes, 0);
  });
}
