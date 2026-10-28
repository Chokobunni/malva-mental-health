import 'dart:async';

import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../models.dart';

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
  MedicationReminderService();

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
    tz.initializeTimeZones();

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

    await _plugin.initialize(
      settings: initSettings,
      onDidReceiveNotificationResponse: _onNotificationResponse,
    );

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

  void _onNotificationResponse(NotificationResponse response) {
    final payload = response.payload;
    if (payload != null && payload.isNotEmpty) {
      onNotificationTap?.call(payload);
    }
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
    // Bersihkan id lama lebih dulu agar jadwal tidak dobel setelah edit.
    await cancelReminder(med.id);
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
    for (final med in medications) {
      try {
        await scheduleMedicationReminder(med);
      } on Object {
        // Satu obat gagal dijadwalkan tidak boleh menggagalkan sisanya.
      }
    }
  }

  /// Tampilkan notifikasi uji coba agar pasien bisa memverifikasi sendiri
  /// bahwa izin + kanal notifikasi berfungsi.
  Future<void> showTestNotification() async {
    await _createChannel();
    await _plugin.show(
      id: testNotificationId,
      title: 'Pengingat obat aktif',
      body: 'Notifikasi pengingat obat Malva berfungsi.',
      notificationDetails: _notificationDetails(),
    );
  }

  /// Waktu pengingat berikutnya (hari ini bila belum lewat, besok bila lewat).
  tz.TZDateTime _nextOccurrence(TimeOfDay time) {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      time.hour,
      time.minute,
    );
    if (!scheduled.isAfter(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
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
    for (final id in medicationIds) {
      await cancelReminder(id);
    }
  }
}
