import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'models.dart';
import 'platform/contracts/ports.dart';
import 'platform/background_chat_delivery.dart';
import 'platform/platform_providers.dart';
import 'providers/providers.dart';
import 'screens/initial_symptoms_screen.dart';
import 'screens/chat_screen.dart';
import 'screens/booking/payment_screen.dart';
import 'screens/initial_screening_consent_screen.dart';
import 'screens/login_screen.dart';
import 'screens/patient_shell.dart';
import 'screens/professional_dashboard_screen.dart';
import 'screens/safety/emergency_contacts_screen.dart';
import 'screens/safety/emergency_dashboard_screen.dart';
import 'screens/safety/guided_grounding_screen.dart';
import 'screens/splash_screen.dart';
import 'services/dashboard_sync_service.dart';
import 'services/goal_reminder_service.dart';
import 'services/google_auth_service.dart';
import 'services/medication_reminder_service.dart';
import 'services/malva_api_client.dart';
import 'services/push_notification_service.dart';
import 'theme.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// Accept only our payment return route. Gateway status query values are never
/// payment evidence; the screen verifies the reference with the backend.
String? paymentReturnReference(String route) {
  try {
    final uri = Uri.tryParse(route);
    if (uri == null) return null;
    final custom =
        uri.scheme == 'malva' && uri.host == 'payment' && uri.path == '/return';
    final relative = uri.scheme.isEmpty &&
        uri.host.isEmpty &&
        (uri.path == '/payment/return' || uri.path == '/return');
    if (!custom && !relative) return null;
    final reference = uri.queryParameters['reference'] ?? '';
    return RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(reference)
        ? reference
        : null;
  } on FormatException {
    return null;
  }
}

class MalvaApp extends ConsumerStatefulWidget {
  const MalvaApp(
      {super.key, this.medicationReminderService, this.goalReminderService});

  final MedicationReminderService? medicationReminderService;
  final GoalReminderService? goalReminderService;

  @override
  ConsumerState<MalvaApp> createState() => _MalvaAppState();
}

