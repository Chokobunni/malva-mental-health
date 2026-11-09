import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:malva_mental_health/src/models.dart';
import 'package:malva_mental_health/src/services/medication_reminder_service.dart';
import 'package:malva_mental_health/src/time/wib.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dexterous.com/flutter/local_notifications');
  final shows = <Map>[];
  final scheduled = <Map>[];
  final cancelled = <int>[];
  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    FlutterLocalNotificationsPlatform.instance =
        AndroidFlutterLocalNotificationsPlugin();
    shows.clear();
    scheduled.clear();
    cancelled.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'initialize') return true;
      if (call.method == 'pendingNotificationRequests') return [];
      if (call.method == 'show') shows.add(call.arguments as Map);
      if (call.method == 'zonedSchedule') scheduled.add(call.arguments as Map);
      if (call.method == 'cancel')
        cancelled.add((call.arguments as Map)['id'] as int);
      return null;
    });
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });
  Medication med(int stock) => Medication(
      id: 'med1',
      name: 'Aripiprazole',
      dosage: '10 mg',
      form: 'Tablet',
      reminders: const [
        MedicationReminder(
            time: TimeOfDay(hour: 8, minute: 0),
            relationToMeal: 'Setelah makan')
      ],
      currentStock: stock,
      alertBelow: 3,
      source: 'prescription');
  test(
      'stock reaches three emits one real notification distinct from dose alarms and rearms after refill',
      () async {
    final service = MedicationReminderService();
    await service.initialize();
    await service.scheduleAll([med(4)]);
    expect(shows, isEmpty);
    expect(scheduled, isNotEmpty);
    await service.scheduleAll([med(3)]);
    expect(shows, hasLength(1));
    expect(shows.single['body'], contains('tersisa 3 unit'));
    expect(shows.single['id'], isNot(scheduled.first['id']));
    await service.scheduleAll([med(2)]);
    expect(shows, hasLength(1));
    await service.scheduleAll([med(30)]);
    await service.scheduleAll([med(3)]);
    expect(shows, hasLength(2));
  });
  test(
      'weekly selection schedules every selected time and periodic routines queue anchored occurrences without daily repetition',
      () async {
    final service = MedicationReminderService();
    await service.initialize();
    final routine = MedicationSchedule(
        times: ['08:00', '20:00'],
        weekdays: [1, 3, 5],
        startAt: wibFromParts(2030, 1, 1, 8),
        refillEnabled: false);
    await service.scheduleAll([med(30).copyWith(schedule: routine)]);
    expect(scheduled, hasLength(6));
    expect(
        scheduled.every((m) =>
            m['matchDateTimeComponents'] ==
            DateTimeComponents.dayOfWeekAndTime.index),
        isTrue);
    scheduled.clear();
    final periodic = MedicationSchedule(
        times: ['08:00'],
        weekdays: [1, 2, 3, 4, 5, 6, 7],
        startAt: wibFromParts(2030, 1, 1, 8),
        intervalHours: 8,
        refillEnabled: false);
    await service.scheduleAll([med(1).copyWith(schedule: periodic)]);
    expect(scheduled, hasLength(60));
    expect(shows, isEmpty);
    expect(
        scheduled.every((m) => m['matchDateTimeComponents'] == null), isTrue);
  });
}
