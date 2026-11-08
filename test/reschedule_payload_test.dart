import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:malva_mental_health/src/models.dart';
import 'package:malva_mental_health/src/providers/auth_providers.dart';
import 'package:malva_mental_health/src/screens/care_package_screen.dart';
import 'package:malva_mental_health/src/screens/pro_schedule_screen.dart';
import 'package:malva_mental_health/src/services/malva_api_client.dart';
import 'package:malva_mental_health/src/theme.dart';

const patient = AuthSession(
    displayName: 'Synthetic',
    role: UserRole.patient,
    identifier: 'patient',
    backendUserId: 'patient',
    accessToken: 'patient-token');
const professional = AuthSession(
    displayName: 'Synthetic',
    role: UserRole.professional,
    identifier: 'professional',
    backendUserId: 'pro',
    accessToken: 'pro-token');
const package = BackendCarePackage(
    id: 'pkg',
    patientId: 'patient',
    professionalId: 'pro',
    status: 'active',
    expiresAt: '2099-02-01T10:00:00+07:00');
Map<String, dynamic> sessionJson() => {
      'id': 'session',
      'package_id': 'pkg',
      'patient_id': 'patient',
      'professional_id': 'pro',
      'scheduled_at': '2099-01-01T10:00:00+07:00',
      'session_type': 'chat',
      'status': 'scheduled',
      'duration_minutes': 30
    };
http.Response jsonResponse(Object body) => http.Response(jsonEncode(body), 200,
    headers: {'content-type': 'application/json'});

void main() {
  for (final isPatient in [true, false]) {
    testWidgets(
        '${isPatient ? "patient" : "professional"} reschedule sends only WIB wall clock to HTTP',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final payloads = <Map<String, dynamic>>[];
      final api = MalvaApiClient(
          baseUrl: 'http://backend.test',
          httpClient: MockClient((r) async {
            if (r.method == 'POST' && r.url.path.endsWith('/reschedule')) {
              payloads.add(jsonDecode(r.body) as Map<String, dynamic>);
              return jsonResponse({'session': sessionJson()});
            }
            if (r.url.path == '/v1/care-packages')
              return jsonResponse({'packages': []});
            if (r.url.path == '/v1/care-sessions')
              return jsonResponse({
                'sessions': r.url.queryParameters['scope'] == 'past' ||
                        r.url.queryParameters['scope'] == 'today'
                    ? []
                    : [sessionJson()]
              });
            if (r.url.path.endsWith('/availability'))
              return jsonResponse({
                'days': [
                  {
                    'date': '2099-01-02',
                    'day_of_week': 5,
                    'off': false,
                    'free_slots': 1
                  }
                ]
              });
            if (r.url.path.endsWith('/slots'))
              return jsonResponse({
                'slots': [
                  {'time': '10:30', 'available': true}
                ]
              });
            if (r.url.path.endsWith('/meet-status'))
              return jsonResponse({'ready': true});
            if (r.url.path.endsWith('/schedules'))
              return jsonResponse({'schedules': []});
            if (r.url.path.endsWith('/pricing'))
              return jsonResponse({'pricing': {}});
            if (r.url.path.endsWith('/time-off'))
              return jsonResponse({'time_off': []});
            return http.Response('{"error":"unexpected"}', 404);
          }));
      final container = ProviderContainer(
          overrides: [apiClientProvider.overrideWithValue(api)]);
      addTearDown(container.dispose);
      container
          .read(authStateProvider.notifier)
          .setSession(isPatient ? patient : professional);
      await tester.pumpWidget(UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
              theme: buildMalvaTheme(),
              home: Scaffold(
                  body: isPatient
                      ? CarePackageScreen(
                          package: package, session: patient, apiClient: api)
                      : ProScheduleScreen(
                          session: professional, apiClient: api)))));
      await tester.pumpAndSettle();
      if (!isPatient) {
        await tester.ensureVisible(find.text('Aksi lain').first);
        await tester.tap(find.text('Aksi lain').first);
        await tester.pumpAndSettle();
      }
      await tester.ensureVisible(find.text('Reschedule').first);
      await tester.tap(find.text('Reschedule').first);
      await tester.pumpAndSettle();
      if (isPatient) {
        await tester.tap(find.widgetWithText(ChoiceChip, '10:30'));
        await tester.pump();
        await tester.tap(find.text('Pilih Jadwal'));
      } else {
        await tester.enterText(find.byType(TextField).at(0), '2099-01-02');
        await tester.enterText(find.byType(TextField).at(1), '10:30');
        await tester.tap(find.text('Pindahkan'));
      }
      await tester.pumpAndSettle();
      expect(payloads, [
        {'scheduled_at': '2099-01-02T10:30'}
      ]);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