class _MalvaAppState extends ConsumerState<MalvaApp>
    with WidgetsBindingObserver {
  late final MalvaApiClient _tokenRefreshApi;
  late final void Function(String, String) _tokenRefreshHandler;
  void Function(String, String)? _previousTokenRefreshHandler;
  late final PushNotificationService _pushNotifications;
  late final DashboardSyncService _dashboardSyncService;
  late final MedicationReminderService _medicationReminderService;
  late final GoalReminderService _goalReminderService;

  /// Kemampuan platform (satu-satunya cara UI bertanya "bisakah ini?").
  /// Di mobile semua true → perilaku identik; di web mematikan fitur yang
  /// belum aman (pengingat OS & push) agar tidak "lolos kompilasi, gagal
  /// runtime". Penyambungan ke tile/tombol dilakukan di T03.
  late final PlatformCapabilities _capabilities;
  bool _isTakingInitialScreening = false;
  bool _showSplash = true;
  int _reminderGeneration = 0;
  Future<void> _medicationReminderWork = Future<void>.value();
  int _goalReminderRequest = 0;
  final Set<String> _scheduledMedicationIds = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _capabilities = ref.read(capabilitiesProvider);
    final apiClient = ref.read(apiClientProvider);
    _tokenRefreshApi = apiClient;
    _previousTokenRefreshHandler = apiClient.onTokenRefreshed;
    _tokenRefreshHandler = (accessToken, refreshToken) {
      if (!mounted) return;
      final updated = ref
          .read(authStateProvider.notifier)
          .updateTokens(accessToken, refreshToken);
      if (updated == null) return;
      unawaited(ref
          .read(malvaStoreProvider.notifier)
          .persistTokenRotation(updated)
          .catchError((_) {}));
      _previousTokenRefreshHandler?.call(accessToken, refreshToken);
    };
    apiClient.onTokenRefreshed = _tokenRefreshHandler;
    _pushNotifications = PushNotificationService(
      apiClient: apiClient,
      navigatorKey: navigatorKey,
      // Dipakai menekan notifikasi chat untuk percakapan yang sedang dibuka.
      activeChatPeer: () => ref.read(activeChatPeerProvider),
      currentSession: () => ref.read(authStateProvider).session,
    );
    _dashboardSyncService = DashboardSyncService();
    _medicationReminderService = widget.medicationReminderService ??
        MedicationReminderService(
          enabled: _capabilities.canScheduleOsReminders,
        );
    _goalReminderService = widget.goalReminderService ??
        GoalReminderService(
          enabled: _capabilities.canScheduleOsReminders,
        );
    if (_capabilities.canScheduleOsReminders) {
      unawaited(_medicationReminderService.initialize().catchError((_) {}));
      unawaited(_goalReminderService.initialize().catchError((_) {}));
    }

    // Initialize offline sync service
    unawaited(ref.read(offlineSyncServiceProvider).initialize());

    // Restore sesi tersimpan (login bertahan setelah app ditutup).
    unawaited(_restorePersistedSession());

    // Izin lokasi saat aplikasi dibuka — untuk jarak faskes (km).
    // Ditunda ke post-frame agar tidak setState saat build/tes.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(ref.read(patientLocationProvider.notifier).resolveOnStartup());
      final session = ref.read(authStateProvider).session;
      if (session != null) unawaited(_syncGoalReminder(session));
    });

    // Hide splash after delay
    Future<void>.delayed(const Duration(milliseconds: 1800), () {
      if (!mounted) return;
      setState(() => _showSplash = false);
    });

    if (_capabilities.canRegisterPush) {
      unawaited(_pushNotifications.initialize().catchError((_) {}));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (identical(_tokenRefreshApi.onTokenRefreshed, _tokenRefreshHandler)) {
      _tokenRefreshApi.onTokenRefreshed = _previousTokenRefreshHandler;
    }
    _dashboardSyncService.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _scheduleAllMedicationReminders();
      final session = ref.read(authStateProvider).session;
      if (session != null) unawaited(_syncGoalReminder(session));
    }
  }

  void _scheduleAllMedicationReminders() {
    if (!_capabilities.canScheduleOsReminders) return;
    final session = ref.read(authStateProvider).session;
    if (session == null || session.role != UserRole.patient) return;
    final state = ref.read(malvaStoreProvider);
    if (state.patient.id != (session.backendUserId ?? 'patient_local')) return;
    final generation = _reminderGeneration;
    final meds = state.medications;
    _medicationReminderWork = _medicationReminderWork.then((_) async {
      if (!_isCurrentReminderSession(session, generation)) return;
      final ids = meds.map((m) => m.id).toSet();
      await _medicationReminderService.cancelRemindersFor(
        _scheduledMedicationIds.difference(ids),
      );
      await _medicationReminderService.scheduleAll(meds);
      _scheduledMedicationIds
        ..clear()
        ..addAll(ids);
    }).catchError((_) {});
  }

  bool _isCurrentReminderSession(AuthSession session, int generation) {
    if (!mounted || generation != _reminderGeneration) return false;
    final current = ref.read(authStateProvider).session;
    return current?.role == UserRole.patient &&
        current?.backendUserId == session.backendUserId &&
        current?.identifier == session.identifier;
  }

  void _cancelPatientReminders() {
    if (!_capabilities.canScheduleOsReminders) return;
    final knownIds =
        ref.read(malvaStoreProvider).medications.map((m) => m.id).toSet();
    _medicationReminderWork = _medicationReminderWork.then((_) async {
      await _medicationReminderService.cancelRemindersFor(
        {..._scheduledMedicationIds, ...knownIds},
      );
      _scheduledMedicationIds.clear();
      await _medicationReminderService.cancelObsoleteReminders(const []);
    }).catchError((_) {});
    _goalReminderRequest++;
    // cancel invalidates its generation synchronously, including an OS write
    // already in flight. Do not put this behind an app-level scheduling queue.
    unawaited(_goalReminderService.cancel().catchError((_) {}));
  }

  /// Sinkronkan pengingat goals dengan kondisi akun dan konfigurasi terbaru.
  ///
  /// Preferensi lama dibaca dari SecureStore; konfigurasi dan progres dari
  /// server. Semua kegagalan (jaringan/izin) diabaikan: pengingat tidak boleh
  /// mengganggu boot aplikasi.
  Future<void> _syncGoalReminder(AuthSession session) async {
    if (!_capabilities.canScheduleOsReminders ||
        session.role != UserRole.patient) return;
    final generation = _reminderGeneration;
    final request = ++_goalReminderRequest;
    bool current() =>
        request == _goalReminderRequest &&
        _isCurrentReminderSession(session, generation);
    final token = session.accessToken;
    if (token == null || token.isEmpty) return;
    try {
      final settings = await _goalReminderService.loadSettings();
      if (!current()) return;
      final goals = await ref.read(apiClientProvider).listGoals(
            accessToken: token,
            includeInactive: true,
          );
      if (!current()) return;
      await _goalReminderService.syncGoals(
        goals: goals,
        settings: settings,
        isCurrent: current,
      );
    } on Object {
      // Offline / izin ditolak: pengingat lama tetap dipakai.
    }
  }

  /// Restore sesi dari secure storage saat aplikasi dibuka kembali.
  /// Sesi dipakai langsung; refresh token ditukar di belakang agar tetap valid.
  Future<void> _restorePersistedSession() async {
    final authAtStart = ref.read(authStateProvider);
    if (authAtStart.session != null) return;
    try {
      final store = ref.read(malvaStoreProvider.notifier);
      final stored = await store.restoreSession();
      if (!mounted || !identical(ref.read(authStateProvider), authAtStart))
        return;
      if (stored == null) {
        _cancelPatientReminders();
        return;
      }
      ref.read(apiClientProvider).setRefreshToken(stored.refreshToken);
      ref.read(authStateProvider.notifier).setSession(stored);
      // Fresh start: data akun tersimpan tidak boleh tercampur akun lain.
      store.applySession(stored);
      unawaited(_pushNotifications.registerDeviceToken(stored));
      final refreshToken = stored.refreshToken;
      if (refreshToken != null && refreshToken.isNotEmpty) {
        try {
          final refreshed = await store.refreshSessionOnline(refreshToken);
          if (!mounted) return;
          // A restore may finish after logout or another account has logged in.
          if (!identical(ref.read(authStateProvider).session, stored)) return;
          ref.read(apiClientProvider).setRefreshToken(refreshed.refreshToken);
          ref.read(authStateProvider.notifier).setSession(refreshed);
        } on Object {
          // Refresh gagal (offline / token dicabut): sesi tersimpan tetap
          // dipakai; request yang gagal 401 akan memicu login ulang.
        }
      }
      // Muat kontak darurat SETELAH refresh — token dijamin terbaru,
      // sehingga kontak tidak hilang karena 401 token kedaluwarsa.
      if (mounted) {
        unawaited(ref.read(safetyProvider.notifier).load());
      }
    } on Object {
      // Gagal membaca secure storage: biarkan user login manual.
    }
  }

  void _handleAuthenticated(AuthSession session) {
    setState(() => _isTakingInitialScreening = false);
    ref.read(authStateProvider.notifier).setSession(session);
    ref.read(apiClientProvider).setRefreshToken(session.refreshToken);
    unawaited(_pushNotifications.registerDeviceToken(session));
    ref.read(malvaStoreProvider.notifier).persistSession(session);
    // Fresh start: bersihkan data akun sebelumnya, set identitas akun baru.
    ref.read(malvaStoreProvider.notifier).applySession(session);
    // Kontak darurat & insiden milik akun sebelumnya harus dibuang lebih dulu:
    // load() mempertahankan kontak lama bila permintaan gagal, sehingga tanpa
    // reset akun baru bisa melihat (dan mengirim SOS ke) kontak akun lama.
    ref.read(safetyProvider.notifier).reset();
    // Muat kontak darurat untuk akun yang baru login.
    unawaited(ref.read(safetyProvider.notifier).load());

    // Sync any pending offline data
    unawaited(ref.read(offlineSyncServiceProvider).syncNow(
          accessToken: session.accessToken,
        ));
  }

  void _handleLogout() {
    _dashboardSyncService.stopSync();
    // Listener auth cancels device reminders in order after any pending schedule.
    // Baca sesi SEBELUM dihapus: token akses dibutuhkan untuk mencabut token
    // FCM perangkat di server.
    final session = ref.read(authStateProvider).session;
    // Cabut token FCM perangkat dari server (best-effort) lalu lupakan
    // pendaftaran lokal — SEBELUM sesi dihapus. Tanpa ini perangkat yang sudah
    // logout tetap menerima push akun lama (notifikasi tanpa aktivitas).
    unawaited(_pushNotifications.unregisterDeviceToken(session?.accessToken));
    // logoutSession menghapus sesi lokal lebih dulu (agar logout tetap
    // "menempel" walau jaringan menggantung), lalu mencabut refresh token
    // di server sebagai best-effort — karenanya aman tidak ditunggu.
    unawaited(ref.read(malvaStoreProvider.notifier).logoutSession(session));
    ref.read(malvaStoreProvider.notifier).resetForAccount();
    // Kontak darurat & insiden ikut dibersihkan agar tidak terbawa ke akun
    // berikutnya di perangkat yang sama.
    ref.read(safetyProvider.notifier).reset();
    ref.read(authStateProvider.notifier).clearSession();
    ref.read(apiClientProvider).setRefreshToken(null);
    unawaited(GoogleAuthService.signOut());
    setState(() => _isTakingInitialScreening = false);
  }

  Widget _buildPatientHome() {
    final storeState = ref.watch(malvaStoreProvider);

    if (storeState.needsInitialScreeningDecision &&
        !_isTakingInitialScreening) {
      return InitialScreeningConsentScreen(
        onAgree: () {
          ref.read(malvaStoreProvider.notifier).skipInitialScreening();
          setState(() => _isTakingInitialScreening = true);
        },
        onSkip: () {
          ref.read(malvaStoreProvider.notifier).skipInitialScreening();
          setState(() => _isTakingInitialScreening = false);
        },
      );
    }

    if (_isTakingInitialScreening) {
      return InitialSymptomsScreen(
        key: ValueKey(ref.read(currentSessionProvider)?.identifier),
        session: ref.read(currentSessionProvider),
        apiClient: ref.read(apiClientProvider),
        onComplete: () => setState(() => _isTakingInitialScreening = false),
        onBack: () => setState(() => _isTakingInitialScreening = false),
      );
    }

    return PatientShell(
      session: ref.read(currentSessionProvider),
      apiClient: ref.read(apiClientProvider),
      medicationReminderService: _medicationReminderService,
      onLogout: _handleLogout,
    );
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateProvider);

    // Listen to auth changes
    ref.listen<AuthState>(authStateProvider, (previous, next) {
      final before = previous?.session;
      final after = next.session;
      final accountChanged = before?.backendUserId != after?.backendUserId ||
          before?.identifier != after?.identifier ||
          before?.role != after?.role;
      if (accountChanged) {
        unawaited(BackgroundChatDelivery.clearPostedNotifications());
        _reminderGeneration++;
        _cancelPatientReminders();
      }
      if (next.isAuthenticated && (before == null || accountChanged)) {
        final session = next.session!;
        ref.read(apiClientProvider).setRefreshToken(session.refreshToken);
        unawaited(_pushNotifications.registerDeviceToken(session));
        _scheduleAllMedicationReminders();
        unawaited(_syncGoalReminder(session));
      } else if (!next.isAuthenticated && before != null) {
        _dashboardSyncService.stopSync();
      }
    });

    ref.listen<MalvaStoreState>(malvaStoreProvider, (previous, next) {
      if (!identical(previous?.medications, next.medications)) {
        _scheduleAllMedicationReminders();
      }
    });

    ref.listen<int>(clinicalDataRevisionProvider, (_, __) {
      final session = ref.read(authStateProvider).session;
      if (session == null || session.role != UserRole.patient) return;
      unawaited(_syncGoalReminder(session));
    });

    // Session expiry auto-redirect
    ref.listen<bool>(sessionIsExpiredProvider, (_, expired) {
      if (expired && mounted) {
        _handleLogout();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Session expired. Silakan login kembali.'),
            backgroundColor: MalvaColors.danger,
          ),
        );
      }
    });

    return MaterialApp(
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      title: 'Malva',
      theme: buildMalvaTheme(),
      onGenerateRoute: _onGenerateRoute,
      home: _showSplash
          ? const SplashScreen()
          : authState.session == null
              ? LoginScreen(onAuthenticated: _handleAuthenticated)
              : authState.isProfessional
                  ? ProfessionalDashboardScreen(
                      session: authState.session,
                      apiClient: ref.read(apiClientProvider),
                      syncService: _dashboardSyncService,
                      onLogout: _handleLogout,
                    )
                  : _buildPatientHome(),
    );
  }

  /// Beranda sesuai peran, dipakai rute bernama '/home'.
  ///
  /// Rute ini adalah tujuan tap notifikasi (lihat `_routeForType` di
  /// PushNotificationService: follow_up, session_meet_missing,
  /// session_meet_ready). Sebelumnya '/home' sudah dipakai sebagai tujuan
  /// tetapi tidak punya generator, sehingga `pushNamed('/home')` gagal dan tap
  /// notifikasi menjadi dead-end.
  Widget _buildRoleHome(AuthState authState) {
    final session = authState.session;
    if (session == null) {
      return LoginScreen(onAuthenticated: _handleAuthenticated);
    }
    if (authState.isProfessional) {
      return ProfessionalDashboardScreen(
        session: session,
        apiClient: ref.read(apiClientProvider),
        syncService: _dashboardSyncService,
        onLogout: _handleLogout,
      );
    }
    return _buildPatientHome();
  }

  Route<dynamic>? _onGenerateRoute(RouteSettings settings) {
    final name = settings.name;
    if (name == null) return null;

    final paymentReference = paymentReturnReference(name);
    if (paymentReference != null) {
      return MaterialPageRoute(
        settings: settings,
        builder: (_) => Consumer(builder: (context, ref, _) {
          final auth = ref.watch(authStateProvider);
          if (auth.session == null) {
            return LoginScreen(onAuthenticated: _handleAuthenticated);
          }
          if (auth.isProfessional) return _buildRoleHome(auth);
          return PaymentScreen.forReturn(
            reference: paymentReference,
            session: auth.session!,
            apiClient: ref.read(apiClientProvider),
          );
        }),
      );
    }

    final authState = ref.read(authStateProvider);

    return switch (name) {
      '/home' => MaterialPageRoute(
          builder: (_) => _buildRoleHome(authState),
          settings: settings,
        ),
      '/crisis-alert' => MaterialPageRoute(
          builder: (_) => _buildPatientHome(),
          settings: settings,
        ),
      '/safety' => MaterialPageRoute(
          builder: (_) => authState.session == null
              ? LoginScreen(onAuthenticated: _handleAuthenticated)
              : const EmergencyDashboardScreen(),
          settings: settings,
        ),
      '/safety/contacts' => MaterialPageRoute(
          builder: (_) => authState.session == null
              ? LoginScreen(onAuthenticated: _handleAuthenticated)
              : const EmergencyContactsScreen(),
          settings: settings,
        ),
      '/safety/grounding' => MaterialPageRoute(
          builder: (_) => authState.session == null
              ? LoginScreen(onAuthenticated: _handleAuthenticated)
              : const GuidedGroundingScreen(),
          settings: settings,
        ),
      '/chat' => MaterialPageRoute(
          builder: (_) {
            final session = authState.session;
            if (session == null) {
              return LoginScreen(onAuthenticated: _handleAuthenticated);
            }
            final args = settings.arguments;
            final map = args is Map ? args : const <String, String>{};
            final peerId = (map['peer_id'] ?? '').toString().trim();
            final name = (map['name'] ?? '').toString().trim();
            if (peerId.isEmpty) {
              // Tanpa peer yang jelas, buka beranda peran — bukan layar kosong.
              return _buildRoleHome(authState);
            }
            return ChatScreen(
              otherUserName: name.isEmpty ? 'Pesan' : name,
              otherUserId: peerId,
            );
          },
          settings: settings,
        ),
      '/medication' => MaterialPageRoute(
          builder: (_) => authState.session == null
              ? LoginScreen(onAuthenticated: _handleAuthenticated)
              : PatientShell(
                  session: authState.session,
                  apiClient: ref.read(apiClientProvider),
                  medicationReminderService: _medicationReminderService,
                  onLogout: _handleLogout,
                ),
          settings: settings,
        ),
      '/assessment/result' => MaterialPageRoute(
          builder: (_) => authState.session == null
              ? LoginScreen(onAuthenticated: _handleAuthenticated)
              : _buildPatientHome(),
          settings: settings,
        ),
      _ => null,
    };
  }
}
