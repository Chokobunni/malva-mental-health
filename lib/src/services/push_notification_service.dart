import 'dart:async';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import '../models.dart';
import '../platform/platform_factory.dart';
import '../time/wib.dart';
import '../platform/background_chat_delivery.dart';
import 'local_notification_router.dart';
import 'malva_api_client.dart';

@pragma('vm:entry-point')
Future<void> _onBackgroundMessage(RemoteMessage message) async {
  // Isolat background punya instance Firebase sendiri; initialize hanya boleh
  // dipanggil bila belum ada agar tidak melempar "duplicate-app".
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp();
  }
  await BackgroundChatDelivery(
    apiClient: MalvaApiClient(),
    secureStore: createSecureStore(),
  ).deliver(message.data);
}

/// Kanal notifikasi Android yang dipakai Malva.
///
/// `malva_updates` WAJIB ada karena backend mengirim push dengan
/// `channel_id = "malva_updates"` (`backend/internal/notify/provider.go`).
/// Tanpa kanal ini push background jatuh ke kanal fallback yang tidak
/// terkelola (importance/nama default, tidak bisa diatur pengguna).
abstract final class MalvaNotificationChannels {
  static const String updates = 'malva_updates';
  static const String medication = 'medication_reminders';
  static const String crisis = 'crisis_alerts';
  static const String followUps = 'follow_ups';

  /// Nama kanal yang tampil di pengaturan Android. Nama pengingat obat HARUS
  /// sama dengan yang dibuat `MedicationReminderService` — sebelumnya kedua
  /// service memakai nama berbeda ("Medication Reminders" vs "Pengingat Obat")
  /// sehingga nama kanal bergantung urutan inisialisasi.
  static String name(String channel) => switch (channel) {
        updates => 'Pembaruan Malva',
        medication => 'Pengingat Obat',
        crisis => 'Crisis Alerts',
        _ => 'Follow-ups',
      };
}

class PushNotificationService {
  PushNotificationService({
    required this.apiClient,
    required this.navigatorKey,
    this.activeChatPeer,
    this.currentSession,
    Future<String?> Function()? fcmTokenProvider,
  }) : _fcmTokenProvider = fcmTokenProvider;

  final MalvaApiClient apiClient;
  final GlobalKey<NavigatorState> navigatorKey;

  /// Peer chat yang SEDANG dibuka (null bila tidak ada). Dipakai menekan
  /// notifikasi chat untuk percakapan yang sedang dilihat pengguna.
  final String? Function()? activeChatPeer;
  final AuthSession? Function()? currentSession;

  /// Sumber token FCM perangkat. Bisa diganti di test agar alur
  /// [unregisterDeviceToken] dapat diuji tanpa Firebase nyata. Bila null,
  /// dipakai `FirebaseMessaging.instance.getToken()`.
  final Future<String?> Function()? _fcmTokenProvider;

  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  /// True hanya setelah inisialisasi benar-benar selesai.
  bool _initialized = false;

  /// Future inisialisasi yang sedang berjalan. Bila gagal, di-reset ke null
  /// agar percobaan berikutnya (mis. setelah jaringan pulih) bisa mencoba lagi
  /// — sebelumnya `_initialized = true` di awal membuat kegagalan pertama
  /// mengunci service selamanya.
  Future<void>? _initFuture;
  Map<String, dynamic>? _pendingInitialNavigation;
  bool _initialNavigationFrameQueued = false;

  /// User yang token-nya sudah terdaftar pada proses ini.
  String? _registeredUserId;
  UserRole? _registeredRole;
  int _registrationGeneration = 0;
  Future<void> _deviceTokenWork = Future<void>.value();
  AuthSession? _pendingRegistrationSession;
  Future<void>? _pendingRegistration;

  /// Listener refresh token yang aktif (dibatalkan sebelum mendaftar ulang).
  StreamSubscription<String>? _tokenRefreshSub;

  /// Izin notifikasi hanya diminta sekali per proses agar tidak memunculkan
  /// dialog berulang setiap login.
  bool _permissionRequested = false;

  /// True bila inisialisasi sudah selesai (dipakai test/diagnostik).
  bool get isInitialized => _initialized;

  /// User yang token-nya terdaftar pada proses ini (dipakai test untuk
  /// memverifikasi `resetRegistration` setelah `unregisterDeviceToken`).
  @visibleForTesting
  String? get registeredUserId => _registeredUserId;

