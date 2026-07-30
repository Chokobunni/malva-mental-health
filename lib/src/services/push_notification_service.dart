import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../models.dart';
import 'malva_api_client.dart';

class PushNotificationService {
  PushNotificationService({
    required this.apiClient,
  });

  final MalvaApiClient apiClient;

  Future<void> registerDeviceToken(AuthSession session) async {
    final accessToken = session.accessToken;
    if (accessToken == null || accessToken.isEmpty) return;

    try {
      await Firebase.initializeApp();
      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission();
      final token = await messaging.getToken();
      if (token == null || token.isEmpty) return;
      await apiClient.saveDeviceToken(
        accessToken: accessToken,
        platform: defaultTargetPlatform.name,
        token: token,
      );
    } on Object catch (error) {
      debugPrint('FCM belum aktif atau gagal registrasi token: $error');
    }
  }
}
