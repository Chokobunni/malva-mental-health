import 'dart:async';

import 'package:flutter/material.dart';

import 'models.dart';
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
import 'store/malva_store.dart';
import 'theme.dart';

final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

class MalvaApp extends StatefulWidget {
  const MalvaApp({
    super.key,
    required this.medicationReminderService,
  });

  final MedicationReminderService medicationReminderService;

  @override
  State<MalvaApp> createState() => _MalvaAppState();
}

class _MalvaAppState extends State<MalvaApp> {
  late final MalvaStore _store;
  late final MalvaApiClient _apiClient;
  late final PushNotificationService _pushNotifications;
  late final DashboardSyncService _dashboardSyncService;
  AuthSession? _session;
  bool _showSplash = true;
  bool _isTakingInitialScreening = false;

  MedicationReminderService get _medicationReminderService =>
      widget.medicationReminderService;

  @override
  void initState() {
    super.initState();
    _apiClient = MalvaApiClient();
    _pushNotifications = PushNotificationService(
      apiClient: _apiClient,
      navigatorKey: _navigatorKey,
    );
    _store = MalvaStore.seeded(apiClient: _apiClient);
    _dashboardSyncService = DashboardSyncService();
    _medicationReminderService.onNotificationTap = _handleNotificationTap;

    Future<void>.delayed(const Duration(milliseconds: 1800), () {
      if (!mounted) return;
      setState(() => _showSplash = false);
    });

    // Initialize FCM handlers early so background messages are captured.
    unawaited(_pushNotifications.initialize());
  }

  @override
  void dispose() {
    _dashboardSyncService.dispose();
    super.dispose();
  }

  void _handleNotificationTap(String medicationId) {
    if (!mounted) return;
    if (_session == null) {
      setState(() => _showSplash = false);
      return;
    }
    if (_session!.role == UserRole.patient) {
      _navigatorKey.currentState?.pushNamed('/medication');
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      debugShowCheckedModeBanner: false,
      title: 'Malva',
      theme: buildMalvaTheme(),
      initialRoute: '/',
      onGenerateRoute: _onGenerateRoute,
      home: _showSplash
          ? const SplashScreen()
          : _session == null
              ? LoginScreen(
                  store: _store,
                  onAuthenticated: _handleAuthenticated,
                )
              : _session!.role == UserRole.professional
                  ? ProfessionalDashboardScreen(
                      store: _store,
                      session: _session,
                      apiClient: _apiClient,
                      syncService: _dashboardSyncService,
                      onLogout: _handleLogout,
                    )
                  : _buildPatientHome(),
    );
  }

  Route<dynamic>? _onGenerateRoute(RouteSettings settings) {
    final name = settings.name;
    if (name == null) return null;

    // Only handle named routes that come from notification taps.
    // Let the default `home` / Navigator handle normal pushes.
    return switch (name) {
      '/crisis-alert' => MaterialPageRoute(
          builder: (_) => _buildPatientHome(),
          settings: settings,
        ),
      '/medication' => MaterialPageRoute(
          builder: (_) => _session == null
              ? LoginScreen(store: _store, onAuthenticated: _handleAuthenticated)
              : PatientShell(
                  store: _store,
                  session: _session,
                  apiClient: _apiClient,
                  medicationReminderService: _medicationReminderService,
                  onLogout: () => setState(() {
                    _session = null;
                    _isTakingInitialScreening = false;
                  }),
                ),
          settings: settings,
        ),
      '/assessment/result' => MaterialPageRoute(
          builder: (_) => _session == null
              ? LoginScreen(store: _store, onAuthenticated: _handleAuthenticated)
              : _buildPatientHome(),
          settings: settings,
        ),
      _ => null,
    };
  }

  void _handleAuthenticated(AuthSession session) {
    setState(() {
      _session = session;
      _isTakingInitialScreening = false;
    });
    unawaited(_pushNotifications.registerDeviceToken(session));
    _scheduleAllMedicationReminders();
  }

  void _handleLogout() {
    _dashboardSyncService.stopSync();
    setState(() {
      _session = null;
      _isTakingInitialScreening = false;
    });
  }

  void _scheduleAllMedicationReminders() {
    for (final med in _store.medications) {
      unawaited(_medicationReminderService.scheduleMedicationReminder(med));
    }
  }

  Widget _buildPatientHome() {
    if (_store.needsInitialScreeningDecision && !_isTakingInitialScreening) {
      return InitialScreeningConsentScreen(
        store: _store,
        onAgree: () => setState(() => _isTakingInitialScreening = true),
        onSkip: () => setState(() => _isTakingInitialScreening = false),
      );
    }

    if (_isTakingInitialScreening) {
      return AssessmentScreen(
        store: _store,
        session: _session,
        isInitialScreening: true,
        onComplete: () => setState(() => _isTakingInitialScreening = false),
        onBack: () => setState(() => _isTakingInitialScreening = false),
      );
    }

    return PatientShell(
      store: _store,
      session: _session,
      apiClient: _apiClient,
      medicationReminderService: _medicationReminderService,
      onLogout: () => setState(() {
        _session = null;
        _isTakingInitialScreening = false;
      }),
    );
  }
}
