import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:malva_mental_health/src/services/malva_api_client.dart';

void main() {
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
