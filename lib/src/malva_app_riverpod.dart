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
import 'screens/splash_screen.dart';
import 'services/dashboard_sync_service.dart';
import 'services/malva_api_client.dart';
import 'services/medication_reminder_service.dart';
import 'services/push_notification_service.dart';
import 'theme.dart';

final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

class MalvaAppRiverpod extends ConsumerStatefulWidget {
  const MalvaAppRiverpod({super.key});

  @override
  ConsumerState<MalvaAppRiverpod> createState() => _MalvaAppRiverpodState();
}

class _MalvaAppRiverpodState extends ConsumerState<MalvaAppRiverpod> {
  late final PushNotificationService _pushNotifications;
  late final DashboardSyncService _dashboardSyncService;
  bool _isTakingInitialScreening = false;

  @override
  void initState() {
    super.initState();
    final apiClient = ref.read(apiClientProvider);
    _pushNotifications = PushNotificationService(
      apiClient: apiClient,
      navigatorKey: _navigatorKey,
    );
    _dashboardSyncService = DashboardSyncService();

    // Hide splash after delay
    Future<void>.delayed(const Duration(milliseconds: 1800), () {
      if (!mounted) return;
      ref.read(appStateProvider.notifier).hideSplash();
    });

    unawaited(_pushNotifications.initialize().catchError((_) {}));

    // Listen to auth changes
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _setupAuthListener();
    });
  }

  void _setupAuthListener() {
    ref.listen<AuthState>(authStateProvider, (previous, next) {
      if (next.isAuthenticated && previous?.session == null) {
        // User just logged in
        final session = next.session!;
        ref.read(apiClientProvider).setRefreshToken(session.refreshToken);
        unawaited(_pushNotifications.registerDeviceToken(session));
        _scheduleAllMedicationReminders();
        ref.read(appStateProvider.notifier).handleAuth(session.role.name);
      } else if (!next.isAuthenticated && previous?.session != null) {
        // User logged out
        _dashboardSyncService.stopSync();
        ref.read(appStateProvider.notifier).handleLogout();
      }
    });
  }

  @override
  void dispose() {
    _dashboardSyncService.dispose();
    super.dispose();
  }

  void _handleNotificationTap(String medicationId) {
    if (!mounted) return;
    final session = ref.read(currentSessionProvider);
    if (session == null) {
      ref.read(appStateProvider.notifier).hideSplash();
      return;
    }
    if (session.role == UserRole.patient) {
      _navigatorKey.currentState?.pushNamed('/medication');
    }
  }

  void _scheduleAllMedicationReminders() {
    final meds = ref.read(medicationProvider).medications;
    final reminderService = ref.read(medicationReminderServiceProvider);
    for (final med in meds) {
      unawaited(reminderService.scheduleMedicationReminder(med));
    }
  }

  void _handleAuthenticated(AuthSession session) {
    setState(() => _isTakingInitialScreening = false);
    ref.read(authStateProvider.notifier).loginPatient(
          email: session.identifier,
          password: '',
        ).catchError((_) {});
    ref.read(apiClientProvider).setRefreshToken(session.refreshToken);
    unawaited(_pushNotifications.registerDeviceToken(session));
    _scheduleAllMedicationReminders();
  }

  void _handleLogout() {
    _dashboardSyncService.stopSync();
    ref.read(authStateProvider.notifier).logout();
    setState(() => _isTakingInitialScreening = false);
  }

  Widget _buildPatientHome() {
    final screeningState = ref.watch(screeningProvider);
    final store = ref.read(malvaStoreBridgeProvider);

    if (screeningState.needsInitialScreeningDecision && !_isTakingInitialScreening) {
      return InitialScreeningConsentScreen(
        store: store,
        onAgree: () => setState(() => _isTakingInitialScreening = true),
        onSkip: () {
          ref.read(screeningProvider.notifier).skipInitial();
          setState(() => _isTakingInitialScreening = false);
        },
      );
    }

    if (_isTakingInitialScreening) {
      return AssessmentScreen(
        store: store,
        session: ref.read(currentSessionProvider),
        isInitialScreening: true,
        onComplete: () => setState(() => _isTakingInitialScreening = false),
        onBack: () => setState(() => _isTakingInitialScreening = false),
      );
    }

    return PatientShell(
      store: store,
      session: ref.read(currentSessionProvider),
      apiClient: ref.read(apiClientProvider),
      medicationReminderService: ref.read(medicationReminderServiceProvider),
      onLogout: _handleLogout,
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = ref.watch(appStateProvider);
    final authState = ref.watch(authStateProvider);
    final store = ref.read(malvaStoreBridgeProvider);

    return MaterialApp(
      navigatorKey: _navigatorKey,
      debugShowCheckedModeBanner: false,
      title: 'Malva',
      theme: buildMalvaTheme(),
      initialRoute: '/',
      onGenerateRoute: _onGenerateRoute,
      home: appState.showSplash
          ? const SplashScreen()
          : !authState.isAuthenticated
              ? LoginScreen(
                  store: store,
                  onAuthenticated: _handleAuthenticated,
                )
              : authState.isProfessional
                  ? ProfessionalDashboardScreen(
                      store: store,
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
    final store = ref.read(malvaStoreBridgeProvider);

    return switch (name) {
      '/crisis-alert' => MaterialPageRoute(
          builder: (_) => _buildPatientHome(),
          settings: settings,
        ),
      '/medication' => MaterialPageRoute(
          builder: (_) => !authState.isAuthenticated
              ? LoginScreen(
                  store: store,
                  onAuthenticated: _handleAuthenticated,
                )
              : PatientShell(
                  store: store,
                  session: authState.session,
                  apiClient: ref.read(apiClientProvider),
                  medicationReminderService: ref.read(medicationReminderServiceProvider),
                  onLogout: _handleLogout,
                ),
          settings: settings,
        ),
      '/assessment/result' => MaterialPageRoute(
          builder: (_) => !authState.isAuthenticated
              ? LoginScreen(
                  store: store,
                  onAuthenticated: _handleAuthenticated,
                )
              : _buildPatientHome(),
          settings: settings,
        ),
      _ => null,
    };
  }
}
