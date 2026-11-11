import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:malva_mental_health/src/models.dart';
import 'package:malva_mental_health/src/providers/providers.dart';
import 'package:malva_mental_health/src/screens/care_package_screen.dart';
import 'package:malva_mental_health/src/services/malva_api_client.dart';
import 'package:malva_mental_health/src/theme.dart';

void main() {
  testWidgets(
      'scheduler keeps practice and package expiry limits when booking video',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const package = BackendCarePackage(
        id: 'package',
        patientId: 'patient',
        professionalId: 'pro',
        professionalName: 'Profesional Uji',
        status: 'active',
        expiresAt: '2099-01-02T12:00:00+07:00');
    final scheduled = <Map<String, dynamic>>[];
    final api = MalvaApiClient(
        baseUrl: 'https://synthetic.test',
        httpClient: MockClient((request) async {
          if (request.method == 'POST' &&
              request.url.path == '/v1/care-sessions') {
            scheduled.add(jsonDecode(request.body) as Map<String, dynamic>);
            return http.Response(
                jsonEncode({
                  'session': {'id': 'created'},
                  'meet_pending': true
                }),
                200);
          }
          final body = switch (request.url.path) {
            '/v1/care-packages' => {'packages': []},
            '/v1/care-sessions' => {'sessions': []},
            '/v1/professionals/pro/meet-status' => {'ready': true},
            '/v1/doctors/pro/availability' => {
                'days': [
                  {'date': '2099-01-01', 'off': true, 'free_slots': 5},
                  {'date': '2099-01-02', 'off': false, 'free_slots': 3},
                  {'date': '2099-01-03', 'off': false, 'free_slots': 3},
                ]
              },
            '/v1/doctors/pro/slots' => {
                'slots': [
                  {'time': '10:00', 'available': true},
                  {'time': '11:00', 'available': false},
                  {'time': '12:00', 'available': true},
                  {'time': '13:00', 'available': true},
                ]
              },
            _ => <String, Object>{},
          };
          return http.Response(jsonEncode(body), 200);
        }));
    final container = ProviderContainer(
        overrides: [apiClientProvider.overrideWithValue(api)]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
            theme: buildMalvaTheme(),
            home: CarePackageScreen(
                package: package,
                apiClient: api,
                session: const AuthSession(
                    role: UserRole.patient,
                    identifier: 'patient',
                    displayName: 'Pasien',
                    backendUserId: 'patient',
                    accessToken: 'token')))));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Jadwalkan Sesi'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Jadwalkan Sesi'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Tutup'), findsOneWidget);
    expect(find.textContaining('1/1'), findsNothing);
    expect(find.textContaining('3/1'), findsNothing);
    expect(find.text('10:00'), findsOneWidget);
    expect(find.text('11:00'), findsNothing);
    expect(find.text('12:00'), findsNothing);
    expect(find.text('13:00'), findsNothing);
    await tester.tap(find.text('10:00'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Pilih Jadwal'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pilih Jadwal'));
    await tester.pumpAndSettle();
    expect(scheduled.single, containsPair('scheduled_at', '2099-01-02T10:00'));
    expect(scheduled.single, containsPair('session_type', 'video'));
    expect(scheduled.single, containsPair('duration_minutes', 60));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  for (final withHistory in [false, true]) {
    testWidgets(
        'package shows real quota, role, countdown and history=$withHistory',
        (tester) async {
      const package = BackendCarePackage(
          id: 'package',
          patientId: 'patient',
          professionalId: 'pro',
          professionalName: 'Profesional Uji',
          status: 'active',
          totalSessions: 8,
          usedSessions: 2,
          remainingSessions: 6,
          expiresAt: '2099-12-18T10:00:00+07:00');
      final api = MalvaApiClient(
          baseUrl: 'https://synthetic.test',
          httpClient: MockClient((request) async {
            final body = switch (request.url.path) {
              '/v1/care-packages' => {'packages': []},
              '/v1/care-sessions' => {
                  'sessions': [
                    if (withHistory)
                      {
                        'id': 'completed',
                        'package_id': 'package',
                        'patient_id': 'patient',
                        'professional_id': 'pro',
                        'status': 'completed',
                        'session_type': 'video',
                        'duration_minutes': 60,
                        'scheduled_at': '2026-01-01T14:00:00+07:00',
                      },
                    {
                      'id': 'future',
                      'package_id': 'package',
                      'patient_id': 'patient',
                      'professional_id': 'pro',
                      'status': 'scheduled',
                      'session_type': 'video',
                      'duration_minutes': 60,
                      'scheduled_at': '2099-01-01T14:00:00+07:00',
                    }
                  ]
                },
              '/v1/doctors/pro' => {
                  'credential': {'specialization': 'Sp.KJ'}
                },
              _ => <String, Object>{},
            };
            return http.Response(jsonEncode(body), 200);
          }));
      final container = ProviderContainer(
          overrides: [apiClientProvider.overrideWithValue(api)]);
      addTearDown(container.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
              theme: buildMalvaTheme(),
              home: CarePackageScreen(
                  package: package,
                  apiClient: api,
                  session: const AuthSession(
                      role: UserRole.patient,
                      identifier: 'patient',
                      displayName: 'Pasien',
                      backendUserId: 'patient',
                      accessToken: 'token')))));
      await tester.pumpAndSettle();
      expect(find.text('6/8 sesi tersisa'), findsOneWidget);
      expect(find.text('Psikiater'), findsOneWidget);
      await tester.drag(find.byType(ListView).first, const Offset(0, -450));
      await tester.pumpAndSettle();
      expect(find.textContaining('Mulai dalam'), findsOneWidget);
      expect(find.text('Riwayat Sesi'),
          withHistory ? findsOneWidget : findsNothing);
      if (withHistory) expect(find.text('Selesai'), findsOneWidget);
      expect(find.text('Belum ada riwayat'), findsNothing);
      expect(find.text('Gabung video call'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
