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

  void _handleAuthenticated(AuthSession session) {
    setState(() => _isTakingInitialScreening = false);
    ref.read(authStateProvider.notifier).setSession(session);
    ref.read(apiClientProvider).setRefreshToken(session.refreshToken);
    unawaited(_pushNotifications.registerDeviceToken(session));
    ref.read(malvaStoreProvider.notifier).persistSession(session);
    _scheduleAllMedicationReminders();
  }

  void _handleLogout() {
    _dashboardSyncService.stopSync();
    ref.read(authStateProvider.notifier).clearSession();
    ref.read(malvaStoreProvider.notifier).clearSession();
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
        isInitialScreening: true,
        onComplete: () => setState(() => _isTakingInitialScreening = false),
        onBack: () => setState(() => _isTakingInitialScreening = false),
      );
    }

    return PatientShell(
      session: ref.read(currentSessionProvider),
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