  /// Initialize the service: local notifications, channels, handlers.
  ///
  /// Idempoten: pemanggilan berulang memakai future yang sama, dan kegagalan
  /// TIDAK mengunci service (future di-reset sehingga bisa dicoba lagi).
  Future<void> initialize() {
    if (_initialized) return Future<void>.value();
    return _initFuture ??= _initializeOnce();
  }

  Future<void> _initializeOnce() async {
    try {
      // Inisialisasi database zona + paksa zona lokal proses ke WIB sekaligus.
      // Jangan panggil `tzdata.initializeTimeZones()` langsung: itu
      // mengembalikan zona lokal ke Etc/UTC sehingga jadwal notifikasi
      // bergeser 7 jam.
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

      // Handler tap TUNGGAL untuk push maupun pengingat obat (lihat
      // LocalNotificationRouter). Tanpa ini kedua service saling menimpa.
      await _localNotifications.initialize(
        settings: initSettings,
        onDidReceiveNotificationResponse: (NotificationResponse response) =>
            LocalNotificationRouter.handlePayload(response.payload),
      );

      LocalNotificationRouter.onPushPayload =
          _handleRemoteNotificationNavigation;
      LocalNotificationRouter.openMedicationScreen =
          () => navigatorKey.currentState?.pushNamed('/medication');

      await _createAndroidChannels();

      final localLaunch =
          await _localNotifications.getNotificationAppLaunchDetails();
      final launchPayload = localLaunch?.notificationResponse?.payload;
      if (localLaunch?.didNotificationLaunchApp == true &&
          launchPayload != null) {
        try {
          final data = jsonDecode(launchPayload);
          if (data is Map)
            _queueInitialNavigation(Map<String, dynamic>.from(data));
        } on FormatException {
          // Non-JSON medicine/goals payloads use their existing local router.
        }
      }

      FirebaseMessaging.onBackgroundMessage(_onBackgroundMessage);
      FirebaseMessaging.onMessage.listen(_onForegroundMessage);
      FirebaseMessaging.onMessageOpenedApp.listen(_onMessageOpenedApp);

      final initialMessage =
          await FirebaseMessaging.instance.getInitialMessage();
      if (initialMessage != null) {
        _queueInitialNavigation(initialMessage.data);
      }

      _initialized = true;
    } on Object {
      // Biarkan pemanggil berikutnya mencoba lagi.
      _initFuture = null;
      rethrow;
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
        MalvaNotificationChannels.crisis,
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
        MalvaNotificationChannels.followUps,
        'Follow-ups',
        description: 'Follow-up notifications from your care team',
        importance: Importance.defaultImportance,
      ),
    );

    await androidPlugin.createNotificationChannel(
      const AndroidNotificationChannel(
        MalvaNotificationChannels.medication,
        'Pengingat Obat',
        description: 'Pengingat jadwal minum obat dari Malva',
        importance: Importance.defaultImportance,
      ),
    );

