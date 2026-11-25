import '../time/wib.dart';
import 'malva_api_client.dart';

typedef GoalHistoryEntry = ({BackendGoal goal, BackendHabitLog? log});

Map<String, List<GoalHistoryEntry>> groupGoalHistory(
    List<BackendGoal> goals, List<BackendHabitLog> logs,
    {required DateTime start, required DateTime end, required DateTime today}) {
  final from = wibDateKey(start);
  final to = wibDateKey(end);
  final todayKey = wibDateKey(today);
  final byId = {for (final goal in goals) goal.id: goal};
  final grouped = <String, Map<String, GoalHistoryEntry>>{};
  for (final log in logs) {
    final goal = byId[log.goalId];
    if (goal == null ||
        log.loggedOn.compareTo(from) < 0 ||
        log.loggedOn.compareTo(to) > 0 ||
        parseWibStored(log.loggedOn) == null) continue;
    (grouped[log.loggedOn] ??= {})[goal.id] = (goal: goal, log: log);
  }
  for (final goal in goals) {
    final details = goal.details;
    // Seven occurrences require every day, even when stored as a flexible
    // weekly goal. Smaller weekly targets have no fixed missed day to infer.
    final legacyDaily = details == null && goal.targetPerWeek == 7;
    if (!goal.isActive ||
        (details == null && !legacyDaily) ||
        (details?.recurrence == 'weekly' &&
            details?.weeklyTarget != null &&
            details!.weeklyTarget != 7)) {
      continue;
    }
    final anchor = details == null
        ? (goal.createdAt == null
            ? null
            : parseWibStored(wibDateKey(goal.createdAt!)))
        : parseWibStored(details.startDate);
    if (anchor == null) continue;
    var day = parseWibStored(from)!;
    if (anchor.isAfter(day)) day = anchor;
    for (;; day = day.add(const Duration(days: 1))) {
      final key = wibDateKey(day);
      if (key.compareTo(to) > 0 || key.compareTo(todayKey) >= 0) break;
      if (details != null && !details.isDueOn(day)) continue;
      (grouped[key] ??= {}).putIfAbsent(goal.id, () => (goal: goal, log: null));
    }
  }
  final dates = grouped.keys.toList()..sort((a, b) => b.compareTo(a));
  return {for (final date in dates) date: grouped[date]!.values.toList()};
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
        .where((step) => entry.log?.completedStepIds.contains(step.id) == true)
        .length ??
    0;

String goalHistoryResult(GoalHistoryEntry entry) {
  final log = entry.log;
  if (log == null) return 'Tidak dilakukan';
  final details = entry.goal.details;
  return switch (details?.method) {
    'numeric' => '${log.value}/${details!.target} ${details.unit}'.trim(),
    'checklist' =>
      '${completedGoalSteps(entry)}/${details!.steps.length} langkah',
    _ => log.done ? 'Selesai' : 'Tidak dilakukan',
  };
}
