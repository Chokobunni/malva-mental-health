import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:malva_mental_health/src/models.dart';
import 'package:malva_mental_health/src/screens/pro_schedule_screen.dart';
import 'package:malva_mental_health/src/services/malva_api_client.dart';

void main() {
  testWidgets(
      'professional history filters attendance outcomes and cancellations',
      (tester) async {
    tester.view.physicalSize = const Size(390, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final sessions = [
      ('Sesi Selesai', 'completed', 'attended', 'attended'),
      ('Sesi Batal', 'cancelled_by_patient', '', ''),
      ('Profesional Absen', 'no_show', 'attended', 'absent'),
      ('Pasien Absen', 'no_show', 'absent', 'attended'),
      ('Dua Absen', 'no_show', 'absent', 'absent'),
      ('Riwayat Lama', 'no_show', '', ''),
    ];
    final api = MalvaApiClient(
      baseUrl: 'https://synthetic.test',
      httpClient: MockClient((request) async => http.Response(
            jsonEncode({
              'sessions': [
                if (request.url.queryParameters['scope'] == 'past')
                  for (final (name, status, patient, professional) in sessions)
                    {
                      'id': name,
                      'patient_id': 'patient',
                      'patient_name': name,
                      'professional_id': 'pro',
                      'scheduled_at': '2026-01-02T10:00:00+07:00',
                      'status': status,
                      'patient_attendance': patient,
                      'professional_attendance': professional,
                    },
              ]
            }),
            200,
          )),
    );
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
            home: Scaffold(
      body: ProScheduleScreen(
        apiClient: api,
        session: const AuthSession(
          role: UserRole.professional,
          identifier: 'pro',
          displayName: 'Profesional',
          accessToken: 'token',
        ),
      ),
    ))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Riwayat Sesi (6)'));
    await tester.pumpAndSettle();
    expect(find.text('Selesai 1'), findsOneWidget);
    expect(find.text('Dibatalkan 1'), findsOneWidget);
    expect(find.text('Tidak Hadir 4'), findsOneWidget);
    expect(find.text('Semua 6'), findsOneWidget);
    expect(find.text('Sesi Selesai'), findsOneWidget);

    await tester.tap(find.text('Dibatalkan 1'));
    await tester.pumpAndSettle();
    expect(find.text('Sesi Batal'), findsOneWidget);
    expect(find.text('Sesi Selesai'), findsNothing);

    await tester.tap(find.text('Tidak Hadir 4'));
    await tester.pumpAndSettle();
    expect(find.text('Profesional Tidak Hadir'), findsOneWidget);
    expect(find.text('Pasien Tidak Hadir'), findsOneWidget);
    expect(find.text('Keduanya Tidak Hadir'), findsOneWidget);
    expect(find.text('Tidak hadir'), findsOneWidget);
    expect(find.text('Sesi Batal'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('video Link copies actual saved URL without editing it',
      (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData')
        copied = (call.arguments as Map)['text'] as String;
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    const s = BackendCareSession(
        id: 's',
        patientId: 'p',
        professionalId: 'pro',
        status: 'scheduled',
        sessionType: 'video',
        meetingUrl: 'https://meet.google.com/abc-defg-hij');
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
            home: Scaffold(
                body: ProfessionalSessionActions(
                    session: s, onChanged: () async {})))));
    await tester.tap(find.text('Aksi lain'));
    await tester.pumpAndSettle();
    expect(find.text('Profil'), findsOneWidget);
    expect(find.text('Reschedule'), findsOneWidget);
    await tester.tap(find.text('Link'));
    await tester.pumpAndSettle();
    expect(copied, s.meetingUrl);
    expect(find.text('Link sesi video'), findsNothing);
    expect(find.text('Ubah link video'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('chat actions offer full width reschedule and omit video Link',
      (tester) async {
    const s = BackendCareSession(
        id: 's', patientId: 'p', professionalId: 'pro', status: 'scheduled');
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
            home: Scaffold(
                body: ProfessionalSessionActions(
                    session: s, onChanged: () async {})))));
    await tester.tap(find.text('Aksi lain'));
    await tester.pumpAndSettle();
    expect(find.text('Link'), findsNothing);
    expect(find.text('Ubah link video'), findsNothing);
    final reschedule =
        tester.getSize(find.widgetWithText(OutlinedButton, 'Reschedule'));
    final profile =
        tester.getSize(find.widgetWithText(OutlinedButton, 'Profil'));
    expect(reschedule.width, greaterThan(profile.width * 1.8));
    await tester.pumpWidget(const SizedBox());
  });
}
