import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:malva_mental_health/src/services/malva_api_client.dart';
import 'package:malva_mental_health/src/services/weekly_summary_service.dart';
import 'package:malva_mental_health/src/time/wib.dart';

void main() {
  test('screening detail resolves older entries from full owned history',
      () async {
    final api = MalvaApiClient(
        baseUrl: 'http://backend.test',
        httpClient: MockClient((request) async {
          expect(request.url.queryParameters['patient_id'], 'patient-1');
          return http.Response(
              jsonEncode({
                'screenings': [
                  if (request.url.queryParameters['limit'] == '0')
                    {'id': 'old-screening', 'patient_id': 'patient-1'}
                ]
              }),
              200);
        }));
    final result = await api.getScreeningDetail(
        accessToken: 'token',
        patientId: 'patient-1',
        screeningId: 'old-screening');
    expect(result.id, 'old-screening');
  });
  test('summary sorts newest-first server data before deriving mood trend',
      () async {
    final now = wibNow();
    final api = MalvaApiClient(
        baseUrl: 'http://backend.test',
        httpClient: MockClient((request) async => http.Response(
            jsonEncode(request.url.path == '/v1/mood-checkins'
                ? {
                    'moods': [
                      {
                        'id': 'historical',
                        'mood': 'awful',
                        'occurred_at':
                            wibIso(now.subtract(const Duration(days: 90))),
                        'sleep_hours': 1
                      },
                      {
                        'id': 'new',
                        'mood': 'great',
                        'occurred_at':
                            wibIso(now.subtract(const Duration(hours: 1))),
                        'sleep_hours': 8
                      },
                      {
                        'id': 'old',
                        'mood': 'sad',
                        'occurred_at':
                            wibIso(now.subtract(const Duration(days: 2))),
                        'sleep_hours': 6
                      },
                    ]
                  }
                : {'logs': []}),
            200,
            headers: {'content-type': 'application/json'})));
    final result = await loadWeeklySummary(api: api, accessToken: 'token');
    expect(result!.moodCount, 2);
    expect(result.moodTrend, 1);
    expect(result.avgSleepHours, 7);
    expect(result.entries, hasLength(3),
        reason: 'monthly, yearly and lifetime charts need full mood history');
  });
}
