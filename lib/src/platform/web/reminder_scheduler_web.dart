import '../contracts/ports.dart';

/// [ReminderScheduler] web: tidak ada penjadwal OS di browser.
///
/// `canScheduleOsReminders == false` → UI wajib menampilkan banner
/// "kelola pengingat dari aplikasi". Pengingat in-app saat tab terbuka
/// (lewat [inAppDueReminders]) ditambahkan di T03; untuk T01 stream kosong
/// yang jujur (tidak ada klaim palsu bahwa pengingat berbunyi).
class NoopReminderScheduler implements ReminderScheduler {
  const NoopReminderScheduler();

  @override
  bool get canScheduleOsReminders => false;

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> requestPermissions() async => false;

  @override
  Future<void> scheduleAll(List<dynamic> medications) async {}

  @override
  Future<void> cancelAll() async {}

  @override
  Future<void> showTestNotification() async {}

  @override
  Stream<String> get inAppDueReminders => const Stream<String>.empty();
}
