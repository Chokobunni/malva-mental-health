import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:malva_mental_health/src/models.dart';
import 'package:malva_mental_health/src/screens/schedule_package_sessions_screen.dart';
import 'package:malva_mental_health/src/services/malva_api_client.dart';
import 'package:malva_mental_health/src/theme.dart';

void main() {
  testWidgets(
      'package scheduler shows real quota and identifies selected session',
      (tester) async {
    tester.view.physicalSize = const Size(390, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final api = MalvaApiClient(
        baseUrl: 'https://synthetic.test',
        httpClient: MockClient((request) async {
          final body = switch (request.url.path) {
            '/v1/doctors/pro' => {
                'credential': {'specialization': 'Sp.KJ'},
                'schedules': []
              },
            '/v1/doctors/pro/availability' => {
                'days': [
                  {'date': '2099-01-02', 'free_slots': 2}
                ]
              },
            '/v1/doctors/pro/slots' => {
                'slots': [
                  {'time': '10:00', 'available': true}
                ]
              },
            '/v1/professionals/pro/meet-status' => {'ready': true},
            _ => <String, dynamic>{},
          };
          return http.Response(jsonEncode(body), 200);
        }));
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
            theme: buildMalvaTheme(),
            home: SchedulePackageSessionsScreen(
              api: api,
              session: const AuthSession(
                  role: UserRole.patient,
                  identifier: 'patient',
                  displayName: 'Pasien',
                  accessToken: 'token'),
              package: const BackendCarePackage(
                  id: 'package',
                  patientId: 'patient',
                  professionalId: 'pro',
                  professionalName: 'Dokter Uji',
                  totalSessions: 4,
                  usedSessions: 2,
                  remainingSessions: 2,
                  status: 'active',
                  expiresAt: '2099-01-03T12:00:00+07:00'),
            ))));
    await tester.pumpAndSettle();
    expect(find.text('2 dari 4 sesi tersisa'), findsOneWidget);
    expect(find.text('50%'), findsOneWidget);
    expect(find.text('Total jadwal dipilih'), findsOneWidget);
    expect(find.text('0 sesi dipilih'), findsOneWidget);
    final choose = find.widgetWithText(TextButton, 'Pilih jadwal').first;
    await Scrollable.ensureVisible(tester.element(choose), alignment: .5);
    await tester.pumpAndSettle();
    await tester.tap(choose);
    await tester.pumpAndSettle();
    expect(find.text('Pilih Jadwal Sesi 3'), findsOneWidget);
    expect(find.text('1. Pilih Tanggal'), findsOneWidget);
    expect(find.text('2. Pilih Jam (WIB)'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
