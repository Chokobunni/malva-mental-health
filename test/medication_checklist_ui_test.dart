import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'package:malva_mental_health/src/services/server_clock.dart';
import 'package:malva_mental_health/src/time/wib.dart';
import 'package:malva_mental_health/src/services/offline_sync_service.dart';
import 'package:malva_mental_health/src/platform/contracts/ports.dart';

class _QueueStorage implements SecureStore {
  bool failWrite = true;
  String? value;
  @override
  Future<String?> read(String key) async => value;
  @override
  Future<void> write(String key, String data) async {
    if (failWrite) throw StateError('disk full');
    value = data;
  }

  @override
  Future<void> delete(String key) async => value = null;
}

void main() {
  testWidgets(
      'failed queue write can retry the original dose without consuming twice',
      (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    tester.view.physicalSize = const Size(390, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('dev.fluttercommunity.plus/connectivity'),
            (_) async => ['none']);
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('dev.fluttercommunity.plus/connectivity'),
            null));
    const session = AuthSession(
        role: UserRole.patient,
        identifier: 'a',
        displayName: 'A',
        backendUserId: 'a',
        accessToken: 'a');
    const id = '00000000-0000-4000-8000-000000000001';
    final attempts = <Map<String, dynamic>>[];
    final api = MalvaApiClient(
        baseUrl: 'https://test.invalid',
        httpClient: MockClient((request) async {
          if (request.method == 'POST')
            attempts.add(jsonDecode(request.body) as Map<String, dynamic>);
          return http.Response('{"error":"offline"}', 503);
        }));
    final storage = _QueueStorage();
    final queue = OfflineSyncService(
        apiClient: api, activeUserIdReader: () => 'a', secureStore: storage);
    addTearDown(queue.dispose);
    final container = ProviderContainer(overrides: [
      authStateProvider
          .overrideWith((ref) => AuthNotifier()..setSession(session)),
      offlineSyncServiceProvider.overrideWithValue(queue)
    ]);
    addTearDown(container.dispose);
    container.read(malvaStoreProvider.notifier).replaceMedications([
      const Medication(
          id: id,
          name: 'Obat pasien',
          dosage: '5 mg',
          form: 'Tablet',
          reminders: [],
          currentStock: 10,
          alertBelow: 2,
          source: 'Pasien')
    ]);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
            home: MedicationScreen(apiClient: api, session: session))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Take Now'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Taken'));
    await tester.pumpAndSettle();
    expect(queue.queue, isEmpty);
    expect(find.text('Coba simpan'), findsOneWidget);
    storage.failWrite = false;
    await tester.tap(find.text('Coba simpan'));
    await tester.pumpAndSettle();
    expect(attempts, hasLength(2));
    expect(attempts.first['taken_at'], attempts.last['taken_at']);
    expect(queue.queue, hasLength(1));
    expect(queue.queue.single.payload['taken_at'], attempts.first['taken_at']);
    expect(container.read(malvaStoreProvider).medicationLogs, hasLength(1));
    expect(
        container.read(malvaStoreProvider).medications.single.currentStock, 9);
  });

  testWidgets('coalesced server dose replaces the optimistic time and history',
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
        accessToken: 'a');
    const id = '00000000-0000-4000-8000-000000000001';
    final actual = parseWibStored(
        wibIso(ServerClock.now().subtract(const Duration(hours: 23))))!;
    final log = {
      'medication_id': id,
      'medication_name': 'Obat pasien',
      'status': 'taken',
      'taken_at': wibIso(actual)
    };
    final api = MalvaApiClient(
        baseUrl: 'https://test.invalid',
        httpClient: MockClient((request) async => http.Response(
            jsonEncode({
              'medication_log': log,
              'medications': [
                {'id': id, 'name': 'Obat pasien', 'current_stock': 9}
              ],
              'medication_logs': [log],
            }),
            200)));
    final container = ProviderContainer(overrides: [
      authStateProvider
          .overrideWith((ref) => AuthNotifier()..setSession(session))
    ]);
    addTearDown(container.dispose);
    container.read(malvaStoreProvider.notifier).replaceMedications([
      const Medication(
          id: id,
          name: 'Obat pasien',
          dosage: '5 mg',
          form: 'Tablet',
          reminders: [],
          currentStock: 10,
          alertBelow: 2,
          source: 'Pasien')
    ]);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
            home: MedicationScreen(apiClient: api, session: session))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Take Now'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Taken'));
    await tester.pumpAndSettle();
    expect(container.read(malvaStoreProvider).medicationLogs, hasLength(1));
    expect(container.read(malvaStoreProvider).medications.single.lastTakenAt,
        actual);
    expect(
        container.read(malvaStoreProvider).medications.single.currentStock, 9);
  });

  testWidgets(
      'taken history remains visible and repeat button stays locked after refresh',
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
        accessToken: 'a');
    const id = '00000000-0000-4000-8000-000000000001';
    var posts = 0;
    Map<String, dynamic>? log;
    final api = MalvaApiClient(
        baseUrl: 'https://test.invalid',
        httpClient: MockClient((request) async {
          if (request.method == 'POST') {
            posts++;
            log = jsonDecode(request.body) as Map<String, dynamic>;
            return http.Response(jsonEncode({'medication_log': log}), 201);
          }
          return http.Response(
              jsonEncode({
                'medications': [
                  {'id': id, 'name': 'Obat pasien', 'current_stock': 9}
                ],
                'medication_logs': [if (log != null) log],
              }),
              200);
        }));
    final container = ProviderContainer(overrides: [
      authStateProvider
          .overrideWith((ref) => AuthNotifier()..setSession(session))
    ]);
    addTearDown(container.dispose);
    container.read(malvaStoreProvider.notifier).replaceMedications([
      const Medication(
          id: id,
          name: 'Obat pasien',
          dosage: '5 mg',
          form: 'Tablet',
          reminders: [],
          currentStock: 10,
          alertBelow: 2,
          source: 'Pasien')
    ]);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
            home: MedicationScreen(apiClient: api, session: session))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Take Now'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Taken'));
    await tester.pumpAndSettle();
    expect(posts, 1);
    expect(find.text('Belum pernah diminum'), findsNothing);
    expect(
        container.read(malvaStoreProvider).medications.single.currentStock, 9);
    expect(find.text('Tunggu 24 jam'), findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Tunggu 24 jam'))
            .onPressed,
        isNull);
  });

  testWidgets('refresh discards medication data after an account round trip',
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
    await tester.pump();
    container.read(authStateProvider.notifier).setSession(session);
    await tester.pump();
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
