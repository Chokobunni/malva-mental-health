import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:timezone/timezone.dart' as tz;

import '../platform/contracts/ports.dart';
import '../platform/platform_factory.dart';
import '../time/wib.dart';
import 'local_notification_router.dart';
import 'malva_api_client.dart';

/// Preferensi pengingat goals harian milik satu pasien.
class GoalReminderSettings {
  const GoalReminderSettings({
    this.enabled = true,
    this.hour = GoalReminderService.defaultHour,
    this.minute = GoalReminderService.defaultMinute,
  });

  /// True bila pengingat harian diaktifkan.
  final bool enabled;

  /// Jam WIB (0-23).
  final int hour;

  /// Menit WIB (0-59).
  final int minute;

  GoalReminderSettings copyWith({bool? enabled, int? hour, int? minute}) {
    return GoalReminderSettings(
      enabled: enabled ?? this.enabled,
      hour: hour ?? this.hour,
      minute: minute ?? this.minute,
    );
  }

  /// Label jam `HH:mm`.
  String get label =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
}

/// Pengingat terjadwal goals serta pengingat harian untuk goal lama (LOKAL).
///
/// KENAPA LOKAL: kebijakan push hanya mengizinkan FCM untuk chat. Pengingat
/// goals (dan obat) dijadwalkan di perangkat agar tidak menambah push dari
/// server dan tidak bisa berulang karena pengiriman ganda.
///
/// Pembagian lapisan: kelas ini memegang ATURAN + PREFERENSI (murni, bisa
/// diuji tanpa plugin). Penjadwalan OS dilakukan [GoalReminderScheduler]
/// (implementasi di `lib/src/platform/io/`), karena kode yang menyentuh
/// `flutter_local_notifications` wajib berada di lapisan platform (gate
/// isolasi platform).
class GoalReminderService {
  /// [enabled] = false mematikan SEMUA operasi (dipakai di web, yang tidak
  /// punya penjadwal notifikasi OS).
  GoalReminderService({
    bool enabled = true,
    SecureStore? store,
    GoalReminderScheduler? scheduler,
  })  : _enabled = enabled,
        _store = store ?? createSecureStore(),
        _scheduler = scheduler ?? createGoalReminderScheduler();

  final bool _enabled;
  final SecureStore _store;
  final GoalReminderScheduler _scheduler;

  Future<void> _work = Future<void>.value();
  Future<void>? _initialization;
  int _generation = 0;
  static const int maxScheduledReminders = 48;
  static const int firstConfiguredId = 930000;
  static const String scheduledIdsStorageKey = 'malva_goal_scheduled_ids';

  /// Earliest future alarms, bounded to one year of upcoming occurrences.
  /// Offsets may cross midnight; completion applies to the occurrence's day.
  static List<DateTime> upcomingReminders(BackendGoal goal,
      {DateTime? now, int limit = maxScheduledReminders}) {
    final details = goal.details;
    if (!goal.isActive || details == null || limit < 1) return [];
    final time = RegExp(r'^(\d{2}):(\d{2})$').firstMatch(details.time);
    if (time == null) return [];
    final hour = int.parse(time[1]!);
    final minute = int.parse(time[2]!);
    if (hour > 23 || minute > 59) return [];
    final base = toWib(now ?? wibNow());
    final offsets =
        details.reminders.where((n) => n >= 0 && n <= 10080).toSet();
    final alarms = <int, DateTime>{};
    for (var day = 0; day <= 370; day++) {
      final date = wibFromParts(base.year, base.month, base.day + day);
      if (!details.isDueOn(date) || (day == 0 && goal.doneToday == true)) {
        continue;
      }
      final occurrence =
          wibFromParts(date.year, date.month, date.day, hour, minute);
      for (final offset in offsets) {
        final alarm = occurrence.subtract(Duration(minutes: offset));
        if (alarm.isAfter(base)) alarms[alarm.millisecondsSinceEpoch] = alarm;
      }
    }
    final sorted = alarms.values.toList()..sort();
    return sorted.take(limit).toList(growable: false);
  }

