import '../../models.dart';
import '../../services/medication_reminder_service.dart';
import '../contracts/ports.dart';

/// [ReminderScheduler] mobile: membungkus [MedicationReminderService] yang
/// sudah terbukti benar (izin Android 13+, alarm presisi/inexact, banyak jam).
///
/// Perilaku TIDAK berubah dari `2fcfde4` — kelas ini hanya adaptor tipis.
class LocalNotificationReminderScheduler implements ReminderScheduler {
  LocalNotificationReminderScheduler({MedicationReminderService? service})
      : _service = service ?? MedicationReminderService();

  final MedicationReminderService _service;

  /// Id obat yang pernah dijadwalkan, agar [cancelAll] bisa membatalkannya
  /// (MedicationReminderService tidak mengekspos cancelAll global).
  final Set<String> _scheduledIds = <String>{};

  @override
  bool get canScheduleOsReminders => true;

  @override
  Future<void> initialize() => _service.initialize();

  @override
  Future<bool> requestPermissions() => _service.ensurePermissions();

  @override
  Future<void> scheduleAll(List<dynamic> medications) async {
    final meds = medications.whereType<Medication>().toList();
    for (final med in meds) {
      _scheduledIds.add(med.id);
    }
    await _service.scheduleAll(meds);
  }

  @override
  Future<void> cancelAll() async {
    await _service.cancelRemindersFor(_scheduledIds.toList());
    _scheduledIds.clear();
  }

  @override
  Future<void> showTestNotification() => _service.showTestNotification();

  /// Di mobile pengingat dijadwalkan OS, jadi tidak ada pancaran in-app.
  @override
  Stream<String> get inAppDueReminders => const Stream<String>.empty();
}
