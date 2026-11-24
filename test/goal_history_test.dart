import 'package:flutter_test/flutter_test.dart';
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
}
