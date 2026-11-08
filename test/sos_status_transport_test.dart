import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:malva_mental_health/src/services/malva_api_client.dart';

void main() {
  test('SOS status uses a real query and preserves aggregate transitions',
      () async {
    var calls = 0;
    final requests = <http.Request>[];
    final fixtures = [
      {'total': 2, 'sent': 0, 'delivered': 0, 'pending': 2, 'failed': 0},
      {'total': 2, 'sent': 1, 'delivered': 0, 'pending': 0, 'failed': 1},
      {'total': 2, 'sent': 0, 'delivered': 1, 'pending': 0, 'failed': 1},
    ];
    final api = MalvaApiClient(
        baseUrl: 'http://backend.test',
        httpClient: MockClient((r) async {
          requests.add(r);
          return http.Response(jsonEncode({'blast': fixtures[calls++]}), 200,
              headers: {'content-type': 'application/json'});
        }));
    final queued = await api.getBlastStatus(
        accessToken: 'test', incidentId: 'incident-synthetic');
    expect(requests.single.method, 'GET');
    expect(requests.single.url.path, '/v1/sos-blast-status');
    expect(requests.single.url.queryParameters,
        {'incident_id': 'incident-synthetic'});
    expect(queued.pending, 2);
    expect(queued.sent, 0);
    final sent = await api.getBlastStatus(
        accessToken: 'test', incidentId: 'incident-synthetic');
    expect(sent.sent, 1);
    expect(sent.failed, 1);
    expect(sent.delivered, 0);
    final delivered = await api.getBlastStatus(
        accessToken: 'test', incidentId: 'incident-synthetic');
    expect(delivered.delivered, 1);
    expect(delivered.sent, 0);
  });
}
