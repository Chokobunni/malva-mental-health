import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/widgets.dart' show GlobalKey, NavigatorState;

import '../../services/push_notification_service.dart';
import '../contracts/ports.dart';

/// [PushRegistrar] mobile: membungkus [PushNotificationService] (kanal Android,
/// handler foreground/background, navigasi tap). Token FCM diambil langsung
/// dari `FirebaseMessaging`.
class FcmPushRegistrar implements PushRegistrar {
  FcmPushRegistrar(
    dynamic apiClient, {
    GlobalKey<NavigatorState>? navigatorKey,
  })  : _apiClient = apiClient,
        _navigatorKey = navigatorKey ?? GlobalKey<NavigatorState>();

  final dynamic _apiClient;
  final GlobalKey<NavigatorState> _navigatorKey;

  late final PushNotificationService _service = PushNotificationService(
    apiClient: _apiClient,
    navigatorKey: _navigatorKey,
  );

  @override
  bool get canRegister => true;

  @override
  void Function(String route)? onTap;

  @override
  Future<void> initialize(
      {void Function(String route)? onForegroundTap}) async {
    onTap = onForegroundTap;
    await _service.initialize();
  }

  @override
  Future<void> requestPermission() async {
    await FirebaseMessaging.instance.requestPermission();
  }

  @override
  Future<String?> obtainToken() async {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp();
    }
    return FirebaseMessaging.instance.getToken();
  }

  @override
  Stream<String> get tokenRefreshes =>
      FirebaseMessaging.instance.onTokenRefresh;
}
