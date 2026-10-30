import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:malva_mental_health/src/models.dart';
import 'package:malva_mental_health/src/providers/providers.dart';
import 'package:malva_mental_health/src/services/malva_api_client.dart';

// ============================================================
// PERSISTENSI LOG MINUM OBAT (adherence & riwayat tidak reset)
//
// Bug: setelah logout/login, adherence kembali 0% dan riwayat kosong
// karena `medicationLogs` hanya hidup di memori. Perbaikan:
//   - `loadMedicationLogs` memuat log dari server saat login.
//   - `replaceMedicationLogs` menggabungkan (bukan menimpa) & menjaga
//     log lokal yang lebih baru.
//   - cache lokal per akun (secure storage) menghidrasi log saat login
//     walau offline.
// ============================================================

const _session = AuthSession(
  role: UserRole.patient,
  identifier: 'pasien@malva.app',
  displayName: 'Pasien',
  backendUserId: 'user1',
  accessToken: 'token_test',
);

/// Sesi offline (token kosong): hanya cache lokal yang bisa dipakai.
const _offlineSession = AuthSession(
  role: UserRole.patient,
  identifier: 'pasien@malva.app',
  displayName: 'Pasien',
  backendUserId: 'user1',
  accessToken: '',
);

Map<String, dynamic> _medJson(String id, int stock) => {
      'id': id,
      'name': 'Sertraline',
      'dosage': '50mg',
      'current_stock': stock,
      'alert_below': 1,
      'form': 'Tablet',
      'reminder_time': '08:00',
      'source': 'resep',
    };

Map<String, dynamic> _logJson(
  String id,
  String name,
  DateTime takenAt,
  String status,
) =>
    {
      'id': 'log_$id',
      'patient_id': 'user1',
      'medication_id': id,
      'medication_name': name,
      'status': status,
      'taken_at': takenAt.toIso8601String(),
      'created_at': takenAt.toIso8601String(),
    };

MalvaApiClient _api({
  List<Map<String, dynamic>> medications = const [],
  List<Map<String, dynamic>> logs = const [],
}) {
  return MalvaApiClient(
    baseUrl: 'http://backend.test',
    httpClient: _FakeClient((request) async {
      switch (request.url.path) {
        case '/v1/medications':
          return _json({'medications': medications});
        case '/v1/medication-logs':
          return _json({'medication_logs': logs});
        default:
          return _json(<String, dynamic>{});
      }
    }),
  );
}

http.Response _json(Object body) => http.Response(
      jsonEncode(body),
      200,
      headers: {'content-type': 'application/json'},
    );

