import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'models.dart';
import 'providers/providers.dart';
import 'screens/assessment_screen.dart';
import 'screens/initial_screening_consent_screen.dart';
import 'screens/login_screen.dart';
import 'screens/patient_shell.dart';
import 'screens/professional_dashboard_screen.dart';
import 'screens/safety/emergency_contacts_screen.dart';
import 'screens/safety/emergency_dashboard_screen.dart';
import 'screens/safety/guided_grounding_screen.dart';
import 'screens/splash_screen.dart';
import 'services/dashboard_sync_service.dart';
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
  bool _isTakingInitialScreening = false;
  bool _showSplash = true;

  @override
  void initState() {
    super.initState();
    final apiClient = ref.read(apiClientProvider);
    _pushNotifications = PushNotificationService(
      apiClient: apiClient,
      navigatorKey: navigatorKey,
    );
    _dashboardSyncService = DashboardSyncService();
    _medicationReminderService =
        widget.medicationReminderService ?? MedicationReminderService();
    unawaited(_medicationReminderService.initialize().catchError((_) {}));

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

    unawaited(_pushNotifications.initialize().catchError((_) {}));
  }

  @override
  void dispose() {
    _dashboardSyncService.dispose();
    super.dispose();
  }

  void _scheduleAllMedicationReminders() {
    final meds = ref.read(malvaStoreProvider).medications;
    for (final med in meds) {
      unawaited(_medicationReminderService.scheduleMedicationReminder(med));
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
      _scheduleAllMedicationReminders();
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
    _scheduleAllMedicationReminders();

    // Sync any pending offline data
    unawaited(ref.read(offlineSyncServiceProvider).syncNow(
          accessToken: session.accessToken,
        ));
  }

  void _handleLogout() {
    _dashboardSyncService.stopSync();
    final session = ref.read(authStateProvider).session;
    // Cabut refresh token di server (best-effort), lalu bersihkan lokal.
    unawaited(ref.read(malvaStoreProvider.notifier).logoutSession(session));
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

  Route<dynamic>? _onGenerateRoute(RouteSettings settings) {
    final name = settings.name;
    if (name == null) return null;

    final authState = ref.read(authStateProvider);

    return switch (name) {
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
      '/medication' => MaterialPageRoute(
          builder: (_) => authState.session == null
              ? LoginScreen(onAuthenticated: _handleAuthenticated)
              : PatientShell(
                  session: authState.session,
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
