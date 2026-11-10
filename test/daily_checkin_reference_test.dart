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

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  Future<ProviderContainer> mount(
      WidgetTester tester, List<Map<String, dynamic>> requests,
      {Future<void>? holdMood,
      List<Medication> meds = const [],
      SecureStore? queueStorage,
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
              jsonEncode(
                  {'medications': [], 'medication_logs': [], 'moods': []}),
              200);
        }));
    final c = ProviderContainer(overrides: [
      apiClientProvider.overrideWithValue(api),
      if (queueStorage != null)
        offlineSyncServiceProvider.overrideWithValue(OfflineSyncService(
            apiClient: api,
            activeUserIdReader: () => 'patient',
            secureStore: queueStorage))
    ]);
    addTearDown(c.dispose);
    c.read(authStateProvider.notifier).setSession(_session);
    for (final med in meds) {
      c.read(malvaStoreProvider.notifier).upsertMedication(med);
    }
    await tester.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
            theme: buildMalvaTheme(),
            home: Scaffold(
                body: SingleChildScrollView(
                    child: DailyCheckInFlow(onSaved: () {}))))));
    await tester.pumpAndSettle();
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
    await mount(tester, requests);
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
    expect(c.read(malvaStoreProvider).medications.single.currentStock, 29);
    await tester.tap(find.text('Selesai Check-in'));
    await tester.pumpAndSettle();
    expect(requests.where((r) => r.containsKey('mood')), hasLength(1));
    expect(requests.where((r) => r.containsKey('medication_id')), hasLength(2));
    expect(c.read(malvaStoreProvider).medications.single.currentStock, 29);
    expect(c.read(malvaStoreProvider.notifier).pendingDosesFor('m'), 0);
    expect(find.textContaining('Log obat belum tersimpan'), findsNothing);
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
    expect(c.read(malvaStoreProvider.notifier).pendingDosesFor('m'), 1);
    await tester.runAsync(() => queue.syncNow());
    await tester.pumpAndSettle();
    expect(c.read(malvaStoreProvider.notifier).pendingDosesFor('m'), 0);
    expect(c.read(malvaStoreProvider).medications.single.currentStock, 29);
    await tester.runAsync(() => queue.syncNow());
    expect(c.read(malvaStoreProvider).medications.single.currentStock, 29);
  });
}
