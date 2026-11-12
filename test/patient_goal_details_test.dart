import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:malva_mental_health/src/services/malva_api_client.dart';
import 'package:malva_mental_health/src/time/wib.dart';

void main() {
  test(
      'today definition uses returned server weekly history after target change',
      () {
    final before = BackendGoal.fromJson({
      'id': 'g',
      'title': 'Baca',
      'done_this_week': 2,
      'completed_weekdays': [1, 2],
      'done_today': true
    });
    final saved = BackendGoal.fromJson({
      'id': 'g',
      'title': 'Baca',
      'done_this_week': 0,
      'completed_weekdays': [],
      'done_today': false
    });
    final dynamic result = before.withDefinition(saved, on: wibNow());
    expect(result.doneThisWeek, 0);
    expect(result.completedWeekdays, isEmpty);
  });
  test(
      'historical definition retains daily log but invalidates unknown weekly history',
      () {
    final before = BackendGoal.fromJson({
      'id': 'g',
      'title': 'Baca',
      'done_this_week': 2,
      'completed_weekdays': [1, 2],
      'today_value': 14
    });
    final saved = BackendGoal.fromJson({
      'id': 'g',
      'title': 'Baca',
      'details': {'method': 'numeric', 'target': 30, 'start_date': '2026-01-01'}
    });
    final dynamic result =
        before.withDefinition(saved, on: DateTime(2026, 1, 2));
    expect(result.todayValue, 14);
    expect(result.weeklyProgressAvailable, isFalse);
    expect(result.completedWeekdays, isEmpty);
  });
  test(
      'accepted progress updates actual weekday states without waiting for reload',
      () {
    final goal = BackendGoal.fromJson({
      'id': 'g',
      'title': 'Baca',
      'is_active': true,
      'done_today': false,
      'done_this_week': 2,
      'completed_weekdays': [1, 2],
    });
    final dynamic completed = goal.withProgress(const BackendHabitLog(
        id: 'l', goalId: 'g', loggedOn: '2026-11-11', done: true));
    expect(completed.doneThisWeek, 3);
    expect(completed.completedWeekdays, [1, 2, 3]);
    final dynamic undone = completed.withProgress(const BackendHabitLog(
        id: 'l', goalId: 'g', loggedOn: '2026-11-11', done: false));
    expect(undone.doneThisWeek, 2);
    expect(undone.completedWeekdays, [1, 2]);
  });
  test('goal response keeps numeric and checklist progress separate from done',
      () {
    final dynamic goal = BackendGoal.fromJson({
      'id': 'g',
      'title': 'Baca',
      'category': 'health',
      'target_per_week': 3,
      'is_active': true,
      'details': {
        'method': 'numeric',
        'target': 20,
        'unit': 'halaman',
        'note': 'Fokus',
        'start_date': '2026-11-11',
        'time': '21:30',
        'recurrence': 'weekly',
        'interval': 1,
        'weekdays': [1, 3, 5],
        'steps': [
          {'id': 's1', 'label': 'Siapkan buku'}
        ],
        'reminders': [30],
        'auto_fail': true,
        'lock_past': true
      },
      'done_today': false,
      'today_value': 14,
      'today_completed_step_ids': ['s1'],
      'streak_days': 8,
      'is_due': true,
      'failed_today': false,
    });
    expect(goal.details.target, 20);
    expect(goal.details.steps.single.id, 's1');
    expect(goal.todayValue, 14);
    expect(goal.todayCompletedStepIds, ['s1']);
    expect(goal.doneToday, isFalse);
    expect(goal.streakDays, 8);
  });

  test('legacy goal does not invent configuration or a streak', () {
    final dynamic goal = BackendGoal.fromJson({
      'id': 'g',
      'title': 'Jalan',
      'target_per_week': 3,
      'last_logged_on': '2026-11-11'
    });
    expect(goal.details, isNull);
    expect(goal.streakDays, 0);
  });

  test('existing habit log request retains done and selected WIB date',
      () async {
    final client = MalvaApiClient(
        baseUrl: 'https://goals.test',
        httpClient: MockClient((request) async {
          expect(jsonDecode(request.body), {
            'goal_id': 'g',
            'logged_on': '2026-11-11',
            'done': false,
          });
          return http.Response(
              '{"log":{"id":"l","goal_id":"g","logged_on":"2026-11-11","done":false}}',
              200);
        }));
    final log = await client.logHabit(
        accessToken: 't', goalId: 'g', loggedOn: '2026-11-11', done: false);
    expect(log.done, isFalse);
  });
}
