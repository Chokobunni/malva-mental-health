import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:malva_mental_health/src/services/goal_history.dart';
import 'package:malva_mental_health/src/services/malva_api_client.dart';
import 'package:malva_mental_health/src/time/wib.dart';

void main() {
  BackendGoal goal(String id, Map<String, dynamic>? details,
          {bool active = true}) =>
      BackendGoal.fromJson({
        'id': id,
        'is_active': active,
        if (details != null)
          'details': {'start_date': '2026-11-21', ...details},
      });

  test('past scheduled dates include missed occurrences and saved progress',
      () {
    final goals = [
      goal('daily', {'time': '22:00', 'auto_fail': false}),
      goal('weekly', {
        'recurrence': 'weekly',
        'weekdays': [1]
      }),
      goal('flexible', {'recurrence': 'weekly', 'weekly_target': 2}),
      goal('archived', {}, active: false),
      goal('legacy', null),
    ];
    const logs = [
      BackendHabitLog(
          id: 'actual', goalId: 'daily', loggedOn: '2026-11-23', done: true),
      BackendHabitLog(
          id: 'saved', goalId: 'archived', loggedOn: '2026-11-22', done: true),
    ];

    final grouped = groupGoalHistory(goals, logs,
        start: wibFromParts(2026, 11, 20),
        end: wibFromParts(2026, 11, 26),
        today: wibFromParts(2026, 11, 25, 23));
    expect(grouped.keys, [
      '2026-11-24',
      '2026-11-23',
      '2026-11-22',
      '2026-11-21',
    ]);
    expect(grouped['2026-11-24']!.single.goal.id, 'daily');
    expect(grouped['2026-11-24']!.single.log, isNull);
    expect(goalHistoryResult(grouped['2026-11-24']!.single), 'Tidak dilakukan');
    expect(grouped['2026-11-23']!.length, 2);
    expect(grouped['2026-11-23']!.first.log, logs.first);
    expect(grouped['2026-11-23']!.last.goal.id, 'weekly');
    expect(grouped['2026-11-22']!.first.log, logs.last);
  });

  test('monthly schedule uses the original anchor after short months', () {
    final target = goal('monthly', {
      'start_date': '2026-01-31',
      'recurrence': 'monthly',
      'method': 'checklist',
    });

    final grouped = groupGoalHistory([target], [],
        start: wibFromParts(2026, 2, 1),
        end: wibFromParts(2026, 4, 1),
        today: wibFromParts(2026, 4, 1));
    expect(grouped.keys, ['2026-03-31', '2026-02-28']);
    expect(goalHistoryResult(grouped.values.first.single), 'Tidak dilakukan');
  });

  test(
      'legacy daily target infers missed days while flexible session quota keeps saved logs',
      () {
    final legacy = BackendGoal.fromJson({
      'id': 'legacy-daily',
      'target_per_week': 7,
      'created_at': '2026-11-17T00:30:00+07:00',
    });
    final flexible = goal('flexible-daily', {
      'start_date': '2026-11-17',
      'recurrence': 'weekly',
      'weekly_target': 7,
    });
    final history = groupGoalHistory([
      legacy,
      flexible
    ], const [
      BackendHabitLog(
          id: 'saved',
          goalId: 'legacy-daily',
          loggedOn: '2026-11-22',
          done: true),
    ],
        start: wibFromParts(2026, 11, 16),
        end: wibFromParts(2026, 11, 25),
        today: wibFromParts(2026, 11, 25));
    expect(history.keys, [
      '2026-11-24',
      '2026-11-23',
      '2026-11-22',
      '2026-11-21',
      '2026-11-20',
      '2026-11-19',
      '2026-11-18',
      '2026-11-17'
    ]);
    expect(history.values.every((entries) => entries.length == 1), isTrue);
    expect(goalHistoryResult(history['2026-11-17']!.first), 'Tidak dilakukan');
    expect(goalHistoryResult(history['2026-11-22']!.first), 'Selesai');
  });

  test('legacy flexible and unknown start dates retain only saved logs', () {
    final goals = [
      for (final id in ['flexible', 'unknown', 'archived'])
        BackendGoal.fromJson({
          'id': id,
          'target_per_week': id == 'flexible' ? 3 : 7,
          'is_active': id != 'archived',
          if (id != 'unknown') 'created_at': '2026-11-17T00:30:00+07:00',
        }),
    ];
    final history = groupGoalHistory(
        goals,
        const [
          BackendHabitLog(
              id: 'old',
              goalId: 'archived',
              loggedOn: '2026-11-22',
              done: true),
        ],
        start: wibFromParts(2026, 11, 16),
        end: wibFromParts(2026, 11, 25),
        today: wibFromParts(2026, 11, 25));
    expect(history.keys, ['2026-11-22']);
    expect(history.values.single.single.goal.id, 'archived');
  });

  test('history and PDF loader keeps recent and older logs across the API cap',
      () async {
    final rows = [
      for (var i = 0; i < 401; i++)
        {
          'id': 'l$i',
          'goal_id': 'g',
          'logged_on': i < 400 ? '2026-11-25' : '2026-11-15',
          'done': true
        },
    ];
    final api = MalvaApiClient(
        baseUrl: 'https://goals.test',
        httpClient: MockClient((request) async {
          final from = request.url.queryParameters['from']!;
          final to = request.url.queryParameters['to']!;
          final matching = rows.where((row) =>
              (row['logged_on']! as String).compareTo(from) >= 0 &&
              (row['logged_on']! as String).compareTo(to) <= 0);
          return http.Response(
              jsonEncode({
                'logs': (from == to ? matching : matching.take(400)).toList()
              }),
              200);
        }));
    final logs = await loadGoalHistoryLogs(api, 'synthetic',
        wibFromParts(2026, 11, 15), wibFromParts(2026, 11, 25));
    expect(logs.length, 401);
    expect(logs.map((log) => log.id).toSet().length, 401);
    expect(logs.where((log) => log.loggedOn == '2026-11-25').length, 400);
    expect(logs.singleWhere((log) => log.id == 'l400').loggedOn, '2026-11-15');
  });
}
