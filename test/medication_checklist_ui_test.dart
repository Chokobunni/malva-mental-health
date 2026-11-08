import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:malva_mental_health/src/models.dart';
import 'package:malva_mental_health/src/providers/providers.dart';
import 'package:malva_mental_health/src/screens/mood_medication_checkin_screen.dart';
import 'package:malva_mental_health/src/screens/medication_screen.dart';
import 'package:malva_mental_health/src/services/malva_api_client.dart';

void main() {
  testWidgets('refresh discards medication data after an account switch',
      (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    const session = AuthSession(
        role: UserRole.patient,
        identifier: 'a',
        displayName: 'A',
        backendUserId: 'a',
        accessToken: 'a');
    final pending = Completer<http.Response>();
    final api = MalvaApiClient(
        baseUrl: 'https://test.invalid',
        httpClient: MockClient((request) => pending.future));
    final container = ProviderContainer(overrides: [
      authStateProvider
          .overrideWith((ref) => AuthNotifier()..setSession(session))
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
            home: MedicationScreen(apiClient: api, session: session))));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, 500));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    container.read(authStateProvider.notifier).setSession(const AuthSession(
        role: UserRole.patient,
        identifier: 'b',
        displayName: 'B',
        backendUserId: 'b',
        accessToken: 'b'));
    pending.complete(http.Response(
        '{"medications":[{"id":"a-med", "name":"A medicine"}]}', 200));
    await tester.pumpAndSettle();
    expect(container.read(malvaStoreProvider).medications, isEmpty);
  });
  testWidgets('same-owner token rotation still confirms accepted dose stock',
      (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    tester.view.physicalSize = const Size(390, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const session = AuthSession(
        role: UserRole.patient,
        identifier: 'a',
        displayName: 'A',
        backendUserId: 'a',
        accessToken: 'old');
    final pending = Completer<http.Response>();
    final api = MalvaApiClient(
        baseUrl: 'https://test.invalid',
        httpClient: MockClient((request) async => request.method == 'POST'
            ? pending.future
            : http.Response('{"medications":[],"medication_logs":[]}', 200)));
    final container = ProviderContainer(overrides: [
      authStateProvider
          .overrideWith((ref) => AuthNotifier()..setSession(session))
    ]);
    addTearDown(container.dispose);
    final med = const Medication(
        id: '00000000-0000-4000-8000-000000000001',
        name: 'Obat pasien',
        dosage: '5 mg',
        form: 'Tablet',
        reminders: [
          MedicationReminder(
              time: TimeOfDay(hour: 8, minute: 0),
              relationToMeal: 'Setelah makan')
        ],
        currentStock: 10,
        alertBelow: 2,
        source: 'Pasien');
    final store = container.read(malvaStoreProvider.notifier);
    store.replaceMedications([med]);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
            home: MedicationScreen(apiClient: api, session: session))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Take Now'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Taken'));
    await tester.pump();
    container.read(authStateProvider.notifier).updateTokens('new', 'refresh');
    pending.complete(http.Response('{"medication_log":{}}', 200));
    await tester.pumpAndSettle();
    store.replaceMedications([med.copyWith(currentStock: 9)]);
    expect(
        container.read(malvaStoreProvider).medications.single.currentStock, 9);
  });
  testWidgets(
      'temporary medication cannot submit a dose before receiving its server id',
      (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    tester.view.physicalSize = const Size(390, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(malvaStoreProvider.notifier).replaceMedications([
      const Medication(
          id: 'med_local',
          name: 'Obat baru',
          dosage: '5 mg',
          form: 'Tablet',
          reminders: [
            MedicationReminder(
                time: TimeOfDay(hour: 8, minute: 0),
                relationToMeal: 'Setelah makan')
          ],
          currentStock: 10,
          alertBelow: 2,
          source: 'Pasien')
    ]);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: MedicationScreen())));
    await tester.pumpAndSettle();
    expect(find.text('Menunggu sync'), findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Menunggu sync'))
            .onPressed,
        isNull);
    expect(
        container.read(malvaStoreProvider).medications.single.currentStock, 10);
    expect(container.read(malvaStoreProvider).medicationLogs, isEmpty);
  });
  testWidgets(
      'phone medication checklist opens cleanly and disables pending medication only',
      (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final pending = Completer<http.Response>();
    var posts = 0;
    final api = MalvaApiClient(
        baseUrl: 'https://test.invalid',
        httpClient: MockClient((request) async {
          if (request.method == 'POST') {
            posts++;
            return pending.future;
          }
          return http.Response(
              jsonEncode(
                  {'moods': [], 'medications': [], 'medication_logs': []}),
              200);
        }));
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(malvaStoreProvider.notifier).replaceMedications([
      for (var i = 1; i < 3; i++)
        Medication(
            id: '00000000-0000-4000-8000-00000000000$i',
            name: 'Obat $i',
            dosage: '5 mg',
            form: 'Tablet',
            reminders: const [
              MedicationReminder(
                  time: TimeOfDay(hour: 8, minute: 0),
                  relationToMeal: 'Setelah makan')
            ],
            currentStock: 10,
            alertBelow: 2,
            source: 'Pasien')
    ]);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
            home: MoodMedicationCheckinScreen(
                apiClient: api,
                session: const AuthSession(
                    role: UserRole.patient,
                    identifier: 'a',
                    displayName: 'A',
                    accessToken: 'a')))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Medication'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(find.text('Take Now').first, 250);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Take Now').first);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Taken'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(posts, 1);
    expect(find.text('Menyimpan…'), findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Menyimpan…'))
            .onPressed,
        isNull);
    expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Take Now'))
            .onPressed,
        isNotNull);
    expect(tester.takeException(), isNull);
    pending.complete(http.Response('{"error":"offline"}', 500));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