  /// Replace the local snapshot. Generation checks surround asynchronous OS
  /// work so logout/account changes cannot leave a late alarm behind.
  Future<void> syncGoals(
      {required List<BackendGoal> goals,
      required GoalReminderSettings settings,
      DateTime? now,
      bool Function()? isCurrent}) {
    if (!_enabled) return Future<void>.value();
    final generation = ++_generation;
    bool current() => generation == _generation && (isCurrent?.call() ?? true);
    final base = now ?? wibNow();
    _work = _work.then((_) async {
      if (!current()) return;
      await initialize();
      if (!current()) return;
      await _cancelConfigured();
      if (!current()) return;
      final alarms = goals
          .expand((goal) => upcomingReminders(goal, now: base))
          .toList()
        ..sort();
      final bounded = alarms.take(maxScheduledReminders).toList();
      // Persist before OS writes: process death must not orphan an alarm.
      await _store.write(
          scheduledIdsStorageKey,
          jsonEncode(
              List.generate(bounded.length, (i) => firstConfiguredId + i)));
      for (var i = 0; i < bounded.length; i++) {
        if (!current()) break;
        await _scheduler.scheduleOnce(
            id: firstConfiguredId + i,
            title: title,
            body: body,
            scheduledAt: bounded[i],
            payload: payload);
      }
      if (!current()) {
        await _cancelConfigured();
        await _scheduler.cancel(notificationId);
        return;
      }
      await sync(
          hasActiveGoals: goals.any(
              (g) => g.isActive && g.details == null && g.doneToday != true),
          enabled: settings.enabled,
          hour: settings.hour,
          minute: settings.minute);
      if (!current()) {
        await _cancelConfigured();
        await _scheduler.cancel(notificationId);
      }
    }).catchError((Object _) {
      // OS permission/network-independent storage failures must not block boot.
      if (kDebugMode) debugPrint('Gagal menyinkronkan pengingat goals');
    });
    return _work;
  }

  Future<void> _cancelConfigured() async {
    // A reserved bounded ID range also recovers schedules when storage was
    // lost/corrupted. Only this service uses these IDs.
    final ids =
        List.generate(maxScheduledReminders, (i) => firstConfiguredId + i)
            .toSet();
    try {
      final raw = await _store.read(scheduledIdsStorageKey);
      if (raw != null) {
        final stored = jsonDecode(raw);
        if (stored is List) {
          ids.addAll(stored.whereType<int>().where((id) =>
              id >= firstConfiguredId &&
              id < firstConfiguredId + maxScheduledReminders));
        }
      }
    } on Object {/* Reserved range remains authoritative. */}
    for (final id in ids) {
      await _scheduler.cancel(id);
    }
    try {
      await _store.delete(scheduledIdsStorageKey);
    } on Object {
      // The bounded ID range remains cancellable on the next run even when
      // storage is unavailable. Continue cancelling the legacy OS alarm.
    }
  }

  /// Id tetap untuk satu pengingat harian goal lama tanpa konfigurasi.
  static const int notificationId = 920001;

  /// Kunci penyimpanan preferensi (SecureStore).
  static const String enabledStorageKey = 'malva_goal_reminder_enabled';
  static const String hourStorageKey = 'malva_goal_reminder_hour';
  static const String minuteStorageKey = 'malva_goal_reminder_minute';

  /// Jam bawaan: 19:00 WIB (setelah aktivitas harian, sebelum istirahat).
  static const int defaultHour = 19;
  static const int defaultMinute = 0;

  /// Payload notifikasi (bukan JSON, bukan id obat — lihat router).
  static const String payload = LocalNotificationRouter.goalReminderPayload;

  static const String title = 'Waktunya cek goals hari ini';
  static const String body =
      'Catat progres goals-mu sebentar saja — konsistensi kecil berarti besar.';

  /// Siapkan kanal notifikasi, izin, dan handler tap (sekali per proses).
  Future<void> initialize() {
    if (!_enabled) return Future<void>.value();
    return _initialization ??= _initialize();
  }

  Future<void> _initialize() async {
    // WAJIB lewat initializeWib(): memaksa zona lokal proses ke Asia/Jakarta.
    initializeWib();
    try {
      await _scheduler.initialize();
    } on Object {
      // Izin/kanal gagal tidak boleh menggagalkan boot aplikasi.
      if (kDebugMode) debugPrint('Gagal menyiapkan pengingat goals');
    }
  }

