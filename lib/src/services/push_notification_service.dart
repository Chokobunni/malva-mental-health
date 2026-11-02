import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import '../models.dart';
import '../time/wib.dart';
import 'malva_api_client.dart';

@pragma('vm:entry-point')
Future<void> _onBackgroundMessage(RemoteMessage message) async {
  await Firebase.initializeApp();
}

class PushNotificationService {
  PushNotificationService({
    required this.apiClient,
    required this.navigatorKey,
  });

  final MalvaApiClient apiClient;
  final GlobalKey<NavigatorState> navigatorKey;

  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  /// Initialize the service: local notifications, channels, handlers.
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    // Inisialisasi database zona + paksa zona lokal proses ke WIB sekaligus.
    // Jangan panggil `tzdata.initializeTimeZones()` langsung: itu mengembalikan
    // zona lokal ke Etc/UTC sehingga jadwal notifikasi bergeser 7 jam.
    initializeWib();

    // ── Local notifications setup ──
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
    await _localNotifications.initialize(
      settings: initSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

    // ── Android notification channels ──
    await _createAndroidChannels();

    // ── FCM handlers ──
    FirebaseMessaging.onBackgroundMessage(_onBackgroundMessage);
    FirebaseMessaging.onMessage.listen(_onForegroundMessage);
    FirebaseMessaging.onMessageOpenedApp.listen(_onMessageOpenedApp);

    // ── Check for cold-start notification tap ──
    final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
    if (initialMessage != null) {
      _handleNotificationNavigation(initialMessage.data);
    }
  }

  // ──────────────────────────────────────────────────────────────
  // Android notification channels
  // ──────────────────────────────────────────────────────────────

