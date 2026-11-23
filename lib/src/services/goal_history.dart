import '../time/wib.dart';
import 'malva_api_client.dart';

typedef GoalHistoryEntry = ({BackendGoal goal, BackendHabitLog log});

Map<String, List<GoalHistoryEntry>> groupGoalHistory(
    List<BackendGoal> goals, List<BackendHabitLog> logs,
    {String? goalId}) {
  final byId = {for (final goal in goals) goal.id: goal};
  final grouped = <String, List<GoalHistoryEntry>>{};
  final sorted = [...logs]..sort((a, b) => b.loggedOn.compareTo(a.loggedOn));
  for (final log in sorted) {
    final goal = byId[log.goalId];
    if (goal == null ||
        (goalId != null && goal.id != goalId) ||
        parseWibStored(log.loggedOn) == null) continue;
    (grouped[log.loggedOn] ??= []).add((goal: goal, log: log));
  }
  return grouped;
}

Future<List<BackendHabitLog>> loadGoalHistoryLogs(
    MalvaApiClient api, String token, DateTime start, DateTime end) async {
  final from = wibDateKey(start);
  final to = wibDateKey(end);
  final logs = await api.listHabitLogs(accessToken: token, from: from, to: to);
  // The API caps multi-day results at 400, while a single date is uncapped.
  if (logs.length < 400 || from == to) return logs;
  final middle = start.add(Duration(days: end.difference(start).inDays ~/ 2));
  final results = await Future.wait([
    loadGoalHistoryLogs(api, token, start, middle),
    loadGoalHistoryLogs(api, token, middle.add(const Duration(days: 1)), end),
  ]);
  return [...results[0], ...results[1]];
}

int completedGoalSteps(GoalHistoryEntry entry) =>
    entry.goal.details?.steps
        .where((step) => entry.log.completedStepIds.contains(step.id))
        .length ??
    0;

String goalHistoryResult(GoalHistoryEntry entry) {
  final details = entry.goal.details;
  return switch (details?.method) {
    'numeric' => '${entry.log.value}/${details!.target} ${details.unit}'.trim(),
    'checklist' =>
      '${completedGoalSteps(entry)}/${details!.steps.length} langkah',
    _ => entry.log.done ? 'Selesai' : 'Belum selesai',
  };
}