  /// Sinkronkan jadwal pengingat dengan kondisi terbaru.
  ///
  /// [hasActiveGoals] = pasien punya minimal satu goal aktif. Tanpa goal
  /// aktif, pengingat dibatalkan agar tidak mengganggu tanpa ada yang perlu
  /// dicatat.
  Future<void> sync({
    required bool hasActiveGoals,
    required bool enabled,
    required int hour,
    required int minute,
  }) async {
    if (!_enabled) return;
    if (!shouldSchedule(hasActiveGoals: hasActiveGoals, enabled: enabled)) {
      await _scheduler.cancel(notificationId);
      return;
    }

    try {
      await _scheduler.scheduleDaily(
        id: notificationId,
        title: title,
        body: body,
        scheduledAt: nextGoalReminderOccurrence(hour, minute),
        payload: payload,
      );
    } on Object catch (error) {
      // Gagal menjadwalkan (izin/alarm) tidak boleh menggagalkan boot.
      if (kDebugMode) debugPrint('Gagal menjadwalkan pengingat goals: $error');
    }
  }

  /// Batalkan pengingat goals.
  Future<void> cancel() {
    if (!_enabled) return Future<void>.value();
    _generation++;
    _work = _work.then((_) async {
      await initialize();
      await _cancelConfigured();
      await _scheduler.cancel(notificationId);
    }).catchError((Object _) {
      if (kDebugMode) debugPrint('Gagal membatalkan pengingat goals');
    });
    return _work;
  }

  /// Aturan murni: pengingat hanya dijadwalkan bila diaktifkan DAN ada goal
  /// aktif. Dipisah agar bisa diuji tanpa plugin.
  @visibleForTesting
  static bool shouldSchedule({
    required bool hasActiveGoals,
    required bool enabled,
  }) =>
      enabled && hasActiveGoals;

  /// Waktu pengingat berikutnya (hari ini bila belum lewat, besok bila lewat).
  ///
  /// MURNI dan SELALU WIB: komponen tanggal & jam dibangun lewat
  /// [wibFromParts]. Memakai `DateTime(...)` akan memakai zona perangkat,
  /// sehingga pengingat bergeser di perangkat non-WIB.
  ///
  /// [now] hanya untuk pengujian (default [wibNow]).
  static tz.TZDateTime nextGoalReminderOccurrence(
    int hour,
    int minute, {
    DateTime? now,
  }) {
    final base = toWib(now ?? wibNow());
    var scheduled = wibFromParts(
      base.year,
      base.month,
      base.day,
      hour,
      minute,
    );
    if (!scheduled.isAfter(base)) {
      // Besok pada jam yang sama — dibangun ulang lewat komponen kalender
      // (bukan `add(Duration(days: 1))`) agar tetap wall-clock WIB yang sama.
      scheduled = wibFromParts(
        base.year,
        base.month,
        base.day + 1,
        hour,
        minute,
      );
    }
    return scheduled;
  }

  /// Baca preferensi tersimpan. Nilai hilang/rusak memakai bawaan 19:00 aktif.
  Future<GoalReminderSettings> loadSettings() async {
    try {
      final enabledRaw = await _store.read(enabledStorageKey);
      final hourRaw = await _store.read(hourStorageKey);
      final minuteRaw = await _store.read(minuteStorageKey);
      return GoalReminderSettings(
        enabled: enabledRaw != 'false',
        hour: _clamp(int.tryParse(hourRaw ?? '') ?? defaultHour, 0, 23),
        minute: _clamp(int.tryParse(minuteRaw ?? '') ?? defaultMinute, 0, 59),
      );
    } on Object {
      return const GoalReminderSettings();
    }
  }

  /// Simpan preferensi (dipakai layar Goals).
  Future<void> saveSettings(GoalReminderSettings settings) async {
    try {
      await _store.write(
          enabledStorageKey, settings.enabled ? 'true' : 'false');
      await _store.write(hourStorageKey, '${settings.hour}');
      await _store.write(minuteStorageKey, '${settings.minute}');
    } on Object catch (error) {
      if (kDebugMode) debugPrint('Gagal menyimpan preferensi goals: $error');
    }
  }

  static int _clamp(int value, int min, int max) =>
      value < min ? min : (value > max ? max : value);
}
