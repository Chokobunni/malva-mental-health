import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:malva_mental_health/src/services/malva_api_client.dart';
import 'package:malva_mental_health/src/services/weekly_summary_service.dart';
import 'package:malva_mental_health/src/time/wib.dart';

void main() {
  for (final fromApi in [true, false]) {
    test(
        'historical seven-day window uses WIB asOf boundaries (${fromApi ? 'API' : 'fallback'})',
        () async {
      final start = wibFromParts(2025, 1, 5);
      final end = wibFromParts(2025, 1, 12);
      final times = [
        start.subtract(const Duration(minutes: 1)),
        start,
        end.subtract(const Duration(minutes: 1)),
        end,
        wibNow(),
      ];
      final api = MalvaApiClient(
          baseUrl: 'http://backend.test',
          httpClient: MockClient((request) async {
            if (!fromApi) return http.Response('{}', 403);
            expect(request.url.queryParameters['patient_id'], 'patient');
            return http.Response(
                jsonEncode(request.url.path == '/v1/mood-checkins'
                    ? {
                        'moods': [
                          for (var i = 0; i < times.length; i++)
                            {
                              'id': '$i',
                              'mood': 'good',
                              'sleep_hours': i == 1 ? 6 : 8,
                              'occurred_at': wibIso(times[i])
                            }
                        ]
                      }
                    : {
                        'medication_logs': [
                          for (var i = 0; i < times.length; i++)
                            {
                              'id': '$i',
                              'status': i == 2 ? 'missed' : 'taken',
                              'taken_at': wibIso(times[i])
                            }
                        ]
                      }),
                200);
          }));
      final result = await loadWeeklySummary(
          api: api,
          accessToken: 'token',
          patientId: 'patient',
          // This instant is January 11 in WIB; device/input offset must not choose January 10.
          asOf: DateTime.parse('2025-01-10T18:30:00-05:00'),
          localMoods: [
            for (var i = 0; i < times.length; i++)
              (at: times[i], sleepHours: i == 1 ? 6.0 : 8.0, moodScore: 4)
          ],
          localLogs: [
            for (var i = 0; i < times.length; i++)
              (at: times[i], status: i == 2 ? 'missed' : 'taken')
          ]);
      expect(result!.moodCount, 2);
      expect(result.avgSleepHours, 7);
      expect(result.totalLogs, 2);
      expect(result.adherencePercent, 50);
      expect(result.source, fromApi ? 'api' : 'local');
    });
  }
  test(
      'summary includes exactly seven WIB calendar days and excludes future records',
      () async {
    final now = wibNow();
    final start = wibFromParts(now.year, now.month, now.day)
        .subtract(const Duration(days: 6));
    final api = MalvaApiClient(
        baseUrl: 'http://backend.test',
        httpClient: MockClient((request) async => http.Response(
            jsonEncode(request.url.path == '/v1/mood-checkins'
                ? {
                    'moods': [
                      {
                        'id': 'boundary',
                        'mood': 'good',
                        'occurred_at': wibIso(start),
                        'sleep_hours': 8
                      },
                      {
                        'id': 'before',
                        'mood': 'sad',
                        'occurred_at':
                            wibIso(start.subtract(const Duration(minutes: 1))),
                        'sleep_hours': 2
                      },
                      {
                        'id': 'future',
                        'mood': 'great',
                        'occurred_at':
                            wibIso(start.add(const Duration(days: 7))),
                        'sleep_hours': 12
                      },
                    ]
                  }
                : {
                    'medication_logs': [
                      {
                        'id': 'boundary',
                        'status': 'taken',
                        'taken_at': wibIso(start)
                      },
                      {
                        'id': 'before',
                        'status': 'missed',
                        'taken_at':
                            wibIso(start.subtract(const Duration(minutes: 1)))
                      },
                      {
                        'id': 'future',
                        'status': 'missed',
                        'taken_at': wibIso(start.add(const Duration(days: 7)))
                      },
                      {'id': 'unknown', 'status': 'missed'},
                    ]
                  }),
            200)));
    final result = await loadWeeklySummary(api: api, accessToken: 'token');
    expect(result!.moodCount, 1);
    expect(result.avgSleepHours, 8);
    expect(result.totalLogs, 1);
    expect(result.adherencePercent, 100);
  });
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
