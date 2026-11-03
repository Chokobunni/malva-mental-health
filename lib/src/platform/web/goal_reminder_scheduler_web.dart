import '../contracts/ports.dart';

/// [GoalReminderScheduler] web: browser tidak punya penjadwal notifikasi OS.
///
/// Semua operasi no-op. UI web sudah menyembunyikan pengingat berbasis OS
/// (`capabilities.canScheduleOsReminders == false`), jadi tidak ada klaim
/// palsu bahwa pengingat akan berbunyi.
class NoopGoalReminderScheduler implements GoalReminderScheduler {
  const NoopGoalReminderScheduler();

  @override
  Future<void> initialize() async {}

  @override
  Future<void> scheduleDaily({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledAt,
    required String payload,
  }) async {}

  @override
  Future<void> cancel(int id) async {}
}
