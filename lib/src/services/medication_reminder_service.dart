import 'dart:async';

import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import '../models.dart';
import '../time/wib.dart';
import 'local_notification_router.dart';

/// Layanan pengingat minum obat berbasis notifikasi lokal.
///
/// Catatan penting (penyebab bug "pengingat tidak pernah berbunyi"):
/// 1. Android 13+ mewajibkan izin POST_NOTIFICATIONS diminta secara eksplisit;
///    tanpa itu notifikasi dijadwalkan tetapi tidak pernah tampil.
/// 2. Android 12+ membatasi alarm presisi (SCHEDULE_EXACT_ALARM) — izinnya
///    harus diminta, dan penjadwalan presisi wajib punya fallback inexact.
/// 3. Semua jam pengingat obat harus dijadwalkan (bukan hanya yang pertama).
/// 4. Jadwal yang disimpan OS hilang setelah perangkat reboot bila manifes
///    tidak mendaftarkan `ScheduledNotificationBootReceiver`.
class MedicationReminderService {
  /// [enabled] = false mematikan SEMUA operasi (dipakai di web, di mana tidak
  /// ada penjadwal notifikasi OS). Dengan begitu `zonedSchedule` tidak pernah
  /// dipanggil di web tanpa perlu menyentuh setiap pemanggil.
  MedicationReminderService({bool enabled = true}) : _enabled = enabled;

  final bool _enabled;
  final Set<String> _lowStockNotified = {};

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  /// Kanal notifikasi pengingat obat (id dipakai juga di AndroidManifest).
  static const String _channelId = 'medication_reminders';
  static const String _channelName = 'Pengingat Obat';
  static const String _channelDescription =
      'Pengingat jadwal minum obat dari Malva';

  /// Id tetap untuk notifikasi uji coba dari layar Medication.
  static const int testNotificationId = 990001;

  void Function(String medicationId)? onNotificationTap;

  /// Siapkan plugin, buat kanal notifikasi, lalu MINTA IZIN.
  ///
  /// Aman dipanggil berulang (mis. setiap cold start): permintaan izin yang
  /// sudah pernah dijawab tidak memunculkan dialog lagi.
  Future<void> initialize() async {
    if (!_enabled) return;
    // WAJIB lewat initializeWib(): ia menginisialisasi database zona SEKALIGUS
    // memaksa zona lokal proses ke Asia/Jakarta. Memanggil
    // `tzdata.initializeTimeZones()` langsung akan mengembalikan zona lokal ke
    // Etc/UTC (bawaan paket), sehingga jadwal pengingat bergeser 7 jam.
    initializeWib();

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      // Izin TIDAK diminta otomatis di sini; diminta eksplisit lewat
      // [_requestPermissions] agar status izin bisa dilaporkan ke UI.
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    // Handler tap TUNGGAL (LocalNotificationRouter) dipakai bersama
    // PushNotificationService: tanpa ini handler yang terdaftar terakhir
    // menimpa yang lain sehingga tap pengingat obat bisa tidak melakukan apa
    // pun. Router meneruskan payload id obat ke [onNotificationTap].
    await _plugin.initialize(
      settings: initSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) =>
          LocalNotificationRouter.handlePayload(response.payload),
    );
    LocalNotificationRouter.onMedicationPayload =
        (String medicationId) => onNotificationTap?.call(medicationId);