  Future<void> _createAndroidChannels() async {
    final androidPlugin =
        _localNotifications.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    if (androidPlugin == null) return;

    await androidPlugin.createNotificationChannel(
      const AndroidNotificationChannel(
        'crisis_alerts',
        'Crisis Alerts',
        description:
            'Urgent crisis notifications requiring immediate attention',
        importance: Importance.max,
        enableVibration: true,
        playSound: true,
      ),
    );

    await androidPlugin.createNotificationChannel(
      const AndroidNotificationChannel(
        'follow_ups',
        'Follow-ups',
        description: 'Follow-up notifications from your care team',
        importance: Importance.defaultImportance,
      ),
    );

    await androidPlugin.createNotificationChannel(
      const AndroidNotificationChannel(
        'medication_reminders',
        'Medication Reminders',
        description: 'Reminders to take your medication',
        importance: Importance.defaultImportance,
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────
  // Token management
  // ──────────────────────────────────────────────────────────────

  Future<void> registerDeviceToken(AuthSession session) async {
    final accessToken = session.accessToken;
    if (accessToken == null || accessToken.isEmpty) return;

    try {
      await Firebase.initializeApp();
      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission();

      // Listen for token refreshes
      messaging.onTokenRefresh.listen((newToken) {
        _sendTokenToBackend(accessToken, newToken);
      });

      final token = await messaging.getToken();
      if (token == null || token.isEmpty) return;
      await _sendTokenToBackend(accessToken, token);
    } on Object catch (error) {
      if (kDebugMode) debugPrint('FCM token registration failed: $error');
    }
  }

  Future<void> _sendTokenToBackend(String accessToken, String token) async {
    try {
      await apiClient.saveDeviceToken(
        accessToken: accessToken,
        platform: defaultTargetPlatform.name,
        token: token,
      );
    } on Object catch (error) {
      if (kDebugMode) {
        debugPrint('Failed to send FCM token to backend: $error');
      }
    }
  }

  // ──────────────────────────────────────────────────────────────
  // Foreground message handler
  // ──────────────────────────────────────────────────────────────

  void _onForegroundMessage(RemoteMessage message) {
    final notification = message.notification;
    if (notification == null) return;

    final data = message.data;
    final channel = _channelForType(data['type']);

    final androidDetails = AndroidNotificationDetails(
      channel,
      _channelName(channel),
      importance: channel == 'crisis_alerts'
          ? Importance.max
          : Importance.defaultImportance,
      priority:
          channel == 'crisis_alerts' ? Priority.high : Priority.defaultPriority,
    );
    const iosDetails = DarwinNotificationDetails();

    _localNotifications.show(
      id: _notificationIdFor(data),
      title: notification.title,
      body: notification.body,
      notificationDetails:
          NotificationDetails(android: androidDetails, iOS: iosDetails),
      payload: jsonEncode(data),
    );
  }

  /// ID notifikasi deterministik dari data peristiwa.
  ///
  /// Dulu memakai `notification.hashCode` (unik per pengiriman), sehingga
  /// peristiwa yang sama yang tiba dua kali menumpuk menjadi dua baris di
  /// shade. Dengan ID stabil per (kind, session_id, notification_id,
  /// patient_id), pengiriman ulang peristiwa yang sama MENIMPA notifikasi
  /// sebelumnya — satu baris per peristiwa.
  int _notificationIdFor(Map<String, dynamic> data) {
    final parts = <String>[
      (data['kind'] ?? data['type'] ?? '').toString(),
      (data['session_id'] ?? '').toString(),
      (data['notification_id'] ?? '').toString(),
      (data['patient_id'] ?? '').toString(),
    ];
    final stableKey = parts.join('|');
    return stableKey.hashCode & 0x7fffffff;
  }

  // ──────────────────────────────────────────────────────────────
  // Notification tap handler
  // ──────────────────────────────────────────────────────────────

  void _onNotificationTapped(NotificationResponse response) {
    if (response.payload == null) return;
    try {
      final data = Map<String, dynamic>.from(
        jsonDecode(response.payload!) as Map,
      );
      _handleNotificationNavigation(data);
    } on Object catch (error) {
      if (kDebugMode) {
        debugPrint('Error parsing notification payload: $error');
      }
    }
  }

  void _onMessageOpenedApp(RemoteMessage message) {
    _handleNotificationNavigation(message.data);
  }

  // ──────────────────────────────────────────────────────────────
  // Navigation based on notification payload
  // ──────────────────────────────────────────────────────────────

  void _handleNotificationNavigation(Map<String, dynamic> data) {
    final type = data['type'] as String?;
    final route = _routeForType(type, data);
    if (route == null) return;

    // Beranda: tap notifikasi TIDAK boleh menumpuk shell beranda baru di atas
    // beranda yang sedang tampil (tap berulang = tumpukan bertambah, tombol
    // back terasa rusak). Bersihkan tumpukan sampai root lalu buka satu
    // beranda. Rute lain tetap pushNamed seperti sebelumnya.
    if (route == '/home') {
      navigatorKey.currentState
          ?.pushNamedAndRemoveUntil('/home', (route) => route.isFirst);
      return;
    }

    navigatorKey.currentState?.pushNamed(route);
  }

  String? _routeForType(String? type, Map<String, dynamic> data) {
    return switch (type) {
      'crisis_alert' => '/crisis-alert',
      'follow_up' => '/home',
      'medication_reminder' => '/medication',
      'screening_result' => '/assessment/result',
      // Notifikasi sesi video (link Meet belum ada / sudah siap): satu-satunya
      // aksi yang diminta adalah membuka detail sesi, dan aplikasi belum punya
      // rute detail sesi. Rute paling aman yang sudah ada adalah beranda
      // per-peran ('/home'): pasien melihat daftar sesinya, profesional melihat
      // dasbor sesi. Tanpa pemetaan ini tap notifikasi tidak melakukan apa pun
      // (dead-end) padahal notifikasi itu meminta tindakan.
      'session_meet_missing' => '/home',
      'session_meet_ready' => '/home',
      _ => null,
    };
  }

  // ──────────────────────────────────────────────────────────────
  // Helpers
  // ──────────────────────────────────────────────────────────────

  String _channelForType(String? type) {
    return switch (type) {
      'crisis_alert' => 'crisis_alerts',
      'medication_reminder' => 'medication_reminders',
      _ => 'follow_ups',
    };
  }

  String _channelName(String channel) {
    return switch (channel) {
      'crisis_alerts' => 'Crisis Alerts',
      'medication_reminders' => 'Medication Reminders',
      _ => 'Follow-ups',
    };
  }

  /// Programmatically show a local notification (e.g. for scheduled reminders).
  Future<void> showLocalNotification({
    required int id,
    required String title,
    required String body,
    String? channel,
    String? payload,
    DateTime? scheduledTime,
  }) async {
    final resolvedChannel = channel ?? 'follow_ups';
    final androidDetails = AndroidNotificationDetails(
      resolvedChannel,
      _channelName(resolvedChannel),
      importance: resolvedChannel == 'crisis_alerts'
          ? Importance.max
          : Importance.defaultImportance,
      priority: resolvedChannel == 'crisis_alerts'
          ? Priority.high
          : Priority.defaultPriority,
    );
    const iosDetails = DarwinNotificationDetails();
    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    if (scheduledTime != null) {
      // Selalu konversi ke zona WIB — bukan zona lokal proses (bawaan paket
      // timezone adalah Etc/UTC, yang membuat notifikasi bergeser 7 jam).
      final tzScheduled = tz.TZDateTime.from(scheduledTime, wibLocation);
      await _localNotifications.zonedSchedule(
        id: id,
        title: title,
        body: body,
        scheduledDate: tzScheduled,
        notificationDetails: details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload: payload,
      );
    } else {
      await _localNotifications.show(
          id: id,
          title: title,
          body: body,
          notificationDetails: details,
          payload: payload);
    }
  }
}
