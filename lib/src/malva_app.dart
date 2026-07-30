import 'dart:async';

import 'package:flutter/material.dart';

import 'models.dart';
import 'screens/assessment_screen.dart';
import 'screens/initial_screening_consent_screen.dart';
import 'screens/login_screen.dart';
import 'screens/patient_shell.dart';
import 'screens/professional_dashboard_screen.dart';
import 'screens/splash_screen.dart';
import 'services/malva_api_client.dart';
import 'services/push_notification_service.dart';
import 'store/malva_store.dart';
import 'theme.dart';

class MalvaApp extends StatefulWidget {
  const MalvaApp({super.key});

  @override
  State<MalvaApp> createState() => _MalvaAppState();
}

class _MalvaAppState extends State<MalvaApp> {
  late final MalvaStore _store;
  late final MalvaApiClient _apiClient;
  late final PushNotificationService _pushNotifications;
  AuthSession? _session;
  bool _showSplash = true;
  bool _isTakingInitialScreening = false;

  @override
  void initState() {
    super.initState();
    _apiClient = MalvaApiClient();
    _pushNotifications = PushNotificationService(apiClient: _apiClient);
    _store = MalvaStore.seeded(apiClient: _apiClient);
    Future<void>.delayed(const Duration(milliseconds: 1800), () {
      if (!mounted) return;
      setState(() => _showSplash = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Malva',
      theme: buildMalvaTheme(),
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
                      onLogout: () => setState(() => _session = null),
                    )
                  : _buildPatientHome(),
    );
  }

  void _handleAuthenticated(AuthSession session) {
    setState(() {
      _session = session;
      _isTakingInitialScreening = false;
    });
    unawaited(_pushNotifications.registerDeviceToken(session));
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
      onLogout: () => setState(() {
        _session = null;
        _isTakingInitialScreening = false;
      }),
    );
  }
}
