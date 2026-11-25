import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:malva_mental_health/src/providers/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:malva_mental_health/src/models.dart';
import 'package:malva_mental_health/src/screens/professional_session_notes_screen.dart';
import 'package:malva_mental_health/src/services/malva_api_client.dart';
import 'package:malva_mental_health/src/services/server_clock.dart';
import 'package:malva_mental_health/src/time/wib.dart';
import 'package:malva_mental_health/src/widgets/care_session_card.dart';

void main() {
  setUp(initializeWib);
  test('sectioned clinical summary round trips and legacy notes survive', () {
    final values = [
      'Keluhan yang tersimpan',
      'Evaluasi',
      'Saran',
      'Rencana',
      'Target'
    ];
    expect(parseSessionNotes(formatSessionNotes(values)), values);
    expect(parseSessionNotes('Catatan lama bebas'),
        ['Catatan lama bebas', '', '', '', '']);
    expect(parseSessionNotes(formatSessionNotes(['', '', 'Saran', '', ''])),
        ['', '', 'Saran', '', '']);
  });
  testWidgets(
      'patient detail keeps real ID, summary, and has no completion control',
      (tester) async {
    const session = BackendCareSession(
        id: 'real-session-42',
        patientId: 'patient',
        professionalId: 'pro',
        professionalName: 'Dokter',
        status: 'completed',
        summaryForPatient: 'Ringkasan tersimpan');
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
            home: Scaffold(
                body: CareSessionCard(
                    session: session,
                    role: UserRole.patient,
                    onOpenChat: () {},
                    onChanged: () async {})))));
    await tester.tap(find.text('Lihat Detail Sesi'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text('Ringkasan Catatan Sesi'), findsOneWidget);
    expect(find.text('ID Sesi: real-session-42'), findsOneWidget);
    expect(find.text('Ringkasan tersimpan'), findsOneWidget);
    expect(find.text('Selesaikan sesi'), findsNothing);
    expect(find.text('Isi Catatan Sesi'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('upcoming chat uses countdown and collapsed secondary actions',
      (tester) async {
    final session = BackendCareSession(
        id: 'future',
        patientId: 'patient',
        professionalId: 'pro',
        professionalName: 'Profesional',
        status: 'scheduled',
        scheduledAt: wibIso(ServerClock.now().add(const Duration(hours: 2))));
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
            home: Scaffold(
                body: SingleChildScrollView(
                    child: CareSessionCard(
                        session: session,
                        role: UserRole.patient,
                        onOpenChat: () {},
                        onChanged: () async {},
                        onCancel: () {},
                        onReschedule: () {}))))));
    expect(find.text('AKSI LAIN'), findsOneWidget);
    expect(find.textContaining('Mulai dalam'), findsOneWidget);
    expect(find.text('Reschedule'), findsNothing);
    await tester.tap(find.text('AKSI LAIN'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Reschedule'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  for (final publish in [false, true]) {
    testWidgets(
        publish
            ? 'publish writes readable summary and preserves private note'
            : 'draft writes only private note and does not share summary',
        (tester) async {
      Map<String, dynamic>? payload;
      final api = MalvaApiClient(
          baseUrl: 'https://synthetic.test',
          httpClient: MockClient((request) async {
            payload = jsonDecode(request.body) as Map<String, dynamic>;
            return http.Response(
                jsonEncode({
                  'session': {
                    'id': 'notes-session',
                    'patient_id': 'patient',
                    'professional_id': 'pro',
                    'status': 'completed'
                  }
                }),
                200);
          }));
      const owner = AuthSession(
          role: UserRole.professional,
          identifier: 'pro',
          displayName: 'Pro',
          backendUserId: 'pro',
          accessToken: 'token');
      const session = BackendCareSession(
          id: 'notes-session',
          patientId: 'patient',
          professionalId: 'pro',
          status: 'completed',
          summaryForPatient: 'Legacy summary',
          privateNote: 'Private existing');
      await tester.pumpWidget(ProviderScope(
          overrides: [currentSessionProvider.overrideWith((ref) => owner)],
          child: MaterialApp(
              home: ProfessionalSessionNotesScreen(
                  session: session, apiClient: api))));
      await tester.enterText(
          find.byType(TextField).first, 'Keluhan diperbarui');
      await tester.tap(find.text(publish ? 'Pratinjau' : 'Simpan Draf'));
      if (publish) {
        await tester.pumpAndSettle();
        expect(payload, isNull);
        expect(find.text('Pratinjau Catatan Sesi'), findsOneWidget);
        expect(find.text('Private existing'), findsNothing);
        await tester.tap(find.text('Simpan & Selesai'));
      }
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      if (publish) {
        expect(payload?['summary_for_patient'],
            'Keluhan Utama\nKeluhan diperbarui');
        expect(payload?['private_note'], 'Private existing');
      } else {
        expect(payload?.containsKey('summary_for_patient'), false);
        expect(payload?['private_note'], contains('Private existing'));
        expect(payload?['private_note'], contains('Keluhan diperbarui'));
      }
      expect(payload?.containsKey('status'), false);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