    await _createChannel();
    await _requestPermissions();
  }

  Future<void> _createChannel() async {
    const androidChannel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: _channelDescription,
      importance: Importance.high,
    );
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(androidChannel);
  }

  /// Minta izin notifikasi (Android 13+) dan izin alarm presisi (Android 12+),
  /// serta izin alert/badge/sound di iOS.
  Future<void> _requestPermissions() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      try {
        await android.requestNotificationsPermission();
      } on Object {
        // Perangkat/OS lama tidak punya izin ini — bukan kegagalan fatal.
      }
      try {
        await android.requestExactAlarmsPermission();
      } on Object {
        // Tanpa izin ini penjadwalan jatuh ke mode inexact (tetap berbunyi).
      }
    }
    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    if (ios != null) {
      try {
        await ios.requestPermissions(alert: true, badge: true, sound: true);
      } on Object {
        // Abaikan: pengguna bisa mengaktifkan izin lewat Pengaturan.
      }
    }
  }

  /// Pastikan izin notifikasi aktif dan laporkan status akhirnya.
  ///
  /// Dipakai layar Medication untuk menampilkan "aktif / tidak aktif" dan
  /// menawarkan tombol aktifkan. Aman dipanggil berkali-kali.
  Future<bool> ensurePermissions() async {
    if (!_enabled) return false;
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      try {
        var enabled = await android.areNotificationsEnabled() ?? false;
        if (!enabled) {
          await android.requestNotificationsPermission();
          enabled = await android.areNotificationsEnabled() ?? false;
        }
        // Izin alarm presisi diminta lagi bila sebelumnya ditolak; kegagalan
        // di sini tidak mematikan pengingat (fallback inexact).
        try {
          await android.requestExactAlarmsPermission();
        } on Object {
          // diabaikan
        }
        return enabled;
      } on Object {
        return false;
      }
    }
    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    if (ios != null) {
      try {
        final granted = await ios.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        );
        return granted ?? true;
      } on Object {
        return false;
      }
    }
    // Platform lain (desktop/web) tidak dipakai untuk pengingat obat.
    return true;
  }

  /// Id notifikasi stabil untuk satu obat + satu jam pengingat.
  ///
  /// Memakai hash FNV-1a 31-bit atas `'<medicationId>#<index>'`, BUKAN
  /// `String.hashCode`: hashCode Dart tidak dijamin sama antar-run (seed acak)
  /// sehingga id yang dipakai untuk menjadwalkan bisa berbeda dengan id yang
  /// dipakai untuk membatalkan setelah aplikasi dibuka ulang. Hasil di-mask ke
  /// 31 bit agar sah sebagai `int` Android (32-bit).
  ///
  /// Tabrakan antar obat masih mungkin secara teoretis (ruang 31 bit), tetapi
  /// stabil dan jauh lebih jarang daripada `hashCode * 10`.
  static int _notificationId(String medicationId, int index) =>
      _stableHash('$medicationId#$index');

  /// Hash FNV-1a 31-bit (deterministik lintas platform & lintas run).
  static int _stableHash(String value) {
    var hash = 0x811c9dc5;
    for (final unit in value.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0x7fffffff;
    }
    // 0 tidak dipakai: sebagian platform memperlakukan id 0 secara khusus.
    return hash == 0 ? 1 : hash;
  }

  /// Id notifikasi versi LAMA (sebelum dukungan banyak jam pengingat).
  ///
  /// Dulu satu obat hanya punya satu notifikasi dengan `id: medicationId.hashCode`.
  /// Id itu tidak pernah dihasilkan lagi oleh [_notificationId], jadi harus
  /// dibatalkan eksplisit agar pengguna yang upgrade tidak menerima pengingat
  /// ganda pada jam pertama.
  static int _legacyNotificationId(String medicationId) =>
      medicationId.hashCode & 0x7fffffff;

  static NotificationDetails _notificationDetails() =>
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDescription,
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      );

  /// Jadwalkan pengingat harian untuk SEMUA jam milik [med].
  ///
  /// Sebelumnya hanya `med.reminders.first` yang dijadwalkan, sehingga obat
  /// dengan dua jam minum hanya mengingatkan sekali sehari.
  Future<void> scheduleMedicationReminder(Medication med) async {
    if (!_enabled) return;
    // Bersihkan id lama lebih dulu agar jadwal tidak dobel setelah edit.
    await cancelReminder(med.id);
    if (med.schedule != null) {
      await _scheduleRoutine(med);
      return;
    }
    if (med.reminders.isEmpty) return;

    for (var index = 0; index < med.reminders.length; index++) {
      final reminder = med.reminders[index];
      final scheduledDate = _nextOccurrence(reminder.time);
      final id = _notificationId(med.id, index);
      const title = 'Waktunya minum obat';
      final body = '${med.name} • ${med.dosage} • ${reminder.relationToMeal}';
      try {
        await _plugin.zonedSchedule(
          id: id,
          title: title,
          body: body,
          scheduledDate: scheduledDate,
          notificationDetails: _notificationDetails(),
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          matchDateTimeComponents: DateTimeComponents.time,
          payload: med.id,
        );
      } on Object {
        // Izin alarm presisi ditolak / tidak tersedia: pakai alarm inexact
        // supaya pengingat tetap berbunyi (mungkin beberapa menit bergeser).
        await _plugin.zonedSchedule(
          id: id,
          title: title,
          body: body,
          scheduledDate: scheduledDate,
          notificationDetails: _notificationDetails(),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          matchDateTimeComponents: DateTimeComponents.time,
          payload: med.id,
        );
      }
    }
  }

  /// Jadwalkan pengingat untuk sekumpulan obat (dipakai saat login/restore).
  Future<void> scheduleAll(Iterable<Medication> medications) async {
    if (!_enabled) return;
    final current = medications.toList(growable: false);
    await cancelObsoleteReminders(current.map((med) => med.id));
    for (final med in current) {
      try {
        await scheduleMedicationReminder(med);
        await showLowStockNotification(med);
      } on Object {
        // Satu obat gagal dijadwalkan tidak boleh menggagalkan sisanya.
      }
    }
  }

  /// Actual stock notification, once per low-stock period, with its own ID.
  Future<void> showLowStockNotification(Medication med) async {
    if (!_enabled) return;
    final id = _stableHash('${med.id}#stock');
    if (!med.needsRefill) {
      _lowStockNotified.remove(med.id);
      await _plugin.cancel(id: id);
      return;
    }
    if (!_lowStockNotified.add(med.id)) return;
    try {
      await _plugin.show(
          id: id,
          title: 'Stok obat hampir habis',
          body:
              '${med.name} tersisa ${med.currentStock} unit. Siapkan isi ulang.',
          notificationDetails: _notificationDetails(),
          payload: med.id);
    } on Object {
      _lowStockNotified.remove(med.id);
      rethrow;
    }
  }

  Future<void> _scheduleRoutine(Medication med) async {
    final routine = med.schedule!;
    final periodic = routine.intervalHours > 0 ||
        routine.intervalDays > 1 ||
        routine.intervalMonths > 0;
    final occurrences = routineOccurrences(routine, limit: periodic ? 60 : 70);
    final seen = <String>{};
    var index = 0;
    for (final date in occurrences) {
      if (!periodic && !seen.add('${date.weekday}:${date.hour}:${date.minute}'))
        continue;
      final id = _notificationId(med.id, index++);
      final repeat = periodic ? null : DateTimeComponents.dayOfWeekAndTime;
      final body =
          '${med.name} • ${med.dosage} • ${med.unitsPerDose} unit${med.reminders.firstOrNull?.relationToMeal.isNotEmpty == true ? ' • ${med.reminders.first.relationToMeal}' : ''}';
      try {
        await _plugin.zonedSchedule(
            id: id,
            title: 'Waktunya minum obat',
            body: body,
            scheduledDate: date,
            notificationDetails: _notificationDetails(),
            androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
            matchDateTimeComponents: repeat,
            payload: med.id);
      } on Object {
        await _plugin.zonedSchedule(
            id: id,
            title: 'Waktunya minum obat',
            body: body,
            scheduledDate: date,
            notificationDetails: _notificationDetails(),
            androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
            matchDateTimeComponents: repeat,
            payload: med.id);
      }
    }
  }

  /// Next occurrences are calculated from the persisted anchor, never the device zone.
  /// shortcut: arbitrary intervals queue 60 occurrences; replenish on app resume/refresh.
  static List<tz.TZDateTime> routineOccurrences(MedicationSchedule routine,
      {DateTime? now, int limit = 60}) {
    if (routine.times.isEmpty || routine.weekdays.isEmpty || limit < 1)
      return [];
    final base = toWib(now ?? wibNow());
    final start = toWib(routine.startAt);
    final result = <tz.TZDateTime>[];
    if (routine.intervalMonths > 0) {
      final elapsed = (base.year - start.year) * 12 + base.month - start.month;
      var cycle = elapsed < 0 ? 0 : elapsed ~/ routine.intervalMonths;
      final times = [...routine.times]..sort();
      for (var i = 0;
          i < limit * 7 + 7 && result.length < limit;
          i++, cycle++) {
        final month = wibFromParts(
            start.year, start.month + cycle * routine.intervalMonths, 1);
        final lastDay = wibFromParts(month.year, month.month + 1, 0).day;
        // Clamp each month from the original day, so Jan31→Feb28→Mar31.
        final day = start.day > lastDay ? lastDay : start.day;
        for (final time in times) {
          final parts = time.split(':');
          final candidate = wibFromParts(month.year, month.month, day,
              int.parse(parts[0]), int.parse(parts[1]));
          if (!candidate.isBefore(start) &&
              candidate.isAfter(base) &&
              routine.weekdays.contains(candidate.weekday))
            result.add(candidate);
          if (result.length == limit) break;
        }
      }
      return result;
    }
    if (routine.intervalHours > 0) {
      final interval = Duration(hours: routine.intervalHours);
      var candidate = tz.TZDateTime.from(start, wibLocation);
      if (!candidate.isAfter(base)) {
        final jumps =
            base.difference(candidate).inMinutes ~/ interval.inMinutes + 1;
        candidate = candidate.add(interval * jumps);
      }
      for (var i = 0;
          i < limit * 7 + 7 && result.length < limit;
          i++, candidate = candidate.add(interval)) {
        if (routine.weekdays.contains(candidate.weekday)) result.add(candidate);
      }
      return result;
    }
    final startDate = wibFromParts(start.year, start.month, start.day);
    final baseDate = wibFromParts(base.year, base.month, base.day);
    var date = baseDate.isBefore(startDate) ? startDate : baseDate;
    final times = routine.reminders('')
      ..sort((a, b) => (a.time.hour * 60 + a.time.minute)
          .compareTo(b.time.hour * 60 + b.time.minute));
    final step = routine.intervalDays > 1 ? routine.intervalDays : 1;
    final remainder = date.difference(startDate).inDays % step;
    if (remainder > 0)
      date = wibFromParts(date.year, date.month, date.day + step - remainder);
    for (var attempts = 0;
        attempts < limit * 7 + 7 && result.length < limit;
        attempts++,
        date = wibFromParts(date.year, date.month, date.day + step)) {
      if (!routine.weekdays.contains(date.weekday)) continue;
      if (routine.intervalDays > 1 &&
          date.difference(startDate).inDays % routine.intervalDays != 0)
        continue;
      for (final reminder in times) {
        final candidate = wibFromParts(date.year, date.month, date.day,
            reminder.time.hour, reminder.time.minute);
        if (candidate.isAfter(base) && !candidate.isBefore(start)) {
          result.add(candidate);
          if (result.length == limit) break;
        }
      }
    }
    return result;
  }

  /// OS alarms survive process restarts, so in-memory IDs cannot find removals.
  /// Plain medication-ID payloads are distinct from goal markers and push JSON.
  Future<void> cancelObsoleteReminders(
      Iterable<String> currentMedicationIds) async {
    if (!_enabled) return;
    final keep = currentMedicationIds.toSet();
    try {
      final pending = await _plugin.pendingNotificationRequests();
      for (final request in pending) {
        final payload = request.payload;
        if (payload == null ||
            payload.isEmpty ||
            keep.contains(payload) ||
            payload == LocalNotificationRouter.goalReminderPayload ||
            payload.trimLeft().startsWith('{')) continue;
        await _plugin.cancel(id: request.id);
      }
    } on Object {
      // Platform/permission failure must not prevent logout or fresh schedules.
    }
  }

  /// Tampilkan notifikasi uji coba agar pasien bisa memverifikasi sendiri
  /// bahwa izin + kanal notifikasi berfungsi.
  Future<void> showTestNotification() async {
    if (!_enabled) return;
    await _createChannel();
    await _plugin.show(
      id: testNotificationId,
      title: 'Pengingat obat aktif',
      body: 'Notifikasi pengingat obat Malva berfungsi.',
      notificationDetails: _notificationDetails(),
    );
  }

  /// Waktu pengingat berikutnya (hari ini bila belum lewat, besok bila lewat).
  tz.TZDateTime _nextOccurrence(TimeOfDay time) => nextReminderOccurrence(time);

  /// Perhitungan MURNI waktu pengingat berikutnya, selalu dalam zona WIB.
  ///
  /// [now] hanya untuk pengujian (default [wibNow]) agar test tidak
  /// bergantung pada jam/zona mesin uji.
  ///
  /// KENAPA TIDAK MEMAKAI ZONA LOKAL PROSES: zona lokal bawaan paket
  /// `timezone` adalah Etc/UTC, sehingga jam 10:00 yang dibangun di zona itu
  /// menjadi 10:00 UTC = 17:00 WIB — pengingat obat telat 7 jam (keluhan nyata
  /// pasien). Karena itu komponen tanggal DAN jam di sini selalu dibangun di
  /// [wibLocation] lewat [wibFromParts].
  ///
  /// Mengembalikan [tz.TZDateTime] ber-zona Asia/Jakarta, yang langsung dipakai
  /// `zonedSchedule(matchDateTimeComponents: DateTimeComponents.time)` sehingga
  /// pengulangan hariannya juga jatuh pada jam WIB yang sama.
  static tz.TZDateTime nextReminderOccurrence(
    TimeOfDay time, {
    DateTime? now,
  }) {
    final base = toWib(now ?? wibNow());
    var scheduled = wibFromParts(
      base.year,
      base.month,
      base.day,
      time.hour,
      time.minute,
    );
    if (!scheduled.isAfter(base)) {
      // Besok pada jam yang sama — dibangun ulang lewat komponen kalender
      // (bukan `add(Duration(days: 1))`) supaya tetap wall-clock WIB yang sama.
      scheduled = wibFromParts(
        base.year,
        base.month,
        base.day + 1,
        time.hour,
        time.minute,
      );
    }
    return scheduled;
  }

  /// Batalkan SEMUA jam pengingat milik satu obat.
  ///
  /// Membatalkan DUA kelompok id:
  /// 1. Id baru [_notificationId] untuk index 0..9 (ruang 10 pengingat/obat).
  /// 2. Id LEGACY [_legacyNotificationId] yang dipakai versi aplikasi sebelum
  ///    dukungan banyak jam pengingat. Id legacy TIDAK pernah dihasilkan oleh
  ///    [_notificationId] (kecuali kebetulan tabrakan), jadi tanpa langkah ini
  ///    pengguna yang upgrade tetap menerima notifikasi lama dan pengingat
  ///    berbunyi ganda pada jam pertama.
  Future<void> cancelReminder(String medicationId) async {
    if (!_enabled) return;
    try {
      final pending = await _plugin.pendingNotificationRequests();
      for (final request in pending) {
        if (request.payload == medicationId)
          await _plugin.cancel(id: request.id);
      }
    } on Object {/* Legacy IDs below still cover old daily alarms. */}
    for (var index = 0; index < 10; index++) {
      await _plugin.cancel(id: _notificationId(medicationId, index));
    }
    // Nilai hashCode hanya dipakai di sini karena versi lama memang
    // menjadwalkan dengan angka itu; penjadwalan baru selalu memakai hash
    // FNV-1a yang stabil.
    await _plugin.cancel(id: _legacyNotificationId(medicationId));
  }

  /// Batalkan reminder untuk sekumpulan obat.
  ///
  /// Dipakai saat logout. Penjadwalan reminder dilakukan oleh OS, sehingga
  /// notifikasinya tetap berbunyi walau pengguna sudah keluar — di perangkat
  /// yang dipakai bergantian, jadwal obat akun lama jadi bocor ke akun
  /// berikutnya. Sengaja memakai cancel(id) per obat, BUKAN cancelAll(), agar
  /// notifikasi lain (mis. pesan chat) tidak ikut terhapus.
  Future<void> cancelRemindersFor(Iterable<String> medicationIds) async {
    if (!_enabled) return;
    for (final id in medicationIds) {
      await cancelReminder(id);
      await _plugin.cancel(id: _stableHash('$id#stock'));
      _lowStockNotified.remove(id);
    }
  }
}
