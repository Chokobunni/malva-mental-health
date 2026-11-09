import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:malva_mental_health/src/models.dart';
import 'package:malva_mental_health/src/providers/malva_store_provider.dart';
import 'package:malva_mental_health/src/services/malva_api_client.dart';

http.Response meds(String name) => http.Response(
    jsonEncode({
      'medications': [
        {
          'id': 'm1',
          'name': name,
          'dosage': '10mg',
          'form': 'tablet',
          'reminder_time': '08:00',
          'relation_to_meal': 'setelah makan',
        }
      ]
    }),
    200);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'clinical refresh wins over older hydration and retains meal instruction',
      () async {
    FlutterSecureStorage.setMockInitialValues({});
    final store = MalvaStoreNotifier(null, null);
    addTearDown(store.dispose);
    store.applySession(const AuthSession(
        role: UserRole.patient,
        identifier: 'p1',
        backendUserId: 'p1',
        displayName: 'Pasien',
        accessToken: 't1'));
    final old = Completer<http.Response>();
    var calls = 0;
    final api = MalvaApiClient(
        baseUrl: 'https://backend.test',
        httpClient: MockClient((r) async {
          calls++;
          return calls == 1 ? old.future : meds('Resep terbaru');
        }));
    final hydration = store.loadMedications(api, 't1');
    await store.loadMedications(api, 't1');
    expect(store.state.medications.single.name, 'Resep terbaru');
    old.complete(meds('Data sebelum diedit'));
    await hydration;
    expect(store.state.medications.single.name, 'Resep terbaru');
    expect(store.state.medications.single.reminders.single.relationToMeal,
        'setelah makan');
    await Future<void>.delayed(Duration.zero);
  });
  test(
      'professional routine survives hydration and pending stock refresh consumes configured units',
      () async {
    FlutterSecureStorage.setMockInitialValues({});
    final store = MalvaStoreNotifier(null, null);
    addTearDown(store.dispose);
    store.applySession(const AuthSession(
        role: UserRole.patient,
        identifier: 'p1',
        backendUserId: 'p1',
        displayName: 'Pasien',
        accessToken: 't1'));
    var stock = 5;
    final api = MalvaApiClient(
        baseUrl: 'https://backend.test',
        httpClient: MockClient((r) async => http.Response(
            jsonEncode({
              'medications': [
                {
                  'id': 'm1',
                  'name': 'Aripiprazole',
                  'dosage': '10 mg',
                  'form': 'Tablet',
                  'current_stock': stock,
                  'alert_below': 3,
                  'source': 'prescription',
                  'schedule': {
                    'times': ['08:00', '20:00'],
                    'weekdays': [1, 2, 3, 4, 5, 6, 7],
                    'start_at': '2026-11-10T08:00:00+07:00',
                    'units_per_dose': 2,
                    'refill_enabled': true
                  }
                }
              ]
            }),
            200)));
    await store.loadMedications(api, 't1');
    expect(store.state.medications.single.reminders.map((r) => r.label),
        ['08:00', '20:00']);
    store.takeMedication('m1');
    expect(store.state.medications.single.currentStock, 3);
    expect(store.state.medications.single.needsRefill, isTrue);
    await store.loadMedications(api, 't1');
    expect(store.state.medications.single.currentStock, 3);
    store.confirmDose('m1');
    stock = 3;
    await store.loadMedications(api, 't1');
    expect(store.state.medications.single.currentStock, 3);
    await Future<void>.delayed(Duration.zero);
  });
}
