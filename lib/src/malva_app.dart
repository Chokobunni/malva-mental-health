import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'models.dart';
import 'platform/contracts/ports.dart';
import 'platform/platform_providers.dart';
import 'providers/providers.dart';
import 'screens/assessment_screen.dart';
import 'screens/chat_screen.dart';
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
import 'services/push_notification_service.dart';
import 'theme.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

class MalvaApp extends ConsumerStatefulWidget {
  const MalvaApp({super.key, this.medicationReminderService});

  final MedicationReminderService? medicationReminderService;

  @override
  ConsumerState<MalvaApp> createState() => _MalvaAppState();
}

class _MalvaAppState extends ConsumerState<MalvaApp> {
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

  @override
  void initState() {
    super.initState();
    _capabilities = ref.read(capabilitiesProvider);
    final apiClient = ref.read(apiClientProvider);
    _pushNotifications = PushNotificationService(
      apiClient: apiClient,
      navigatorKey: navigatorKey,
      // Dipakai menekan notifikasi chat untuk percakapan yang sedang dibuka.
      activeChatPeer: () => ref.read(activeChatPeerProvider),
    );
    _dashboardSyncService = DashboardSyncService();
    _medicationReminderService = widget.medicationReminderService ??
        MedicationReminderService(
          enabled: _capabilities.canScheduleOsReminders,
        );
    _goalReminderService = GoalReminderService(
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
    _dashboardSyncService.dispose();
    super.dispose();
  }

  void _scheduleAllMedicationReminders() {
    if (!_capabilities.canScheduleOsReminders) return;
    final meds = ref.read(malvaStoreProvider).medications;
    // scheduleAll menjadwalkan SEMUA jam pengingat tiap obat (bukan hanya
    // jam pertama) dan membatalkan id lama agar tidak dobel.
    unawaited(_medicationReminderService.scheduleAll(meds));
  }

  /// Sinkronkan pengingat goals harian dengan kondisi akun.
  ///
  /// Preferensi (aktif/jam) dibaca dari SecureStore; jumlah goal aktif dari
  /// server. Semua kegagalan (jaringan/izin) diabaikan: pengingat tidak boleh
  /// mengganggu boot aplikasi.
  Future<void> _syncGoalReminder(AuthSession session) async {
    if (!_capabilities.canScheduleOsReminders) return;
    final token = session.accessToken;
    if (token == null || token.isEmpty) return;
    try {
      final settings = await _goalReminderService.loadSettings();
      final goals = await ref.read(apiClientProvider).listGoals(
            accessToken: token,
            includeInactive: true,
          );
      final hasActiveGoals = goals.any((goal) => goal.isActive);
      await _goalReminderService.sync(
        hasActiveGoals: hasActiveGoals,
        enabled: settings.enabled,
        hour: settings.hour,
        minute: settings.minute,
      );
    } on Object {
      // Offline / izin ditolak: pengingat lama tetap dipakai.
    }
  }

  /// Restore sesi dari secure storage saat aplikasi dibuka kembali.
  /// Sesi dipakai langsung; refresh token ditukar di belakang agar tetap valid.
  Future<void> _restorePersistedSession() async {
    try {
      final store = ref.read(malvaStoreProvider.notifier);
      final stored = await store.restoreSession();
      if (stored == null) return;
      if (!mounted) return;
      ref.read(apiClientProvider).setRefreshToken(stored.refreshToken);
      ref.read(authStateProvider.notifier).setSession(stored);
      // Fresh start: data akun tersimpan tidak boleh tercampur akun lain.
      store.applySession(stored);
      _scheduleAllMedicationReminders();
      unawaited(_syncGoalReminder(stored));
      unawaited(_pushNotifications.registerDeviceToken(stored));
      final refreshToken = stored.refreshToken;
      if (refreshToken != null && refreshToken.isNotEmpty) {
        try {
          final refreshed = await store.refreshSessionOnline(refreshToken);
          if (!mounted) return;
          // Jangan timpa bila user sudah logout saat refresh berjalan.
          if (ref.read(authStateProvider).session == null) return;
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
    _scheduleAllMedicationReminders();
    unawaited(_syncGoalReminder(session));

    // Sync any pending offline data
    unawaited(ref.read(offlineSyncServiceProvider).syncNow(
          accessToken: session.accessToken,
        ));
  }

  void _handleLogout() {
    _dashboardSyncService.stopSync();
    // Reminder obat dibatalkan SEBELUM resetForAccount() mengosongkan daftar
    // obat. Penjadwalan dilakukan OS, jadi tanpa ini notifikasi "waktunya minum
    // obat X" milik akun lama tetap berbunyi setelah logout dan terbaca oleh
    // akun berikutnya di perangkat yang sama.
    final meds = ref.read(malvaStoreProvider).medications;
    unawaited(_medicationReminderService
        .cancelRemindersFor(meds.map((m) => m.id).toList(growable: false)));
    // Pengingat goals juga dijadwalkan OS: batalkan agar tidak berbunyi untuk
    // akun yang sudah keluar.
    unawaited(_goalReminderService.cancel());
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
        onAgree: () => setState(() => _isTakingInitialScreening = true),
        onSkip: () {
          ref.read(malvaStoreProvider.notifier).skipInitialScreening();
          setState(() => _isTakingInitialScreening = false);
        },
      );
    }

    if (_isTakingInitialScreening) {
      return AssessmentScreen(
        session: ref.read(currentSessionProvider),
        apiClient: ref.read(apiClientProvider),
        isInitialScreening: true,
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
      if (next.isAuthenticated && previous?.session == null) {
        final session = next.session!;
        ref.read(apiClientProvider).setRefreshToken(session.refreshToken);
        unawaited(_pushNotifications.registerDeviceToken(session));
        _scheduleAllMedicationReminders();
        unawaited(_syncGoalReminder(session));
      } else if (!next.isAuthenticated && previous?.session != null) {
        _dashboardSyncService.stopSync();
      }
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
      initialRoute: '/',
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
