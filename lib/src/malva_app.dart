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

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

class MalvaApp extends StatefulWidget {
  const MalvaApp({super.key, this.medicationReminderService});

  final MedicationReminderService? medicationReminderService;

  @override
  State<MalvaApp> createState() => _MalvaAppState();
}

class _MalvaAppState extends State<MalvaApp> {
  late final MalvaStore _store;
  late final MalvaApiClient _apiClient;
  late final PushNotificationService _pushNotifications;
  late final DashboardSyncService _dashboardSyncService;
  late final MedicationReminderService _medicationReminderService;
  AuthSession? _session;
  bool _showSplash = true;
  bool _isTakingInitialScreening = false;

  @override
  void initState() {
    super.initState();
    _apiClient = MalvaApiClient();
    _store = MalvaStore.seeded(apiClient: _apiClient);
    _pushNotifications = PushNotificationService(
      apiClient: _apiClient,
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
    unawaited(_restoreSession());
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
      navigatorKey.currentState?.pushNamed('/medication');
    }
  }

  void _handleAuthenticated(AuthSession session) {
    setState(() {
      _session = session;
      _isTakingInitialScreening = false;
    });
    _apiClient.setRefreshToken(session.refreshToken);
    unawaited(_pushNotifications.registerDeviceToken(session));
    unawaited(_store.persistSession(session));
    _scheduleAllMedicationReminders();
  }

  void _handleLogout() {
    _dashboardSyncService.stopSync();
    unawaited(_store.clearSession());
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

  Future<void> _restoreSession() async {
    final session = await _store.restoreSession();
    if (session != null && mounted) {
      setState(() => _session = session);
      _apiClient.setRefreshToken(session.refreshToken);
      unawaited(_pushNotifications.registerDeviceToken(session));
      _scheduleAllMedicationReminders();
    }
  }

  Widget _buildPatientHome() {
    if (_store.needsInitialScreeningDecision && !_isTakingInitialScreening) {
      return InitialScreeningConsentScreen(
        store: _store,
        onAgree: () => setState(() => _isTakingInitialScreening = true),
        onSkip: () => setState(() {
          _store.skipInitialScreening();
          _isTakingInitialScreening = false;
        }),
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
      onLogout: _handleLogout,
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
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

    return switch (name) {
      '/crisis-alert' => MaterialPageRoute(
          builder: (_) => _buildPatientHome(),
          settings: settings,
        ),
      '/medication' => MaterialPageRoute(
          builder: (_) => _session == null
              ? LoginScreen(
                  store: _store,
                  onAuthenticated: _handleAuthenticated,
                )
              : PatientShell(
                  store: _store,
                  session: _session,
                  apiClient: _apiClient,
                  medicationReminderService: _medicationReminderService,
                  onLogout: _handleLogout,
                ),
          settings: settings,
        ),
      '/assessment/result' => MaterialPageRoute(
          builder: (_) => _session == null
              ? LoginScreen(
                  store: _store,
                  onAuthenticated: _handleAuthenticated,
                )
              : _buildPatientHome(),
          settings: settings,
        ),
      _ => null,
    };
  }
}