ProviderContainer _container(MalvaApiClient api) {
  final container = ProviderContainer(
    overrides: [apiClientProvider.overrideWithValue(api)],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // Secure storage palsu (in-memory) agar cache lokal bisa diuji.
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
  });

  test('adherence & riwayat pulih dari SERVER setelah login ulang', () async {
    final today = DateTime.now();

    // Sesi 1: server belum punya log; obat stok 3. Pasien minum → stok 2.
    final api1 = _api(medications: [_medJson('med_1', 3)], logs: const []);
    final store1 = _container(api1).read(malvaStoreProvider.notifier);
    store1.applySession(_session);
    await pumpEventQueue(); // tunggu pemuatan server sesi 1
    store1.takeMedication('med_1', status: 'taken');
    await pumpEventQueue();

    expect(store1.state.adherencePercent, 100);
    expect(store1.state.medicationLogs, hasLength(1));
    expect(store1.state.medications.first.currentStock, 2);

    // Kosongkan cache agar sesi 2 murni menguji pemuatan dari SERVER.
    FlutterSecureStorage.setMockInitialValues(<String, String>{});

    // Sesi 2 (setara logout/login): server sudah punya 1 log 'taken' hari ini.
    final api2 = _api(
      medications: [_medJson('med_1', 2)],
      logs: [_logJson('med_1', 'Sertraline', today, 'taken')],
    );
    final store2 = _container(api2).read(malvaStoreProvider.notifier);
    store2.applySession(_session);
    await store2.loadMedications(api2, _session.accessToken);
    await store2.loadMedicationLogs(api2, _session.accessToken);
    await pumpEventQueue();

    expect(store2.state.adherencePercent, 100);
    expect(store2.state.medicationLogs, hasLength(1));
    expect(store2.state.medicationLogs.first.status, 'taken');
    // Stok persisten dari server (tidak berubah jadi 3).
    expect(store2.state.medications.first.currentStock, 2);
  });

  test('log lokal yang lebih baru tidak terhapus saat merge data server lama',
      () async {
    final api = _api();
    final store = _container(api).read(malvaStoreProvider.notifier);
    store.applySession(_session);
    await pumpEventQueue();

    final now = DateTime.now();
    final localNewer = MedicationLog(
      medicationId: 'med_1',
      medicationName: 'Sertraline',
      takenAt: now,
      status: 'taken',
    );
    store.replaceMedicationLogs([localNewer]);
    expect(store.state.medicationLogs, hasLength(1));

    // Server mengembalikan log yang LEBIH LAMA.
    final serverOlder = MedicationLog(
      medicationId: 'med_0',
      medicationName: 'Obat Lama',
      takenAt: now.subtract(const Duration(days: 1)),
      status: 'taken',
    );
    store.replaceMedicationLogs([serverOlder]);

    // Log lokal yang lebih baru tetap ada, log server lama ikut masuk.
    expect(
      store.state.medicationLogs.any((l) => l.medicationId == 'med_1'),
      isTrue,
    );
    expect(
      store.state.medicationLogs.any((l) => l.medicationId == 'med_0'),
      isTrue,
    );
    // Urut takenAt DESC → log terbaru (lokal) di depan.
    expect(store.state.medicationLogs.first.medicationId, 'med_1');
  });

  test('cache lokal: log tetap tampil tanpa server setelah takeMedication',
      () async {
    // Sesi 1: minum obat → cache lokal tertulis.
    final api = _api(medications: [_medJson('med_1', 3)], logs: const []);
    final store1 = _container(api).read(malvaStoreProvider.notifier);
    store1.applySession(_session);
    await pumpEventQueue();
    store1.takeMedication('med_1', status: 'taken');
    await pumpEventQueue(); // pastikan cache ter-flush
    expect(store1.state.medicationLogs, hasLength(1));

    // Sesi 2 OFFLINE (token kosong): hanya cache yang menghidrasi log.
    final store2 = _container(api).read(malvaStoreProvider.notifier);
    store2.applySession(_offlineSession);
    await pumpEventQueue();

    expect(store2.state.medicationLogs, hasLength(1));
    expect(store2.state.medicationLogs.first.medicationId, 'med_1');
    expect(store2.state.medicationLogs.first.status, 'taken');
  });

  // ----------------------------------------------------------------------
  // MERGE DOSIS BERBASIS JENDELA TOLERANSI WAKTU (bukan timestamp eksak)
  // ----------------------------------------------------------------------

  MedicationLog dose({
    String id = 'med_1',
    String name = 'Sertraline',
    required DateTime at,
    String status = 'taken',
  }) =>
      MedicationLog(
        medicationId: id,
        medicationName: name,
        takenAt: at,
        status: status,
      );

  test('server di belakang 2 detik untuk dosis yang sama → 1 entri', () async {
    final api = _api();
    final store = _container(api).read(malvaStoreProvider.notifier);
    store.applySession(_session);
    await pumpEventQueue();

    final t = DateTime.now();
    store.replaceMedicationLogs([dose(at: t)]);
    store.replaceMedicationLogs([dose(at: t.subtract(const Duration(seconds: 2)))]);

    expect(store.state.medicationLogs, hasLength(1),
        reason: 'selisih jam server 2 detik di belakang bukan dosis baru');
  });

  test('server di depan 2 detik untuk dosis yang sama → 1 entri', () async {
    final api = _api();
    final store = _container(api).read(malvaStoreProvider.notifier);
    store.applySession(_session);
    await pumpEventQueue();

    final t = DateTime.now();
    store.replaceMedicationLogs([dose(at: t)]);
    store.replaceMedicationLogs([dose(at: t.add(const Duration(seconds: 2)))]);

    expect(store.state.medicationLogs, hasLength(1),
        reason: 'selisih jam server 2 detik di depan bukan dosis baru');
  });

  test('log offline lebih lama dari log server terbaru TIDAK hilang → 2 entri',
      () async {
    final api = _api();
    final store = _container(api).read(malvaStoreProvider.notifier);
    store.applySession(_session);
    await pumpEventQueue();

    final today = DateTime.now();
    final morning = DateTime(today.year, today.month, today.day, 8, 0);
    final evening = DateTime(today.year, today.month, today.day, 20, 0);

    // Dosis pagi tercatat lokal (offline, gagal sync).
    store.replaceMedicationLogs([dose(at: morning)]);
    // Server baru punya dosis malam (lebih baru).
    store.replaceMedicationLogs([dose(at: evening)]);

    expect(store.state.medicationLogs, hasLength(2),
        reason: 'log pagi (lebih lama, belum sync) tidak boleh dibuang');
    expect(
      store.state.medicationLogs.any((l) => l.takenAt == morning),
      isTrue,
    );
    expect(
      store.state.medicationLogs.any((l) => l.takenAt == evening),
      isTrue,
    );
  });

  test('dua dosis berbeda 4 jam untuk obat sama → 2 entri (jendela tidak menelan dosis nyata)',
      () async {
    final api = _api();
    final store = _container(api).read(malvaStoreProvider.notifier);
    store.applySession(_session);
    await pumpEventQueue();

    final t = DateTime.now();
    store.replaceMedicationLogs([dose(at: t)]);
    store.replaceMedicationLogs([dose(at: t.subtract(const Duration(hours: 4)))]);

    expect(store.state.medicationLogs, hasLength(2),
        reason: 'dosis 4 jam berbeda bukan dosis yang sama');
  });

  test('id sementara (med_...) lokal vs id UUID server, dosis sama → 1 entri (cocok via nama)',
      () async {
    final api = _api();
    final store = _container(api).read(malvaStoreProvider.notifier);
    store.applySession(_session);
    await pumpEventQueue();

    final t = DateTime.now();
    // Log lokal memakai id sementara sebelum sync.
    store.replaceMedicationLogs([
      dose(id: 'med_1730000000000', at: t),
    ]);
    // Server mengembalikan dosis yang sama dengan id UUID asli, waktu berdekatan.
    store.replaceMedicationLogs([
      dose(id: 'a1111111-2222-3333-4444-555555555555',
          at: t.subtract(const Duration(seconds: 1))),
    ]);

    expect(store.state.medicationLogs, hasLength(1),
        reason: 'id sementara vs UUID untuk dosis sama harus digabung via nama');
  });

  test('dua id server BERBEDA, nama obat sama, waktu berdekatan → 2 entri',
      () async {
    final api = _api();
    final store = _container(api).read(malvaStoreProvider.notifier);
    store.applySession(_session);
    await pumpEventQueue();

    final t = DateTime.now();
    // Dua resep berbeda dengan nama sama (mis. "Lamictal 20mg" vs 50mg),
    // masing-masing punya id server (UUID) sendiri.
    store.replaceMedicationLogs([
      dose(
        id: '11111111-1111-1111-1111-111111111111',
        name: 'Lamictal',
        at: t,
      ),
    ]);
    store.replaceMedicationLogs([
      dose(
        id: '22222222-2222-2222-2222-222222222222',
        name: 'Lamictal',
        at: t.add(const Duration(seconds: 10)),
      ),
    ]);

    expect(store.state.medicationLogs, hasLength(2),
        reason: 'dua id server berbeda = dua dosis berbeda walau namanya sama; '
            'salah satunya tidak boleh hilang');
  });
}

/// Klien HTTP palsu (pola repo, lihat `malva_api_client_test.dart`).
class _FakeClient extends http.BaseClient {
  _FakeClient(this.handler);

  final FutureOr<http.Response> Function(http.Request request) handler;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final body = request is http.Request ? request.body : '';
    final replay = http.Request(request.method, request.url)
      ..headers.addAll(request.headers)
      ..body = body;
    final response = await handler(replay);
    return http.StreamedResponse(
      Stream.value(response.bodyBytes),
      response.statusCode,
      headers: response.headers,
      reasonPhrase: response.reasonPhrase,
      request: replay,
    );
  }
}
