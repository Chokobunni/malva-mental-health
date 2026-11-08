import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:malva_mental_health/src/models.dart';
import 'package:malva_mental_health/src/providers/auth_providers.dart';
import 'package:malva_mental_health/src/screens/portal/shared_patient_data_screen.dart';
import 'package:malva_mental_health/src/services/malva_api_client.dart';
import 'package:malva_mental_health/src/widgets/therapy_library.dart';

void main() {
  testWidgets('professional opens full saved answers from shared therapy card',
      (tester) async {
    const session = AuthSession(
        role: UserRole.professional,
        identifier: 'professional',
        displayName: 'Profesional',
        backendUserId: 'pro-1',
        accessToken: 'token');
    final api = MalvaApiClient(
        baseUrl: 'http://backend.test',
        httpClient: MockClient((request) async {
          final body = switch (request.url.path) {
            '/v1/patient-professional-links' => {
                'links': [
                  {
                    'patient_id': 'patient-1',
                    'patient_display_name': 'Pasien',
                    'professional_id': 'pro-1',
                    'status': 'active'
                  }
                ]
              },
            '/v1/therapy-submissions' => {
                'submissions': [
                  {
                    'id': 'therapy-1',
                    'patient_id': 'patient-1',
                    'module_id': 'abcde',
                    'title': 'Latihan tersimpan',
                    'summary': 'Ringkasan',
                    'answers': {'activating': 'Jawaban lengkap pasien'},
                    'shared_with_professional_id': 'pro-1'
                  }
                ]
              },
            _ => {'moods': []},
          };
          if (request.url.path == '/v1/therapy-submissions') {
            expect(request.url.queryParameters['patient_id'], 'patient-1');
          }
          return http.Response(jsonEncode(body), 200,
              headers: {'content-type': 'application/json'});
        }));
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(authStateProvider.notifier).setSession(session);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
            home: SharedPatientDataScreen(session: session, apiClient: api))));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Terapi'));
    await tester.tap(find.text('Terapi'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Latihan tersimpan'));
    await tester.pumpAndSettle();
    expect(find.byType(TherapySubmissionView), findsOneWidget);
    expect(find.text('Jawaban lengkap pasien'), findsOneWidget);
    container.read(authStateProvider.notifier).clearSession();
    await tester.pumpAndSettle();
    expect(find.text('Jawaban lengkap pasien'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
