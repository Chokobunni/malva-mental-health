import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:malva_mental_health/src/models.dart';
import 'package:malva_mental_health/src/providers/providers.dart';
import 'package:malva_mental_health/src/screens/professional_session_notes_screen.dart';
import 'package:malva_mental_health/src/screens/portal/prescription_wizard_screen.dart';
import 'package:malva_mental_health/src/services/malva_api_client.dart';
import 'package:malva_mental_health/src/services/server_clock.dart';
import 'package:malva_mental_health/src/time/wib.dart';

void main() {
  setUp(initializeWib);
  for (final live in [true, false]) {
    testWidgets(
        'add medication persists directly in ${live ? 'live' : 'completed'} notes context and rejects stale owner',
        (tester) async {
      tester.view.physicalSize = const Size(430, 2100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      const owner = AuthSession(
          role: UserRole.professional,
          identifier: 'pro',
          backendUserId: 'pro',
          displayName: 'Dokter',
          accessToken: 'token');
      final account = StateProvider<AuthSession?>((ref) => owner);
      final container = ProviderContainer(overrides: [
        currentSessionProvider.overrideWith((ref) => ref.watch(account))
      ]);
      addTearDown(container.dispose);
      final posts = <http.Request>[];
      final api = MalvaApiClient(
          baseUrl: 'https://synthetic.test',
          httpClient: MockClient((request) async {
            if (request.url.path == '/v1/credentials/me')
              return http.Response(
                  '{"credential":{"specialization":"Sp.KJ","verification_status":"VERIFIED"}}',
                  200);
            if (request.method == 'POST') {
              posts.add(request);
              return http.Response(
                  '{"medication":{"id":"saved-med","name":"Obat dari server","dosage":"5 mg"}}',
                  201);
            }
            return http.Response('{"goals":[],"medications":[]}', 200);
          }));
      await tester.pumpWidget(UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
              home: ProfessionalSessionNotesScreen(
                  apiClient: api,
                  session: BackendCareSession(
                      id: 'session',
                      patientId: 'patient',
                      professionalId: 'pro',
                      status: live ? 'scheduled' : 'completed',
                      scheduledAt: wibIso(ServerClock.now().subtract(live
                          ? const Duration(minutes: 30)
                          : const Duration(hours: 2))))))));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Tambah Obat'), 300,
          scrollable: find.byType(Scrollable).first);
      await tester.tap(find.text('Tambah Obat'));
      await tester.pumpAndSettle();
      final editor = tester.widget<EPrescriptionFormScreen>(
          find.byType(EPrescriptionFormScreen));
      const value = Medication(
          id: '',
          name: 'Obat input',
          dosage: '5 mg',
          form: 'Tablet',
          reminders: [],
          currentStock: 10,
          alertBelow: 3,
          source: 'Profesional');
      await editor.onSaveMedication!(value);
      expect(posts, hasLength(1));
      expect(posts.single.url.path, '/v1/medications');
      expect(posts.single.url.queryParameters['session_id'], 'session');
      expect(jsonDecode(posts.single.body)['patient_id'], 'patient');
      Navigator.pop(tester.element(find.byType(EPrescriptionFormScreen)));
      await tester.pumpAndSettle();
      expect(find.text('Obat dari server'), findsOneWidget);
      expect(find.text('Obat input'), findsNothing);
      container.read(account.notifier).state = null;
      await tester.pump();
      await expectLater(editor.onSaveMedication!(value), throwsStateError);
      expect(posts, hasLength(1));
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
  test(
      'notes resources use live session and strict completed cutoff without extending note saves',
      () {
    final now = ServerClock.now();
    BackendCareSession session(String status, Duration sinceStart) =>
        BackendCareSession(
          id: 'session',
          patientId: 'patient',
          professionalId: 'pro',
          status: status,
          scheduledAt: wibIso(now.subtract(sinceStart)),
        );
    final live = session('scheduled', const Duration(minutes: 30));
    expect(live.canManageNoteResources, true);
    expect(live.canWriteNotes, false);
    expect(
        session('scheduled', const Duration(hours: 2)).canManageNoteResources,
        false);
    expect(
        session('completed', const Duration(hours: 24, minutes: 59))
            .canManageNoteResources,
        true);
    expect(
        session('completed', const Duration(hours: 25)).canManageNoteResources,
        false);
    expect(
        session('cancelled_by_patient', const Duration(hours: 2))
            .canManageNoteResources,
        false);
  });
  testWidgets(
      'active patient resources appear in their existing editor sections',
      (tester) async {
    tester.view.physicalSize = const Size(430, 2100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const owner = AuthSession(
        role: UserRole.professional,
        identifier: 'pro',
        backendUserId: 'pro',
        displayName: 'Dokter',
        accessToken: 'token');
    final api = MalvaApiClient(
        baseUrl: 'https://synthetic.test',
        httpClient: MockClient((request) async {
          if (request.url.path == '/v1/credentials/me') {
            return http.Response(
                jsonEncode({
                  'credential': {
                    'specialization': 'Sp.KJ',
                    'verification_status': 'VERIFIED'
                  }
                }),
                200);
          }
          return http.Response(
              jsonEncode({
                'goals': [
                  {'id': 'goal', 'title': 'Jalan pagi', 'is_active': true}
                ],
                'medications': [
                  {'id': 'med', 'name': 'Obat rutin', 'dosage': '10 mg'}
                ]
              }),
              200);
        }));
    await tester.pumpWidget(ProviderScope(
        overrides: [currentSessionProvider.overrideWith((ref) => owner)],
        child: MaterialApp(
            home: ProfessionalSessionNotesScreen(
                apiClient: api,
                session: BackendCareSession(
                  id: 'session',
                  patientId: 'patient',
                  professionalId: 'pro',
                  status: 'completed',
                  scheduledAt: wibIso(
                      ServerClock.now().subtract(const Duration(hours: 2))),
                )))));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Jalan pagi'), 350,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('Isi Detail Sesi'), findsNothing);
    expect(find.text('Obat Aktif'), findsNothing);
    expect(find.byTooltip('Edit target'), findsOneWidget);
    expect(find.byTooltip('Edit obat'), findsOneWidget);
    expect(find.text('Obat rutin'), findsOneWidget);
    expect(tester.getTopLeft(find.text('Obat rutin')).dy,
        lessThan(tester.getTopLeft(find.text('Target & Kebiasaan Terapi')).dy));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test(
      'notes resource mutation clients scope existing routes to selected session',
      () async {
    final requests = <http.Request>[];
    final api = MalvaApiClient(
        baseUrl: 'https://synthetic.test',
        httpClient: MockClient((request) async {
          requests.add(request);
          return http.Response(
              jsonEncode({
                'goal': {'id': 'goal', 'title': 'Title'},
                'medication': {'id': 'med', 'name': 'Name'}
              }),
              200);
        }));
    await api.createGoal(
        accessToken: 'token',
        title: 'Title',
        patientId: 'patient',
        sessionId: 'session');
    await api.updateGoal(
        accessToken: 'token',
        goalId: 'goal',
        title: 'Title',
        patientId: 'patient',
        sessionId: 'session');
    await api.updateMedication(
        accessToken: 'token',
        medicationId: 'med',
        name: 'Name',
        dosage: '10 mg',
        form: 'Tablet',
        reminderTime: '',
        relationToMeal: '',
        currentStock: 10,
        alertBelow: 3,
        source: 'Profesional',
        patientId: 'patient',
        sessionId: 'session');
    for (final request in requests) {
      expect(request.url.queryParameters['session_id'], 'session');
      expect(jsonDecode(request.body)['patient_id'], 'patient');
      expect(jsonDecode(request.body).containsKey('session_id'), false);
    }
    expect(requests.map((request) => request.method), ['POST', 'PATCH', 'PUT']);
  });
  testWidgets(
      'reopened draft numbers recommendations and hides preview on account switch',
      (tester) async {
    tester.view.physicalSize = const Size(430, 1500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const owner = AuthSession(
        role: UserRole.professional,
        identifier: 'pro',
        backendUserId: 'pro',
        displayName: 'Dokter');
    final account = StateProvider<AuthSession?>((ref) => owner);
    final container = ProviderContainer(overrides: [
      currentSessionProvider.overrideWith((ref) => ref.watch(account))
    ]);
    addTearDown(container.dispose);
    final values = [
      'Keluhan draf',
      '',
      '1. Jalan pagi\n2. Tidur teratur',
      '',
      ''
    ];
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
            home: ProfessionalSessionNotesScreen(
                session: BackendCareSession(
          id: 'session',
          patientId: 'patient',
          professionalId: 'pro',
          patientName: 'Pasien Uji',
          sessionType: 'video',
          status: 'completed',
          scheduledAt:
              wibIso(ServerClock.now().subtract(const Duration(hours: 2))),
          summaryForPatient: 'Ringkasan lama',
          privateNote:
              'Rahasia klinis\n\n[MALVA_DRAF_SESI_V1]\n${jsonEncode(values)}',
        )))));
    expect(find.text('Draf tersimpan'), findsOneWidget);
    expect(find.textContaining('WIB'), findsWidgets);
    expect(find.text('Konsultasi Video'), findsOneWidget);
    expect(find.text('Jalan pagi'), findsOneWidget);
    await tester.tap(find.byTooltip('Hapus rekomendasi 1'));
    await tester.pump();
    expect(find.text('Jalan pagi'), findsNothing);
    expect(find.text('1.'), findsOneWidget);
    await tester.tap(find.text('Tambah Rekomendasi'));
    await tester.pump();
    expect(find.text('2.'), findsOneWidget);
    await tester.tap(find.text('Pratinjau Ringkasan'));
    await tester.pumpAndSettle();
    expect(find.text('Pratinjau Ringkasan Sesi'), findsOneWidget);
    expect(find.text('1. Tidur teratur'), findsOneWidget);
    expect(find.text('Rahasia klinis').hitTestable(), findsNothing);
    container.read(account.notifier).state = const AuthSession(
        role: UserRole.professional,
        identifier: 'other',
        backendUserId: 'other',
        displayName: 'Lain');
    await tester.pumpAndSettle();
    expect(find.text('Keluhan draf'), findsNothing);
    expect(find.text('1. Tidur teratur'), findsNothing);
    expect(find.text('Tutup Pratinjau'), findsNothing);
  });
}
