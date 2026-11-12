import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:malva_mental_health/src/models/goal_details.dart';
import 'package:malva_mental_health/src/platform/contracts/ports.dart';
import 'package:malva_mental_health/src/services/goal_reminder_service.dart';
import 'package:malva_mental_health/src/services/malva_api_client.dart';
import 'package:malva_mental_health/src/time/wib.dart';

class MemoryStore implements SecureStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

class FailingDeleteStore extends MemoryStore {
  @override
  Future<void> delete(String key) async => throw StateError('unavailable');
}

class Scheduler implements GoalReminderScheduler {
  final pending = <int, DateTime>{};
  final daily = <int>{};
  final dailyAt = <int, DateTime>{};
  final payloads = <String>[];
  Completer<void>? block;
  Completer<void>? initialization;
  @override
  Future<void> initialize() async {
    await initialization?.future;
  }

  @override
  Future<void> cancel(int id) async {
    pending.remove(id);
    daily.remove(id);
    dailyAt.remove(id);
  }

  @override
  Future<void> scheduleDaily(
      {required int id,
      required String title,
      required String body,
      required DateTime scheduledAt,
      required String payload}) async {
    daily.add(id);
    dailyAt[id] = scheduledAt;
  }

  @override
  Future<void> scheduleOnce(
      {required int id,
      required String title,
      required String body,
      required DateTime scheduledAt,
      required String payload}) async {
    final gate = block;
    block = null;
    if (gate != null) await gate.future;
    pending[id] = scheduledAt;
    payloads.add(payload);
  }
}

BackendGoal goal(
        {String id = 'one',
        GoalDetails? details,
        bool active = true,
        bool done = false}) =>
    BackendGoal(
        id: id,
        title: 'Private title',
        category: 'general',
        targetPerWeek: 3,
        isActive: active,
        details: details,
        doneToday: done);
const details =
    GoalDetails(startDate: '2026-11-12', time: '22:30', reminders: [30, 0]);