    // Kanal yang dipakai backend untuk push chat & pembaruan lain.
    await androidPlugin.createNotificationChannel(
      const AndroidNotificationChannel(
        MalvaNotificationChannels.updates,
        'Pembaruan Malva',
        description: 'Pesan chat dan pembaruan dari Malva',
        importance: Importance.defaultImportance,
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────
  // Token management
  // ──────────────────────────────────────────────────────────────

  /// Daftarkan token FCM perangkat untuk sesi ini.
  ///
  /// Pengaman yang dipasang (akar notifikasi berulang/ganda):
  /// 1. User yang sama tidak didaftarkan dua kali dalam satu proses — dulu
  ///    `_restorePersistedSession` dan listener auth sama-sama memanggilnya.
  /// 2. Listener `onTokenRefresh` lama DIBATALKAN sebelum memasang yang baru,
  ///    sehingga listener tidak menumpuk setiap login.
  /// 3. `Firebase.initializeApp()` hanya dipanggil bila belum ada aplikasi
  ///    (bootstrap sudah menginisialisasi; memanggil ulang bisa melempar dan
  ///    seluruh registrasi token ikut gagal).
  /// 4. Izin notifikasi diminta sekali per proses.
  Future<void> registerDeviceToken(AuthSession session) {
    _flushInitialNavigation();
    final accessToken = session.accessToken;
    if (accessToken == null || accessToken.isEmpty) return Future<void>.value();

    final userId = session.backendUserId ?? session.identifier;
    if (userId.isEmpty || !_sessionIsCurrent(session))
      return Future<void>.value();
    if (_registeredUserId == userId && _registeredRole == session.role)
      return Future<void>.value();
    final pending = _pendingRegistrationSession;
    if (pending != null &&
        _pendingRegistration != null &&
        (pending.backendUserId ?? pending.identifier) == userId &&
        pending.role == session.role) {
      return _pendingRegistration!;
    }
    final generation = ++_registrationGeneration;
    // Another queued owner may already have changed the backend token before
    // its response returns. A later return to the old owner must save again.
    _registeredUserId = null;
    _registeredRole = null;
    final work = _queueDeviceTokenWork(() async {
      if (!_registrationIsCurrent(session, generation)) return;

      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp();
      }
      if (!_registrationIsCurrent(session, generation)) return;
      final messaging = FirebaseMessaging.instance;
      if (!_permissionRequested) {
        _permissionRequested = true;
        await messaging.requestPermission();
      }
      if (!_registrationIsCurrent(session, generation)) return;

      // Batalkan listener lama sebelum memasang yang baru.
      await _tokenRefreshSub?.cancel();
      if (!_registrationIsCurrent(session, generation)) return;
      _tokenRefreshSub = messaging.onTokenRefresh.listen(
        (String newToken) {
          if (!_registrationIsCurrent(session, generation)) return;
          unawaited(_queueDeviceTokenWork(() async {
            if (_registrationIsCurrent(session, generation)) {
              await _sendTokenToBackend(accessToken, newToken);
            }
          }));
        },
      );

      final token = await _currentFcmToken();
      if (token == null ||
          token.isEmpty ||
          !_registrationIsCurrent(session, generation)) return;
      await _sendTokenToBackend(accessToken, token);
      if (!_registrationIsCurrent(session, generation)) return;
      _registeredUserId = userId;
      _registeredRole = session.role;
    });
    _pendingRegistrationSession = session;
    _pendingRegistration = work;
    return work.whenComplete(() {
      if (identical(_pendingRegistration, work)) {
        _pendingRegistration = null;
        _pendingRegistrationSession = null;
      }
    });
  }

  bool _sessionIsCurrent(AuthSession expected) {
    if (currentSession == null) return true;
    final current = currentSession!.call();
    return current != null &&
        current.role == expected.role &&
        (current.backendUserId ?? current.identifier) ==
            (expected.backendUserId ?? expected.identifier);
  }

  bool _registrationIsCurrent(AuthSession session, int generation) =>
      generation == _registrationGeneration && _sessionIsCurrent(session);

  Future<void> _queueDeviceTokenWork(Future<void> Function() operation) {
    _deviceTokenWork =
        _deviceTokenWork.then((_) => operation()).catchError((_) {
      if (kDebugMode) debugPrint('FCM device token operation failed.');
    });
    return _deviceTokenWork;
  }

  /// Lupakan pendaftaran pada proses ini (dipakai saat logout).
  ///
  /// Tanpa ini, login ulang dengan akun yang sama akan dilewati oleh pengaman
  /// "user sudah terdaftar" walau token server baru saja dicabut.
  void resetRegistration() {
    _pendingInitialNavigation = null;
    _registrationGeneration++;
    _registeredUserId = null;
    _registeredRole = null;
    _pendingRegistration = null;
    _pendingRegistrationSession = null;
    unawaited(_tokenRefreshSub?.cancel());
    _tokenRefreshSub = null;
  }

  /// Cabut token FCM perangkat dari server, lalu lupakan pendaftaran lokal.
  ///
  /// Dipanggil saat logout SEBELUM sesi dihapus (butuh [accessToken]). Tanpa
  /// ini, perangkat yang sudah keluar tetap tercatat `enabled` di server dan
  /// terus menerima push milik akun lama — muncul sebagai notifikasi tanpa
  /// aktivitas yang sesuai di aplikasi.
  ///
  /// Best-effort: kegagalan jaringan/izin TIDAK boleh menghalangi logout, jadi
  /// work diserialkan setelah save lama, lalu sebelum registrasi akun baru.
  Future<void> unregisterDeviceToken(String? accessToken) {
    final token = accessToken;
    // Invalidate listeners and lookups immediately, not after network logout.
    resetRegistration();
    return _queueDeviceTokenWork(() async {
      if (token != null && token.isNotEmpty) {
        final fcmToken = await _currentFcmToken();
        if (fcmToken != null && fcmToken.isNotEmpty) {
          await apiClient.deleteDeviceToken(
            accessToken: token,
            token: fcmToken,
          );
        }
      }
    });
  }

  /// Ambil token FCM perangkat: lewat [fcmTokenProvider] bila disuntikkan
  /// (test), atau `FirebaseMessaging.instance.getToken()` (produksi). Null bila
  /// Firebase belum siap / tidak ada token.
  Future<String?> _currentFcmToken() async {
    final provider = _fcmTokenProvider;
    if (provider != null) return provider();
    if (Firebase.apps.isEmpty) return null;
    return FirebaseMessaging.instance.getToken();
  }

  Future<void> _sendTokenToBackend(String accessToken, String token) async {
    await apiClient.saveDeviceToken(
      accessToken: accessToken,
      platform: defaultTargetPlatform.name,
      token: token,
    );
  }

  // ──────────────────────────────────────────────────────────────
  // Foreground message handler
  // ──────────────────────────────────────────────────────────────

  Future<void> _onForegroundMessage(RemoteMessage message) async {
    final data = message.data;
    final kind = eventKindOf(data);

    final session = currentSession?.call();
    if (!isRemoteChatForSession(data, session)) return;
    try {
      if (!await BackgroundChatDelivery.isActiveSession(
          apiClient, data, session!)) return;
    } on Object {
      return;
    }
    if (!isRemoteChatForSession(data, currentSession?.call())) return;
    // Chat untuk percakapan yang sedang dibuka tidak perlu notifikasi.
    if (!shouldShowChatNotification(data, activeChatPeer?.call())) return;

    final notification = message.notification;
    String title;
    String body;
    if (notification != null) {
      title = notification.title ?? 'Malva';
      body = notification.body ?? '';
    } else if (kind == 'chat_message') {
      // Push data-only dari backend: bangun isi notifikasi dari payload.
      title = (data['sender_name'] ?? '').toString().trim();
      if (title.isEmpty) title = 'Pesan baru';
      final text = (data['text'] ?? '').toString().trim();
      body = text.length > 120 ? '${text.substring(0, 120)}…' : text;
      if (body.isEmpty) body = 'Anda menerima pesan baru.';
    } else {
      // Data-only di luar chat tidak ditampilkan: tidak ada jenis notifikasi
      // lain yang diizinkan selain chat, pengingat goals, dan pengingat obat.
      return;
    }

    final channel = _channelForType(kind);
    final androidDetails = AndroidNotificationDetails(
      channel,
      MalvaNotificationChannels.name(channel),
      importance: channel == MalvaNotificationChannels.crisis
          ? Importance.max
          : Importance.defaultImportance,
      priority: channel == MalvaNotificationChannels.crisis
          ? Priority.high
          : Priority.defaultPriority,
    );
    const iosDetails = DarwinNotificationDetails();

    _localNotifications.show(
      id: notificationIdFor(data),
      title: title,
      body: body,
      notificationDetails:
          NotificationDetails(android: androidDetails, iOS: iosDetails),
      payload: jsonEncode(data),
    );
  }

  /// ID notifikasi deterministik dari data peristiwa.
  ///
  /// Memakai FNV-1a 31-bit (pola sama dengan
  /// `MedicationReminderService._stableHash`), BUKAN `String.hashCode`:
  /// hashCode Dart tidak dijamin sama antar-proses (seed acak), sehingga
  /// setelah aplikasi dibuka ulang id yang dihitung berbeda dan peristiwa yang
  /// sama tampil sebagai DUA baris di shade. Dengan id stabil, pengiriman
  /// ulang peristiwa yang sama MENIMPA notifikasi sebelumnya.
  static int notificationIdFor(Map<String, dynamic> data) {
    final parts = <String>[
      eventKindOf(data),
      (data['session_id'] ?? '').toString(),
      (data['notification_id'] ?? '').toString(),
      (data['patient_id'] ?? '').toString(),
    ];
    return _stableHash(parts.join('|'));
  }

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

  /// Jenis peristiwa dari payload.
  ///
  /// Backend mengirim kunci `kind` (bukan `type`) — lihat
  /// `backend/internal/server/server.go` saat membangun data FCM. Kunci `type`
  /// tetap dibaca lebih dulu demi kompatibilitas payload lama/notifikasi lokal
  /// yang sudah tersimpan, lalu fallback ke `kind`. Tanpa fallback ini seluruh
  /// routing & pemilihan kanal menerima null dan tap notifikasi tidak pernah
  /// bernavigasi.
  static String eventKindOf(Map<String, dynamic> data) =>
      (data['type'] ?? data['kind'] ?? '').toString();

  /// True bila notifikasi chat perlu ditampilkan.
  ///
  /// Remote events only display chat; device reminders have their own scheduler.
  @visibleForTesting
  static bool shouldShowChatNotification(
    Map<String, dynamic> data,
    String? activePeer,
  ) {
    if (eventKindOf(data) != 'chat_message') return false;
    final sender = (data['sender_id'] ?? '').toString();
    if (sender.isEmpty) return true;
    final peer = (activePeer ?? '').trim();
    if (peer.isEmpty) return true;
    return sender != peer;
  }

  static bool isRemoteChatForSession(
    Map<String, dynamic> data,
    AuthSession? session,
  ) {
    if (eventKindOf(data) != 'chat_message' ||
        session == null ||
        (session.accessToken ?? '').isEmpty ||
        (data['session_id'] ?? '').toString().isEmpty) return false;
    final userId = session.backendUserId ?? '';
    final patient = (data['patient_id'] ?? '').toString();
    final professional = (data['professional_id'] ?? '').toString();
    final sender = (data['sender_id'] ?? '').toString();
    if (userId.isEmpty ||
        patient.isEmpty ||
        professional.isEmpty ||
        sender.isEmpty) return false;
    return switch (session.role) {
      UserRole.patient => userId == patient && sender == professional,
      UserRole.professional => userId == professional && sender == patient,
      _ => false,
    };
  }

  // ──────────────────────────────────────────────────────────────
  // Notification tap handler
  // ──────────────────────────────────────────────────────────────

  void _onMessageOpenedApp(RemoteMessage message) {
    _handleRemoteNotificationNavigation(message.data);
  }

  void _queueInitialNavigation(Map<String, dynamic> data) {
    if (eventKindOf(data) != 'chat_message') return;
    _pendingInitialNavigation = data;
    _flushInitialNavigation();
  }

  void _flushInitialNavigation() {
    final data = _pendingInitialNavigation;
    if (data == null || currentSession?.call() == null) return;
    if (navigatorKey.currentState == null) {
      if (!_initialNavigationFrameQueued) {
        _initialNavigationFrameQueued = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _initialNavigationFrameQueued = false;
          if (navigatorKey.currentState != null) _flushInitialNavigation();
        });
      }
      return;
    }
    // Consume once: a payload for a different restored owner must not be
    // replayed if that older account logs in at a later time.
    _pendingInitialNavigation = null;
    _handleRemoteNotificationNavigation(data);
  }

  void _handleRemoteNotificationNavigation(Map<String, dynamic> data) {
    if (!isRemoteChatForSession(data, currentSession?.call())) return;
    _handleNotificationNavigation(data);
  }

  // ──────────────────────────────────────────────────────────────
  // Navigation based on notification payload
  // ──────────────────────────────────────────────────────────────

  void _handleNotificationNavigation(Map<String, dynamic> data) {
    final kind = eventKindOf(data);
    final route = routeForType(kind.isEmpty ? null : kind, data);
    if (route == null) return;

    // Chat: butuh argumen peer agar layar chat langsung terbuka pada lawan
    // bicara yang benar (sebelumnya tap chat dead-end karena rute tidak ada).
    if (route == '/chat') {
      navigatorKey.currentState?.pushNamed(
        '/chat',
        arguments: <String, String>{
          'peer_id': (data['sender_id'] ?? '').toString(),
          'name': (data['sender_name'] ?? 'Pesan').toString(),
        },
      );
      return;
    }

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

  /// Pemetaan tipe notifikasi → rute. Murni agar bisa diuji.
  @visibleForTesting
  static String? routeForType(String? type, Map<String, dynamic> data) {
    return switch (type) {
      'crisis_alert' => '/crisis-alert',
      'follow_up' => '/home',
      'medication_reminder' => '/medication',
      'screening_result' => '/assessment/result',
      // Chat: buka layar percakapan dengan pengirim sebagai lawan bicara.
      'chat_message' => '/chat',
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

  static String _channelForType(String? type) {
    return switch (type) {
      'crisis_alert' => MalvaNotificationChannels.crisis,
      'medication_reminder' => MalvaNotificationChannels.medication,
      'chat_message' => MalvaNotificationChannels.updates,
      _ => MalvaNotificationChannels.followUps,
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
    final resolvedChannel = channel ?? MalvaNotificationChannels.followUps;
    final androidDetails = AndroidNotificationDetails(
      resolvedChannel,
      MalvaNotificationChannels.name(resolvedChannel),
      importance: resolvedChannel == MalvaNotificationChannels.crisis
          ? Importance.max
          : Importance.defaultImportance,
      priority: resolvedChannel == MalvaNotificationChannels.crisis
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
        payload: payload,
      );
    }
  }
}
