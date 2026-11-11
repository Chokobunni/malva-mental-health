import 'dart:convert';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:malva_mental_health/src/models.dart';
import 'package:malva_mental_health/src/providers/providers.dart';
import 'package:malva_mental_health/src/services/malva_api_client.dart';
import 'package:malva_mental_health/src/services/server_clock.dart';
import 'package:malva_mental_health/src/theme.dart';
import 'package:malva_mental_health/src/services/offline_sync_service.dart';
import 'package:malva_mental_health/src/platform/contracts/ports.dart';
import 'package:malva_mental_health/src/time/wib.dart';
import 'package:malva_mental_health/src/widgets/daily_checkin_flow.dart';

const _session = AuthSession(
    role: UserRole.patient,
    identifier: 'patient',
    displayName: 'Emilie R',
    backendUserId: 'patient',
    accessToken: 'token');

class _FailStorage implements SecureStore {
  @override
  Future<String?> read(String key) async => null;
  @override
  Future<void> write(String key, String value) async =>
      throw StateError('disk full');
  @override
  Future<void> delete(String key) async {}
}

class _MemoryStorage implements SecureStore {
  final Map<String, String> values = {};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
  @override
  Future<void> delete(String key) async => values.remove(key);
}

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    ServerClock.reset();
  });
  tearDown(ServerClock.reset);

  Future<void> pumpFlow(WidgetTester tester, ProviderContainer c,
      {Key? key}) async {
    await tester.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
            theme: buildMalvaTheme(),
            home: Scaffold(
                body: SingleChildScrollView(
                    child: DailyCheckInFlow(key: key, onSaved: () {}))))));
    await tester.pumpAndSettle();
  }

  void expectCompleted() {
    expect(find.textContaining('Check-in hari ini selesai. Streak'),
        findsOneWidget);
    for (final mood in MoodValue.values) {
      expect(find.text(mood.label), findsNothing);
    }
    expect(find.text('Selesai Check-in'), findsNothing);
  }

  Future<ProviderContainer> mount(
      WidgetTester tester, List<Map<String, dynamic>> requests,
      {Future<void>? holdMood,
      List<Map<String, dynamic>> serverMoods = const [],
      List<Medication> meds = const [],
      SecureStore? queueStorage,
      int moodFailures = 0,
      int medicationFailures = 0}) async {
    tester.view.physicalSize = const Size(390, 950);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final api = MalvaApiClient(
        baseUrl: 'https://test.invalid',
        httpClient: MockClient((r) async {
          if (r.method == 'POST') {
            final body = jsonDecode(r.body) as Map<String, dynamic>;
            requests.add(body);
            if (r.url.path == '/v1/mood-checkins' && holdMood != null)
              await holdMood;
            if (r.url.path == '/v1/mood-checkins' && moodFailures-- > 0)
              return http.Response(jsonEncode({'error': 'offline'}), 503);
            if (r.url.path == '/v1/medication-logs' && medicationFailures-- > 0)
              return http.Response(jsonEncode({'error': 'offline'}), 503);
            if (r.url.path == '/v1/medication-logs')
              return http.Response(
                  jsonEncode({
                    'medication_log': {'id': 'log', ...body}
                  }),
                  200);
            return http.Response(
                jsonEncode({
                  'mood': {'id': 'm', ...body}
                }),
                200);
          }
          return http.Response(
              jsonEncode({
                'medications': [],
                'medication_logs': [],
                'moods': serverMoods
              }),
              200);
        }));
    final queue = queueStorage == null
        ? null
        : OfflineSyncService(
            apiClient: api,
            activeUserIdReader: () => 'patient',
            secureStore: queueStorage);
    if (queue != null) addTearDown(queue.dispose);
    final c = ProviderContainer(overrides: [
      apiClientProvider.overrideWithValue(api),
      if (queue != null) offlineSyncServiceProvider.overrideWithValue(queue)
    ]);
    addTearDown(c.dispose);
    c.read(authStateProvider.notifier).setSession(_session);
    for (final med in meds) {
      c.read(malvaStoreProvider.notifier).upsertMedication(med);
    }
    await pumpFlow(tester, c);
    return c;
  }

  Future<void> next(WidgetTester tester) async {
    await tester.ensureVisible(find.text('Lanjut'));
    await tester.tap(find.text('Lanjut'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }

  testWidgets(
      'five stages persist exact zero energy and chosen anxiety/irritability',
      (tester) async {
    final requests = <Map<String, dynamic>>[];
    final c = await mount(tester, requests);
    expect(find.text('Selamat datang, Emilie R!'), findsOneWidget);
    await tester.tap(find.text('Baik'));
    await tester.pumpAndSettle();
    expect(find.text('Langkah 2 dari 5'), findsOneWidget);
    await next(tester);
    expect(find.text('Berapa lama kamu tidur?'), findsOneWidget);
    await next(tester);
    expect(find.text('Bagaimana tingkat energimu?'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('energy-0')));
    await tester.pumpAndSettle();
    expect(find.text('Habis'), findsOneWidget);
    await next(tester);
    expect(find.text('Langkah 5 dari 5'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('anxiety-plus')));
    await tester.tap(find.byKey(const ValueKey('irritability-minus')));
    await tester.ensureVisible(find.text('Selesai Check-in'));
    await tester.tap(find.text('Selesai Check-in'));
    await tester.pumpAndSettle();
    expect(requests, hasLength(1));
    expect(requests.single, containsPair('energy', 0));
    expect(requests.single, containsPair('anxiety', 4));
    expect(requests.single, containsPair('irritability', 1));
    expect(requests.single, containsPair('sleep_hours', 7.5));
    expect(requests.single, containsPair('mood', 'good'));
    expectCompleted();
    await pumpFlow(tester, c, key: const ValueKey('reopened-home'));
    expectCompleted();
  });

  for (final sleepHours in [7.5, 0.0]) {
    testWidgets(
        'server-restored check-in ($sleepHours sleep) hides choices for its account and WIB day',
        (tester) async {
      final c = await mount(tester, [], serverMoods: [
        {
          'id': 'saved-mood',
          'mood': 'good',
          'sleep_hours': sleepHours,
          'energy': 5,
          'anxiety': 3,
          'irritability': 2,
          'note': 'Daily check-in',
          'occurred_at': wibIso(ServerClock.now()),
        }
      ]);
      c.read(malvaStoreProvider.notifier).applySession(_session);
      await tester.pumpAndSettle();
      expectCompleted();
      await pumpFlow(tester, c, key: const ValueKey('restored-home'));
      expectCompleted();
      c.read(malvaStoreProvider.notifier).resetForAccount();
      c.read(authStateProvider.notifier).setSession(const AuthSession(
          role: UserRole.patient,
          identifier: 'other',
          backendUserId: 'other',
          displayName: 'Dina',
          accessToken: 'other-token'));
      await tester.pumpAndSettle();
      expect(find.text('Selamat datang, Dina!'), findsOneWidget);
      expect(find.text('Bagaimana kabarmu hari ini?'), findsOneWidget);
      expect(find.text('Baik'), findsOneWidget);
    });
  }

  testWidgets('manual mood without sleep keeps the daily check-in available',
      (tester) async {
    final c = await mount(tester, []);
    c.read(malvaStoreProvider.notifier).addMood(MoodEntry(
        date: ServerClock.now(),
        mood: MoodValue.good,
        sleepHours: 0,
        energy: 0,
        anxiety: 0,
        irritability: 0,
        note: 'Catatan mood'));
    await tester.pumpAndSettle();
    expect(find.text('Baik'), findsOneWidget);
    expect(find.text('Bagaimana kabarmu hari ini?'), findsOneWidget);
  });

  testWidgets('completed local flow opens fresh choices on the next WIB day',
      (tester) async {
    final c = await mount(tester, []);
    await tester.tap(find.text('Baik'));
    await tester.pumpAndSettle();
    await next(tester);
    await next(tester);
    await next(tester);
    await tester.tap(find.text('Selesai Check-in'));
    await tester.pumpAndSettle();
    expectCompleted();
    FlutterSecureStorage.setMockInitialValues({
      ServerClock.offsetStorageKey: '86400000',
    });
    ServerClock.reset();
    await ServerClock.loadPersisted();
    // Home rebuilds on resume; keep the same widget state across that rebuild.
    await pumpFlow(tester, c);
    expect(find.text('Bagaimana kabarmu hari ini?'), findsOneWidget);
    expect(find.text('Baik'), findsOneWidget);
    await tester.tap(find.text('Baik'));
    await tester.pumpAndSettle();
    expect(find.text('Langkah 2 dari 5'), findsOneWidget);
  });

  testWidgets(
      'durable offline check-in stays completed after a fresh app mount',
      (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('dev.fluttercommunity.plus/connectivity'),
            (_) async => ['none']);
    final storage = _MemoryStorage();
    final first =
        await mount(tester, [], moodFailures: 1, queueStorage: storage);
    await tester.tap(find.text('Baik'));
    await tester.pumpAndSettle();
    await next(tester);
    for (final (key, count) in [
      ('sleep-hours-minus', 7),
      ('sleep-minutes-minus', 30)
    ]) {
      for (var i = 0; i < count; i++) {
        await tester.tap(find.byKey(ValueKey(key)));
        await tester.pump();
      }
    }
    await next(tester);
    await next(tester);
    await tester.tap(find.text('Selesai Check-in'));
    await tester.pumpAndSettle();
    expectCompleted();
    expect(first.read(malvaStoreProvider).moodEntries.single.sleepHours, 0);
    expect(first.read(offlineSyncServiceProvider).pendingCount, 1);

    // Fresh providers have no in-memory mood or completion flag.
    final restored = await mount(tester, [], queueStorage: storage);
    await pumpFlow(tester, restored, key: const ValueKey('offline-restored'));
    expect(find.text('Baik'), findsOneWidget);
    // Secure storage may finish loading after Home has already mounted.
    await restored.read(offlineSyncServiceProvider).initialize();
    await tester.pumpAndSettle();
    expect(restored.read(malvaStoreProvider).moodEntries, isEmpty);
    expectCompleted();
    expect(find.textContaining('Streak 1 hari!'), findsOneWidget);
    restored.read(authStateProvider.notifier).setSession(const AuthSession(
        role: UserRole.patient,
        identifier: 'other',
        backendUserId: 'other',
        displayName: 'Dina',
        accessToken: 'other-token'));
    await tester.pumpAndSettle();
    expect(find.text('Baik'), findsOneWidget);
    restored.read(authStateProvider.notifier).setSession(_session);
    await tester.pumpAndSettle();
    expectCompleted();
    FlutterSecureStorage.setMockInitialValues({
      ServerClock.offsetStorageKey: '86400000',
    });
    ServerClock.reset();
    await ServerClock.loadPersisted();
    await pumpFlow(tester, restored, key: const ValueKey('offline-restored'));
    expect(find.text('Baik'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    restored.read(offlineSyncServiceProvider).dispose();
  });

  testWidgets(
      'back retains selected energy and account change clears the draft',
      (tester) async {
    final c = await mount(tester, []);
    await tester.tap(find.text('Baik'));
    await tester.pumpAndSettle();
    await next(tester);
    await next(tester);
    await tester.tap(find.byKey(const ValueKey('energy-6')));
    await next(tester);
    await tester.tap(find.text('Kembali'));
    await tester.pumpAndSettle();
    expect(find.text('6 / 10'), findsOneWidget);
    expect(find.text('Tinggi'), findsOneWidget);
    c.read(authStateProvider.notifier).setSession(const AuthSession(
        role: UserRole.patient,
        identifier: 'other',
        displayName: 'Dina',
        backendUserId: 'other',
        accessToken: 'other-token'));
    await tester.pumpAndSettle();
    expect(find.text('Selamat datang, Dina!'), findsOneWidget);
    expect(find.text('Bagaimana tingkat energimu?'), findsNothing);
  });
  testWidgets(
      'daily medications sync once; skipped preserves stock; temporary ID cannot dose',
      (tester) async {
    final requests = <Map<String, dynamic>>[];
    final c = await mount(tester, requests, meds: [
      Medication(
          id: 'm1',
          name: 'A',
          dosage: '20mg',
          form: 'Tablet',
          currentStock: 30,
          alertBelow: 3,
          reminders: [],
          source: "patient",
          schedule: MedicationSchedule(
              times: [],
              weekdays: [1, 2, 3, 4, 5, 6, 7],
              startAt: wibNow(),
              unitsPerDose: 2)),
      const Medication(
          id: 'm2',
          name: 'B',
          dosage: '20mg',
          form: 'Tablet',
          currentStock: 30,
          alertBelow: 3,
          reminders: [],
          source: "professional"),
      const Medication(
          id: 'med_local',
          name: 'C',
          dosage: '20mg',
          form: 'Tablet',
          currentStock: 30,
          alertBelow: 3,
          reminders: [],
          source: "professional"),
    ]);
    await tester.tap(find.text('Baik'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('m1-taken')));
    await tester.tap(find.byKey(const ValueKey('m2-skipped')));
    await tester.tap(find.byKey(const ValueKey('med_local-taken')));
    await next(tester);
    await next(tester);
    await next(tester);
    await tester.tap(find.text('Selesai Check-in'));
    await tester.pumpAndSettle();
    expect(requests, hasLength(3));
    expect(requests[1], containsPair('medication_id', 'm1'));
    expect(requests[1], containsPair('status', 'taken'));
    expect(requests[2], containsPair('medication_id', 'm2'));
    expect(requests[2], containsPair('status', 'skipped'));
    expect(c.read(malvaStoreProvider).medications[0].currentStock, 28);
    expect(c.read(malvaStoreProvider).medications[1].currentStock, 30);
    expect(c.read(malvaStoreProvider.notifier).pendingDosesFor('m1'), 0);
  });

  testWidgets(
      'a response from a prior account generation cannot update a returned account',
      (tester) async {
    final held = Completer<void>();
    final c = await mount(tester, [], holdMood: held.future);
    await tester.tap(find.text('Baik'));
    await tester.pumpAndSettle();
    await next(tester);
    await next(tester);
    await next(tester);
    await tester.tap(find.text('Selesai Check-in'));
    await tester.pump();
    c.read(authStateProvider.notifier).setSession(const AuthSession(
        role: UserRole.patient,
        identifier: 'other',
        displayName: 'Other',
        backendUserId: 'other',
        accessToken: 'other'));
    await tester.pump();
    c.read(authStateProvider.notifier).setSession(_session);
    await tester.pump();
    held.complete();
    await tester.pumpAndSettle();
    expect(c.read(malvaStoreProvider).moodEntries, isEmpty);
    expect(find.text('Bagaimana kabarmu hari ini?'), findsOneWidget);
  });
  test('failed durable queue writes do not leave a duplicate pending item',
      () async {
    final queue = OfflineSyncService(
        apiClient: MalvaApiClient(baseUrl: 'https://test.invalid'),
        activeUserIdReader: () => 'patient',
        secureStore: _FailStorage());
    addTearDown(queue.dispose);
    await expectLater(
        queue.enqueueMedicationLog(
            medicationId: 'm', medicationName: 'A', status: 'taken'),
        throwsStateError);
    expect(queue.queue, isEmpty);
  });
  testWidgets(
      'medication and queue failure can retry without repeating mood or stock deduction',
      (tester) async {
    final requests = <Map<String, dynamic>>[];
    final c = await mount(tester, requests,
        queueStorage: _FailStorage(),
        medicationFailures: 1,
        meds: const [
          Medication(
              id: 'm',
              name: 'A',
              dosage: '20mg',
              form: 'Tablet',
              reminders: [],
              currentStock: 30,
              alertBelow: 3,
              source: 'patient')
        ]);
    await tester.tap(find.text('Baik'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('m-taken')));
    await next(tester);
    await next(tester);
    await next(tester);
    await tester.tap(find.text('Selesai Check-in'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.textContaining('Log obat belum tersimpan'), findsOneWidget);
    expect(find.text('Selesai Check-in'), findsOneWidget);
    expect(c.read(malvaStoreProvider).medications.single.currentStock, 29);
    await tester.tap(find.text('Selesai Check-in'));
    await tester.pumpAndSettle();
    expect(requests.where((r) => r.containsKey('mood')), hasLength(1));
    expect(requests.where((r) => r.containsKey('medication_id')), hasLength(2));
    expect(c.read(malvaStoreProvider).medications.single.currentStock, 29);
    expect(c.read(malvaStoreProvider.notifier).pendingDosesFor('m'), 0);
    expect(find.textContaining('Log obat belum tersimpan'), findsNothing);
    expectCompleted();
  });
  testWidgets(
      'offline dose stays queued then clears pending exactly once after sync',
      (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('dev.fluttercommunity.plus/connectivity'),
            (_) async => ['none']);
    final c = await mount(tester, [],
        medicationFailures: 1,
        meds: const [
          Medication(
              id: 'm',
              name: 'A',
              dosage: '20mg',
              form: 'Tablet',
              reminders: [],
              currentStock: 30,
              alertBelow: 3,
              source: 'Pasien')
        ]);
    await tester.tap(find.text('Baik'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('m-taken')));
    await next(tester);
    await next(tester);
    await next(tester);
    await tester.tap(find.text('Selesai Check-in'));
    await tester.pumpAndSettle();
    final queue = c.read(offlineSyncServiceProvider);
    expect(queue.pendingCount, 1);
    expectCompleted();
    expect(c.read(malvaStoreProvider.notifier).pendingDosesFor('m'), 1);
    await tester.runAsync(() => queue.syncNow());
    await tester.pumpAndSettle();
    expect(c.read(malvaStoreProvider.notifier).pendingDosesFor('m'), 0);
    expect(c.read(malvaStoreProvider).medications.single.currentStock, 29);
    await tester.runAsync(() => queue.syncNow());
    expect(c.read(malvaStoreProvider).medications.single.currentStock, 29);
  });
}
