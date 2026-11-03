import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../services/local_notification_router.dart';
import '../../time/wib.dart';
import '../contracts/ports.dart';

/// [GoalReminderScheduler] mobile: penjadwal notifikasi lokal untuk pengingat
/// goals harian.
///
/// Berkas ini berada di `lib/src/platform/io/` karena menyentuh plugin
/// `flutter_local_notifications` — gate isolasi platform melarang impor plugin
/// dari kode bersama (`lib/src/services/**`).
class LocalNotificationGoalReminderScheduler implements GoalReminderScheduler {
  LocalNotificationGoalReminderScheduler();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _permissionsRequested = false;

  /// Kanal notifikasi pengingat goals (nama harus sama di semua tempat).
  static const String channelId = 'goal_reminders';
  static const String channelName = 'Pengingat Goals';
  static const String channelDescription =
      'Pengingat harian untuk mencatat progres goals di Malva';

  @override
  Future<void> initialize() async {
    // WAJIB lewat initializeWib(): memaksa zona lokal proses ke Asia/Jakarta.
    initializeWib();

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    // Handler tap TUNGGAL bersama push & pengingat obat.
    await _plugin.initialize(
      settings: initSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) =>
          LocalNotificationRouter.handlePayload(response.payload),
    );

    await _createChannel();
    await _requestPermissionsOnce();
  }

  Future<void> _createChannel() async {
    const androidChannel = AndroidNotificationChannel(
      channelId,
      channelName,
      description: channelDescription,
      importance: Importance.defaultImportance,
    );
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(androidChannel);
  }

  Future<void> _requestPermissionsOnce() async {
    if (_permissionsRequested) return;
    _permissionsRequested = true;
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      try {
        final enabled = await android.areNotificationsEnabled() ?? false;
        if (!enabled) {
          await android.requestNotificationsPermission();
        }
      } on Object {
        // Perangkat/OS lama tidak punya izin ini — bukan kegagalan fatal.
      }
    }
    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    if (ios != null) {
      try {
        await ios.requestPermissions(alert: true, badge: true, sound: true);
      } on Object {
        // Pengguna bisa mengaktifkan izin lewat Pengaturan.
      }
    }
  }

  @override
  Future<void> scheduleDaily({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledAt,
    required String payload,
  }) async {
    // Konversi eksplisit ke WIB: bukan zona lokal proses (bawaan paket
    // timezone adalah Etc/UTC → jadwal bergeser 7 jam).
    final scheduled = tz.TZDateTime.from(scheduledAt, wibLocation);
    await _plugin.zonedSchedule(
      id: id,
      title: title,
      body: body,
      scheduledDate: scheduled,
      notificationDetails: _notificationDetails(),
      // Inexact: pengingat harian tidak butuh presisi detik dan tidak
      // bergantung pada izin SCHEDULE_EXACT_ALARM (yang bisa ditolak).
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
      payload: payload,
    );
  }

  @override
  Future<void> cancel(int id) async {
    try {
      await _plugin.cancel(id: id);
    } on Object catch (error) {
      if (kDebugMode) debugPrint('Gagal membatalkan pengingat goals: $error');
    }
  }

  static NotificationDetails _notificationDetails() =>
      const NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          channelName,
          channelDescription: channelDescription,
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
        iOS: DarwinNotificationDetails(),
      );
}
