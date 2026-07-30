import 'dart:async';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../models.dart';

class MedicationReminderService {
  MedicationReminderService();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  void Function(String medicationId)? onNotificationTap;

  Future<void> initialize() async {
    tz.initializeTimeZones();

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _plugin.initialize(
      settings: initSettings,
      onDidReceiveNotificationResponse: _onNotificationResponse,
    );

    const androidChannel = AndroidNotificationChannel(
      'medication_reminders',
      'Medication Reminders',
      description: 'Reminder untuk minum obat',
      importance: Importance.high,
    );
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(androidChannel);
  }

  void _onNotificationResponse(NotificationResponse response) {
    final payload = response.payload;
    if (payload != null && payload.isNotEmpty) {
      onNotificationTap?.call(payload);
    }
  }

  Future<void> scheduleMedicationReminder(Medication med) async {
    if (med.reminders.isEmpty) return;

    final reminder = med.reminders.first;
    final now = tz.TZDateTime.now(tz.local);

    var scheduledDate = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      reminder.time.hour,
      reminder.time.minute,
    );

    if (scheduledDate.isBefore(now)) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }

    await _plugin.zonedSchedule(
      id: med.id.hashCode,
      title: 'Time to take ${med.name}',
      body: '${med.dosage} - ${reminder.relationToMeal}',
      scheduledDate: scheduledDate,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'medication_reminders',
          'Medication Reminders',
          channelDescription: 'Reminder untuk minum obat',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
      payload: med.id,
    );
  }

  Future<void> cancelReminder(String medicationId) async {
    await _plugin.cancel(id: medicationId.hashCode);
  }

  Future<void> cancelAllReminders() async {
    await _plugin.cancelAll();
  }
}
