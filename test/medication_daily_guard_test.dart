import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:malva_mental_health/src/models.dart';
import 'package:malva_mental_health/src/providers/providers.dart';
import 'package:malva_mental_health/src/services/server_clock.dart';
import 'package:malva_mental_health/src/services/malva_api_client.dart';
import 'package:malva_mental_health/src/time/wib.dart';

const _med = Medication(
  id: '00000000-0000-4000-8000-000000000001',
  name: 'Obat pasien',
  dosage: '5 mg',
  form: 'Tablet',
  reminders: [],
  currentStock: 10,
  alertBelow: 2,
  source: 'Pasien',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  ProviderContainer container() {
    final result = ProviderContainer();
    addTearDown(result.dispose);
    return result;
  }

  test('last taken survives confirmed medication refresh and log hydration',
      () {
    final store = container().read(malvaStoreProvider.notifier);
    store.replaceMedications([_med]);
    store.takeMedication(_med.id);
    final takenAt = store.state.medications.single.lastTakenAt;
    store.confirmDose(_med.id);
    store.replaceMedications([_med.copyWith(currentStock: 9)]);
    expect(store.state.medications.single.lastTakenAt, takenAt);
    expect(store.state.medications.single.lastTakenLabel,
        isNot('Belum pernah diminum'));

    final reloaded = container().read(malvaStoreProvider.notifier);
    reloaded.replaceMedicationLogs(store.state.medicationLogs);
    reloaded.replaceMedications([_med.copyWith(currentStock: 9)]);
    expect(reloaded.state.medications.single.lastTakenAt, takenAt);
    expect(reloaded.state.medications.single.currentStock, 9);
  });

  test('rapid repeated doses across shared callers consume only once', () {
    final store = container().read(malvaStoreProvider.notifier);
    store.replaceMedications([_med]);
    for (var i = 0; i < 10; i++) {
      store.takeMedication(_med.id);
    }
    expect(store.state.medicationLogs, hasLength(1));
    expect(store.state.medications.single.currentStock, 9);
    expect(store.pendingDosesFor(_med.id), 1);
    store.confirmDose(_med.id);
    store.takeMedication(_med.id);
    expect(store.state.medicationLogs, hasLength(1));
    expect(store.state.medications.single.currentStock, 9);
  });

  for (final hoursAgo in [23, 25]) {
    test('server history ${hoursAgo}h ago enforces rolling 24 hour interval',
        () {
      final store = container().read(malvaStoreProvider.notifier);
      final at = ServerClock.now().subtract(Duration(hours: hoursAgo));
      store.replaceMedications([_med]);
      store.replaceMedicationLogs([
        MedicationLog(
            medicationId: _med.id,
            medicationName: _med.name,
            takenAt: at,
            status: 'taken'),
        MedicationLog(
            medicationId: _med.id,
            medicationName: _med.name,
            takenAt: ServerClock.now(),
            status: 'skipped'),
      ]);
      expect(store.state.medications.single.lastTakenAt, at);
      store.takeMedication(_med.id);
      expect(store.state.medicationLogs, hasLength(hoursAgo < 24 ? 2 : 3));
      expect(
          store.state.medications.single.currentStock, hoursAgo < 24 ? 10 : 9);
    });
  }

  test('skipped does not consume or prevent the first taken dose', () {
    final store = container().read(malvaStoreProvider.notifier);
    store.replaceMedications([_med]);
    store.takeMedication(_med.id, status: 'skipped');
    expect(store.state.medications.single.currentStock, 10);
    expect(store.state.medications.single.lastTakenAt, isNull);
    store.takeMedication(_med.id);
    expect(store.state.medicationLogs, hasLength(2));
    expect(store.state.medications.single.currentStock, 9);
  });

  test('restart restores cached cooldown without mixing another account',
      () async {
    const session = AuthSession(
        role: UserRole.patient,
        identifier: 'a',
        backendUserId: 'a',
        displayName: 'A',
        accessToken: '');
    final first = container().read(malvaStoreProvider.notifier);
    first.applySession(session);
    await pumpEventQueue();
    first.replaceMedications([_med]);
    first.takeMedication(_med.id);
    await pumpEventQueue();
    final restarted = container().read(malvaStoreProvider.notifier);
    restarted.applySession(session);
    await pumpEventQueue();
    restarted.replaceMedications([_med.copyWith(currentStock: 9)]);
    expect(restarted.takeMedication(_med.id), isFalse);
    expect(restarted.state.medicationLogs, hasLength(1));
    expect(restarted.state.medications.single.currentStock, 9);
    restarted.applySession(const AuthSession(
        role: UserRole.patient,
        identifier: 'b',
        backendUserId: 'b',
        displayName: 'B',
        accessToken: ''));
    await pumpEventQueue();
    restarted.replaceMedications([_med]);
    expect(restarted.takeMedication(_med.id), isTrue);
    expect(restarted.state.medications.single.currentStock, 9);
  });

  test('last taken also restores for medication beyond first 100 history rows',
      () async {
    final takenAt = ServerClock.now().subtract(const Duration(days: 30));
    final api = MalvaApiClient(
        baseUrl: 'https://test.invalid',
        httpClient: MockClient((request) async {
          final logs = [
            for (var i = 0; i < 100; i++)
              {
                'medication_id': 'other-$i',
                'medication_name': 'Other $i',
                'status': 'taken',
                'taken_at': wibIso(ServerClock.now())
              },
            {
              'medication_id': _med.id,
              'medication_name': _med.name,
              'status': 'taken',
              'taken_at': wibIso(takenAt)
            },
          ];
          final limit =
              int.tryParse(request.url.queryParameters['limit'] ?? '') ?? 20;
          return http.Response(
              jsonEncode({
                'medications': [
                  {'id': _med.id, 'name': _med.name, 'current_stock': 9}
                ],
                'medication_logs':
                    limit == 0 ? logs : logs.take(limit).toList(),
                'moods': [],
              }),
              200);
        }));
    final c = ProviderContainer(
        overrides: [apiClientProvider.overrideWithValue(api)]);
    addTearDown(c.dispose);
    final store = c.read(malvaStoreProvider.notifier);
    store.applySession(const AuthSession(
        role: UserRole.patient,
        identifier: 'a',
        backendUserId: 'a',
        displayName: 'A',
        accessToken: 't'));
    await pumpEventQueue();
    expect(store.state.medications.single.lastTakenAt?.millisecondsSinceEpoch,
        takenAt.millisecondsSinceEpoch);
  });
}
