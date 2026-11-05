import 'dart:convert';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/services.dart';

import '../../models.dart';
import '../contracts/ports.dart';
import '../../time/wib.dart';
import '../../services/local_notification_router.dart';
import '../../services/malva_api_client.dart';
import '../../services/push_notification_service.dart';
import '../../services/server_clock.dart';

/// Validates the persisted account and live session before background display.
class BackgroundChatDelivery {
  BackgroundChatDelivery({required this.apiClient, required this.secureStore});

  final MalvaApiClient apiClient;
  final SecureStore secureStore;

  static Future<void> clearPostedNotifications() async {
    try {
      // Native NotificationManager only: plugin.cancelAll would also delete
      // valid future medicine/goals alarms.
      await const MethodChannel('malva/notifications')
          .invokeMethod<void>('clearPosted');
    } on Object {
      // Non-Android hosts have no native shade cleanup channel.
    }
  }

  Future<void> deliver(Map<String, dynamic> data) async {
    if (PushNotificationService.eventKindOf(data) != 'chat_message') return;
    try {
      initializeWib();
      final saved = await secureStore.read('malva_active_session');
      if (saved == null) return;
      final map = jsonDecode(saved) as Map<String, dynamic>;
      final role = switch (map['role']) {
        'patient' => UserRole.patient,
        'professional' => UserRole.professional,
        _ => null,
      };
      if (role == null) return;
      final session = AuthSession(
        role: role,
        identifier: map['identifier']?.toString() ?? '',
        displayName: map['displayName']?.toString() ?? '',
        backendUserId: map['backendUserId']?.toString(),
        accessToken: map['accessToken']?.toString(),
      );
      if (!PushNotificationService.isRemoteChatForSession(data, session))
        return;
      if (!await isActiveSession(apiClient, data, session)) return;
      final plugin = FlutterLocalNotificationsPlugin();
      await plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(
              requestAlertPermission: false,
              requestBadgePermission: false,
              requestSoundPermission: false),
        ),
        onDidReceiveNotificationResponse: (response) =>
            LocalNotificationRouter.handlePayload(response.payload),
      );
      await plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(const AndroidNotificationChannel(
            MalvaNotificationChannels.updates,
            'Pesan Chat Malva',
            importance: Importance.defaultImportance,
          ));
      // Logout/account switches may happen while the server or plugin awaits.
      if (await secureStore.read('malva_active_session') != saved) return;
      final text = (data['text'] ?? '').toString().trim();
      final sender = (data['sender_name'] ?? '').toString().trim();
      await plugin.show(
        id: PushNotificationService.notificationIdFor(data),
        title: sender.isEmpty ? 'Pesan baru' : sender,
        body: text.isEmpty
            ? 'Anda menerima pesan baru.'
            : text.length > 120
                ? '${text.substring(0, 120)}…'
                : text,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
              MalvaNotificationChannels.updates, 'Pesan Chat Malva',
              importance: Importance.defaultImportance),
          iOS: DarwinNotificationDetails(),
        ),
        payload: jsonEncode(data),
      );
    } on Object {
      // Offline, expired credentials or malformed legacy payload: stay silent.
    }
  }

  static Future<bool> isActiveSession(MalvaApiClient apiClient,
      Map<String, dynamic> data, AuthSession session) async {
    final sessions = await apiClient.listCareSessions(
        accessToken: session.accessToken!, scope: 'ongoing');
    final now = ServerClock.now();
    return sessions.any((item) {
      final start = item.scheduledDateTime;
      return item.id == data['session_id'] &&
          item.patientId == data['patient_id'] &&
          item.professionalId == data['professional_id'] &&
          (item.status == 'scheduled' || item.status == 'completed') &&
          start != null &&
          !now.isBefore(start.subtract(const Duration(minutes: 10))) &&
          now.isBefore(start.add(Duration(minutes: item.durationMinutes)));
    });
  }
}