void main() {
  test('completed legacy goal keeps its future repeating daily reminder',
      () async {
    final scheduler = Scheduler();
    final service =
        GoalReminderService(store: MemoryStore(), scheduler: scheduler);
    final now = wibNow();
    await service.syncGoals(
        goals: [goal(done: true)],
        settings: const GoalReminderSettings(hour: 0),
        now: now);
    expect(scheduler.daily, contains(GoalReminderService.notificationId));
    expect(scheduler.dailyAt[GoalReminderService.notificationId],
        wibFromParts(now.year, now.month, now.day + 1));
  });
  test('storage deletion failure cannot preserve the legacy OS alarm on logout',
      () async {
    final scheduler = Scheduler()
      ..daily.add(GoalReminderService.notificationId);
    final service =
        GoalReminderService(store: FailingDeleteStore(), scheduler: scheduler);
    await service.cancel();
    expect(scheduler.daily, isEmpty);
  });
  test('scheduling waits for asynchronous native initialization', () async {
    final gate = Completer<void>();
    final scheduler = Scheduler()..initialization = gate;
    final service =
        GoalReminderService(store: MemoryStore(), scheduler: scheduler);
    final initializing = service.initialize();
    final syncing = service.syncGoals(
        goals: [goal(details: details)],
        settings: const GoalReminderSettings(),
        now: wibFromParts(2026, 11, 12, 20));
    for (var i = 0; i < 100; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(scheduler.pending, isEmpty);
    gate.complete();
    await initializing;
    await syncing;
    expect(scheduler.pending, isNotEmpty);
  });
  test('offsets cross midnight, deduplicate and respect weekly interval in WIB',
      () {
    const weekly = GoalDetails(
        startDate: '2026-11-12',
        time: '00:15',
        recurrence: 'weekly',
        interval: 2,
        weekdays: [1, 4],
        reminders: [30, 0, 30]);
    final times = GoalReminderService.upcomingReminders(goal(details: weekly),
        now: wibFromParts(2026, 11, 12, 0, 0), limit: 4);
    expect(times.map(wibApiDateTime).toList(), [
      '2026-11-12T00:15',
      '2026-11-22T23:45',
      '2026-11-23T00:15',
      '2026-11-25T23:45'
    ]);
    expect(
        times.every((time) => time.timeZoneOffset == const Duration(hours: 7)),
        isTrue);
  });
  test(
      'done today skips current occurrence only and daily interval uses anchor',
      () {
    final times = GoalReminderService.upcomingReminders(
        goal(
            details: const GoalDetails(
                startDate: '2026-11-12',
                time: '22:30',
                interval: 3,
                reminders: [30]),
            done: true),
        now: wibFromParts(2026, 11, 12, 10),
        limit: 2);
    expect(times.map(wibApiDateTime).toList(),
        ['2026-11-15T22:00', '2026-11-18T22:00']);
    expect(
        GoalReminderService.upcomingReminders(
            goal(details: details, active: false),
            now: wibFromParts(2026, 11, 12)),
        isEmpty);
    expect(
        GoalReminderService.upcomingReminders(
            goal(
                details:
                    const GoalDetails(startDate: '2026-11-12', reminders: [0])),
            now: wibFromParts(2026, 11, 12)),
        isEmpty);
  });
  test('configured only schedules bounded one-shots and replaces after delete',
      () async {
    final scheduler = Scheduler();
    final store = MemoryStore();
    final service = GoalReminderService(store: store, scheduler: scheduler);
    await service.syncGoals(
        goals: [goal(details: details)],
        settings: const GoalReminderSettings(),
        now: wibFromParts(2026, 11, 12, 20));
    expect(scheduler.daily, isEmpty);
    expect(scheduler.pending.length, lessThanOrEqualTo(48));
    expect(scheduler.pending.values.map(wibApiDateTime),
        containsAll(['2026-11-12T22:00', '2026-11-12T22:30']));
    expect(scheduler.payloads.toSet(), {'goal_reminder'});
    expect(store.values.values.any((value) => value.contains('Private title')),
        isFalse);
    final restarted = GoalReminderService(store: store, scheduler: scheduler);
    await restarted.cancel();
    expect(scheduler.pending, isEmpty);
    await restarted
        .syncGoals(goals: [goal()], settings: const GoalReminderSettings());
    expect(scheduler.daily, {GoalReminderService.notificationId});
    await restarted
        .syncGoals(goals: [], settings: const GoalReminderSettings());
    expect(scheduler.daily, isEmpty);
    expect(scheduler.pending, isEmpty);
  });
  test(
      'logout during native scheduling cancels late schedule and queued stale work',
      () async {
    final scheduler = Scheduler()..block = Completer<void>();
    final gate = scheduler.block!;
    final service =
        GoalReminderService(store: MemoryStore(), scheduler: scheduler);
    final sync = service.syncGoals(
        goals: [goal(details: details)],
        settings: const GoalReminderSettings(),
        now: wibFromParts(2026, 11, 12, 20));
    while (scheduler.block != null) {
      await Future<void>.delayed(Duration.zero);
    }
    final cancelled = service.cancel();
    gate.complete();
    await Future.wait([sync, cancelled]);
    expect(scheduler.pending, isEmpty);
    expect(scheduler.daily, isEmpty);
  });
  test('account generation guard stops pending work before scheduling',
      () async {
    final scheduler = Scheduler();
    final service =
        GoalReminderService(store: MemoryStore(), scheduler: scheduler);
    var current = true;
    final sync = service.syncGoals(
        goals: [goal(details: details)],
        settings: const GoalReminderSettings(),
        isCurrent: () => current);
    current = false;
    await sync;
    expect(scheduler.pending, isEmpty);
    expect(scheduler.daily, isEmpty);
  });

  test(
      'edits replace offsets and completion removes current-day pending alarms',
      () async {
    final scheduler = Scheduler();
    final service =
        GoalReminderService(store: MemoryStore(), scheduler: scheduler);
    final now = wibFromParts(2026, 11, 12, 20);
    await service.syncGoals(
        goals: [goal(details: details)],
        settings: const GoalReminderSettings(),
        now: now);
    expect(scheduler.pending.values.map(wibApiDateTime),
        contains('2026-11-12T22:00'));
    const edited =
        GoalDetails(startDate: '2026-11-12', time: '23:00', reminders: [15]);
    await service.syncGoals(
        goals: [goal(details: edited)],
        settings: const GoalReminderSettings(),
        now: now);
    expect(scheduler.pending.values.map(wibApiDateTime),
        isNot(contains('2026-11-12T22:00')));
    expect(scheduler.pending.values.map(wibApiDateTime),
        contains('2026-11-12T22:45'));
    await service.syncGoals(
        goals: [goal(details: edited, done: true)],
        settings: const GoalReminderSettings(),
        now: now);
    expect(scheduler.pending.values.map(wibApiDateTime),
        isNot(contains('2026-11-12T22:45')));
    expect(scheduler.pending.values.map(wibApiDateTime),
        contains('2026-11-13T22:45'));
    await service.syncGoals(
        goals: [goal(details: edited, active: false)],
        settings: const GoalReminderSettings(),
        now: now);
    expect(scheduler.pending, isEmpty);
  });

  test(
      'configured offsets survive disabled legacy preference without duplicate daily alarm',
      () async {
    final scheduler = Scheduler();
    final service =
        GoalReminderService(store: MemoryStore(), scheduler: scheduler);
    await service.syncGoals(
        goals: [goal(details: details), goal(id: 'legacy')],
        settings: const GoalReminderSettings(enabled: false),
        now: wibFromParts(2026, 11, 12, 20));
    expect(scheduler.pending, isNotEmpty);
    expect(scheduler.daily, isEmpty);
  });
}
