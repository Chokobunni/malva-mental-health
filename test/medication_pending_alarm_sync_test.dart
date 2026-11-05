import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:malva_mental_health/src/services/medication_reminder_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dexterous.com/flutter/local_notifications');
  final cancelled = <int>[];
  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    FlutterLocalNotificationsPlatform.instance =
        AndroidFlutterLocalNotificationsPlugin();
    cancelled.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'initialize') return true;
      if (call.method == 'pendingNotificationRequests')
        return [
          {
            'id': 101,
            'title': 'Synthetic',
            'body': 'Synthetic',
            'payload': 'removed-medication'
          },
          {
            'id': 102,
            'title': 'Synthetic',
            'body': 'Synthetic',
            'payload': 'goal_reminder'
          },
          {
            'id': 103,
            'title': 'Synthetic',
            'body': 'Synthetic',
            'payload': '{"kind":"chat_message"}'
          },
          {
            'id': 104,
            'title': 'Synthetic',
            'body': 'Synthetic',
            'payload': null
          },
        ];
      if (call.method == 'cancel') {
        cancelled.add((call.arguments as Map)['id'] as int);
      }
      if (call.method == 'cancelAll')
        fail('must never cancel goals/chat with a global operation');
      return null;
    });
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
      'cold-start empty medication sync removes OS alarms absent from server, preserving goals/chat',
      () async {
    final service = MedicationReminderService();
    await service.initialize();
    await service.scheduleAll([]);
    expect(cancelled, [101]);
  });
}
