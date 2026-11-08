import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:malva_mental_health/src/malva_app.dart';
import 'package:malva_mental_health/src/platform/contracts/ports.dart';
import 'package:malva_mental_health/src/platform/platform_providers.dart';
import 'package:malva_mental_health/src/providers/providers.dart';
import 'package:malva_mental_health/src/screens/login_screen.dart';
import 'package:malva_mental_health/src/screens/initial_symptoms_screen.dart';
import 'package:malva_mental_health/src/screens/initial_screening_consent_screen.dart';
import 'package:malva_mental_health/src/screens/patient_shell.dart';
import 'package:malva_mental_health/src/services/malva_api_client.dart';

void main() {
  testWidgets(
      'agree then Back exits to Home without a result or repeated consent',
      (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    final container = ProviderContainer(overrides: [
      apiClientProvider.overrideWithValue(MalvaApiClient(
          baseUrl: 'https://synthetic.test',
          httpClient: MockClient(
              (request) async => request.url.path == '/v1/auth/register'
                  ? http.Response(
                      jsonEncode({
                        'user': {
                          'id': 'registered',
                          'email': 'new@example.test',
                          'role': 'patient',
                          'display_name': 'New'
                        },
                        'access_token': 'new-token',
                        'refresh_token': 'new-refresh'
                      }),
                      201)
                  : http.Response('{}', 200)))),
      capabilitiesProvider.overrideWithValue(const PlatformCapabilities(
          canScheduleOsReminders: false,
          canRegisterPush: false,
          canExportFiles: false,
          canDialTel: false,
          canPickFiles: false,
          canGeolocate: false,
          canBindGoogleCalendar: false,
          isWebBuild: false)),
    ]);
    var disposed = false;
    addTearDown(() {
      if (!disposed) container.dispose();
    });
    final store = container.read(malvaStoreProvider.notifier);
    final session = await store.registerPatientOnline(
        email: 'new@example.test',
        password: 'Synthetic123!',
        displayName: 'New');
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container, child: const MalvaApp()));
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    tester
        .widget<LoginScreen>(find.byType(LoginScreen))
        .onAuthenticated(session);
    await tester.pumpAndSettle();
    expect(find.byType(InitialScreeningConsentScreen), findsOneWidget);
    await tester.tap(find.text('Saya setuju'));
    await tester.pumpAndSettle();
    expect(find.byType(InitialSymptomsScreen), findsOneWidget);
    await tester.tap(find.byIcon(Icons.arrow_back_rounded));
    await tester.pumpAndSettle();
    expect(find.byType(PatientShell), findsOneWidget);
    expect(find.byType(InitialScreeningConsentScreen), findsNothing);
    expect(store.state.assessments, isEmpty);
    expect(store.state.screeningBundles, isEmpty);
    await tester.pumpWidget(const SizedBox());
    container.dispose();
    disposed = true;
  });
}
