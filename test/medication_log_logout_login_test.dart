import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:malva_mental_health/src/models.dart';
import 'package:malva_mental_health/src/providers/providers.dart';
import 'package:malva_mental_health/src/services/malva_api_client.dart';
import 'package:malva_mental_health/src/time/wib.dart';

// ============================================================
// QA — T6: PERSISTENSI LOG MINUM OBAT (adherence & riwayat tidak reset)
//
// Verifikasi independen atas perbaikan:
//   - `loadMedicationLogs` memuat log dari server saat login.
//   - `replaceMedicationLogs` menggabungkan (bukan menimpa) & menjaga log
//     lokal yang lebih baru, tanpa menggandakan dosis yang sama.
//   - cache lokal per akun (secure storage) menghidrasi log saat login.
//   - aturan adherence tidak berubah (hanya 'taken' hari ini).
//   - tidak ada kebocoran async / unhandled exception.
//   - regresi stok "2 tidak naik jadi 3" tetap benar.
// ============================================================

const _session = AuthSession(
  role: UserRole.patient,
  identifier: 'pasien@malva.app',
  displayName: 'Pasien',
  backendUserId: 'user1',
  accessToken: 'token_test',
);

/// Sesi akun lain untuk uji isolasi cache.
const _sessionB = AuthSession(
  role: UserRole.patient,
  identifier: 'b@malva.app',
  displayName: 'Pasien B',
  backendUserId: 'userB',
  accessToken: 'token_b',
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
      'taken_at': wibIso(takenAt),
      'created_at': wibIso(takenAt),
    };

/// Klien API dengan respons per-path; `statusCode` 500 mensimulasikan error.
MalvaApiClient _api({
  List<Map<String, dynamic>> medications = const [],
  List<Map<String, dynamic>> logs = const [],
  int medicationsStatus = 200,
  int logsStatus = 200,
}) {
  return MalvaApiClient(
    baseUrl: 'http://backend.test',
    httpClient: _FakeClient((request) async {
      switch (request.url.path) {
        case '/v1/medications':
          return _json({'medications': medications}, medicationsStatus);
        case '/v1/medication-logs':
          return _json({'medication_logs': logs}, logsStatus);
        default:
          return _json(<String, dynamic>{}, 200);
      }
    }),
  );
}

http.Response _json(Object body, int status) => http.Response(
      jsonEncode(body),
      status,
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
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
  });

  // ----------------------------------------------------------------------
  // #1 — SKENARIO PERSIS LAPORAN USER
  // ----------------------------------------------------------------------
  test(
      'laporan user: adherence & riwayat pulih dari SERVER setelah login ulang, stok tetap',
      () async {
    // Sesi 1: obat stok 3, server belum punya log. Pasien minum → stok 2.
    final api1 = _api(medications: [_medJson('med_1', 3)], logs: const []);
    final store1 = _container(api1).read(malvaStoreProvider.notifier);
    store1.applySession(_session);
    await pumpEventQueue();
    store1.takeMedication('med_1', status: 'taken');
    await pumpEventQueue();

    expect(store1.state.adherencePercent, 100, reason: 'adherence sesi 1');
    expect(store1.state.medicationLogs, hasLength(1), reason: 'riwayat sesi 1');
    expect(store1.state.medications.first.currentStock, 2,
        reason: 'stok sesi 1');

    // Kosongkan cache agar sesi 2 murni menguji pemuatan dari SERVER.
    FlutterSecureStorage.setMockInitialValues(<String, String>{});

    // Sesi 2 (setara logout/login): server punya 1 log 'taken' hari ini.
    final today = DateTime.now();
    final api2 = _api(
      medications: [_medJson('med_1', 2)],
      logs: [_logJson('med_1', 'Sertraline', today, 'taken')],
    );
    final store2 = _container(api2).read(malvaStoreProvider.notifier);
    store2.applySession(_session);
    await store2.loadMedications(api2, _session.accessToken);
    await store2.loadMedicationLogs(api2, _session.accessToken);
    await pumpEventQueue();

    expect(store2.state.adherencePercent, 100, reason: 'adherence pulih');
    expect(store2.state.medicationLogs, hasLength(1), reason: 'riwayat pulih');
    expect(store2.state.medicationLogs.first.status, 'taken');
    expect(store2.state.medications.first.currentStock, 2,
        reason: 'stok tidak berubah jadi 3');
  });

  // ----------------------------------------------------------------------
  // #2 — ANTI-DUPLIKAT: waktu SAMA persis → tetap 1 entri
  // ----------------------------------------------------------------------
  test('anti-duplikat: log server dengan waktu SAMA tidak menggandakan dosis',
      () async {
    final api = _api();
    final store = _container(api).read(malvaStoreProvider.notifier);
    store.applySession(_session);
    await pumpEventQueue();

    final t = DateTime.now();
    final local = MedicationLog(
      medicationId: 'med_1',
      medicationName: 'Sertraline',
      takenAt: t,
      status: 'taken',
    );
    store.replaceMedicationLogs([local]);
    expect(store.state.medicationLogs, hasLength(1));

    // Server mengembalikan log untuk dosis yang SAMA pada waktu yang SAMA.
    final serverSame = MedicationLog(
      medicationId: 'med_1',
      medicationName: 'Sertraline',
      takenAt: t,
      status: 'taken',
    );
    store.replaceMedicationLogs([serverSame]);

    expect(store.state.medicationLogs, hasLength(1),
        reason: 'waktu sama harus dedupe jadi 1 entri');
  });

  // ----------------------------------------------------------------------
  // #2b — ANTI-DUPLIKAT: jam server SEDIKIT DI BELAKANG jam perangkat
  //       (log lokal lebih baru dari log server untuk dosis yang sama)
  // ----------------------------------------------------------------------
  test(
      'anti-duplikat: jam server sedikit di belakang perangkat tidak menggandakan dosis yang sama',
      () async {
    final api = _api();
    final store = _container(api).read(malvaStoreProvider.notifier);
    store.applySession(_session);
    await pumpEventQueue();

    final t = DateTime.now();
    final local = MedicationLog(
      medicationId: 'med_1',
      medicationName: 'Sertraline',
      takenAt: t,
      status: 'taken',
    );
    store.replaceMedicationLogs([local]);

    // Server menyimpan waktu 2 detik LEBIH AWAL untuk dosis yang sama.
    final serverBehind = MedicationLog(
      medicationId: 'med_1',
      medicationName: 'Sertraline',
      takenAt: t.subtract(const Duration(seconds: 2)),
      status: 'taken',
    );
    store.replaceMedicationLogs([serverBehind]);

    expect(store.state.medicationLogs, hasLength(1),
        reason: 'dosis yang sama tidak boleh jadi 2 entri hanya karena '
            'selisih jam server vs perangkat');
  });

  // ----------------------------------------------------------------------
  // #2d — ANTI-DUPLIKAT (end-to-end jujur): takeMedication lalu
  //        loadMedicationLogs mengembalikan log server dengan jam di belakang.
  //        Ini alur PERSIS yang dijelaskan requirement.
  // ----------------------------------------------------------------------
  test(
      'anti-duplikat (end-to-end): takeMedication lalu loadMedicationLogs dengan jam server di belakang tidak dobel',
      () async {
    // Sesi login: server belum punya log (agar auto-load tidak menambah entri).
    final apiEmpty = _api(medications: [_medJson('med_1', 3)], logs: const []);
    final store = _container(apiEmpty).read(malvaStoreProvider.notifier);
    store.applySession(_session);
    await store.loadMedications(apiEmpty, _session.accessToken);
    await pumpEventQueue();

    // Entri optimistis lewat jalur produksi.
    store.takeMedication('med_1', status: 'taken');
    expect(store.state.medicationLogs, hasLength(1));

    // Server mengembalikan log dosis yang sama dengan waktu 2 detik LEBIH AWAL.
    final behind = DateTime.now().subtract(const Duration(seconds: 2));
    final apiServer = _api(
      medications: [_medJson('med_1', 2)],
      logs: [_logJson('med_1', 'Sertraline', behind, 'taken')],
    );
    await store.loadMedicationLogs(apiServer, _session.accessToken);

    expect(store.state.medicationLogs, hasLength(1),
        reason:
            'satu dosis tidak boleh jadi 2 entri setelah reload dari server '
            'yang jamnya sedikit di belakang perangkat');
  });

  // ----------------------------------------------------------------------
  // #2c — ANTI-DUPLIKAT: jam server sedikit DI DEPAN perangkat (kontrol)
  //        Membuktikan mekanisme dedupe memang jalan saat server >= lokal.
  // ----------------------------------------------------------------------
  test(
      'anti-duplikat (kontrol): jam server sedikit di DEPAN perangkat dedupe jadi 1',
      () async {
    final api = _api();
    final store = _container(api).read(malvaStoreProvider.notifier);
    store.applySession(_session);
    await pumpEventQueue();

    final t = DateTime.now();
    store.replaceMedicationLogs([
      MedicationLog(
        medicationId: 'med_1',
        medicationName: 'Sertraline',
        takenAt: t,
        status: 'taken',
      ),
    ]);

    // Server menyimpan waktu 2 detik LEBIH AKHIR untuk dosis yang sama.
    store.replaceMedicationLogs([
      MedicationLog(
        medicationId: 'med_1',
        medicationName: 'Sertraline',
        takenAt: t.add(const Duration(seconds: 2)),
        status: 'taken',
      ),
    ]);

    expect(store.state.medicationLogs, hasLength(1),
        reason: 'server lebih baru → log lokal lama dibuang, jadi 1 entri');
  });

  // ----------------------------------------------------------------------
  // #3 — ANTI-KEHILANGAN: log lokal lebih baru dari log server tidak hilang
  // ----------------------------------------------------------------------
  test('anti-kehilangan: log lokal lebih baru dari log server tidak terhapus',
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

    // Server mengembalikan log yang LEBIH LAMA (mis. dosis obat lain kemarin).
    final serverOlder = MedicationLog(
      medicationId: 'med_0',
      medicationName: 'Obat Lama',
      takenAt: now.subtract(const Duration(days: 1)),
      status: 'taken',
    );
    store.replaceMedicationLogs([serverOlder]);

    expect(store.state.medicationLogs.any((l) => l.medicationId == 'med_1'),
        isTrue,
        reason: 'log lokal baru tidak boleh hilang');
    expect(store.state.medicationLogs.any((l) => l.medicationId == 'med_0'),
        isTrue,
        reason: 'log server lama tetap masuk');
    // Urut terbaru dulu.
    expect(store.state.medicationLogs.first.medicationId, 'med_1');
  });

  // ----------------------------------------------------------------------
  // #4 — CACHE LOKAL: riwayat tetap tampil saat offline setelah takeMedication
  // ----------------------------------------------------------------------
  test(
      'cache lokal: log tetap tampil tanpa server (token kosong) setelah takeMedication',
      () async {
    final api = _api(medications: [_medJson('med_1', 3)], logs: const []);
    final store1 = _container(api).read(malvaStoreProvider.notifier);
    store1.applySession(_session);
    await pumpEventQueue();
    store1.takeMedication('med_1', status: 'taken');
    await pumpEventQueue(); // biarkan cache ter-flush
    expect(store1.state.medicationLogs, hasLength(1));

    // Sesi 2 OFFLINE: hanya cache yang menghidrasi log.
    final store2 = _container(api).read(malvaStoreProvider.notifier);
    store2.applySession(_offlineSession);
    await pumpEventQueue();

    expect(store2.state.medicationLogs, hasLength(1),
        reason: 'cache lokal harus menghidrasi riwayat saat offline');
    expect(store2.state.medicationLogs.first.medicationId, 'med_1');
    expect(store2.state.medicationLogs.first.status, 'taken');
  });

  // ----------------------------------------------------------------------
  // #4b — CACHE LOKAL: tidak bocor walau server error 500
  // ----------------------------------------------------------------------
  test('cache lokal: riwayat tetap ada walau server error 500 saat login',
      () async {
    final api = _api(medications: [_medJson('med_1', 3)], logs: const []);
    final store1 = _container(api).read(malvaStoreProvider.notifier);
    store1.applySession(_session);
    await pumpEventQueue();
    store1.takeMedication('med_1', status: 'taken');
    await pumpEventQueue();

    // Server error total pada sesi berikutnya.
    final brokenApi = _api(medicationsStatus: 500, logsStatus: 500);
    final store2 = _container(brokenApi).read(malvaStoreProvider.notifier);
    store2.applySession(_session);
    await pumpEventQueue();

    expect(store2.state.medicationLogs, hasLength(1),
        reason: 'cache harus dipakai saat server error');
  });

  // ----------------------------------------------------------------------
  // #5 — ISOLASI AKUN: cache akun A tidak muncul untuk akun B
  // ----------------------------------------------------------------------
  test('isolasi akun: cache akun A tidak muncul untuk akun B', () async {
    final api = _api(medications: [_medJson('med_1', 3)], logs: const []);
    // Akun A minum obat → cache di bawah 'user1'.
    final storeA = _container(api).read(malvaStoreProvider.notifier);
    storeA.applySession(_session);
    await pumpEventQueue();
    storeA.takeMedication('med_1', status: 'taken');
    await pumpEventQueue();
    expect(storeA.state.medicationLogs, hasLength(1));

    // Akun B login offline: TIDAK boleh melihat log akun A.
    final storeB = _container(api).read(malvaStoreProvider.notifier);
    storeB.applySession(_sessionB);
    await pumpEventQueue();

    expect(storeB.state.medicationLogs, isEmpty,
        reason: 'log akun A tidak boleh bocor ke akun B');
  });

  // ----------------------------------------------------------------------
  // #6 — ATURAN ADHERENCE TIDAK BERUBAH: hanya 'taken' hari ini
  // ----------------------------------------------------------------------
  test('aturan adherence: hanya status taken hari ini yang dihitung', () {
    const med = Medication(
      id: 'm',
      name: 'Sertraline',
      dosage: '50mg',
      form: 'Tablet',
      reminders: const [],
      currentStock: 10,
      alertBelow: 1,
      source: 'resep',
    );
    const patient = PatientProfile(
      id: 'u',
      name: 'P',
      age: 0,
      primaryProfessional: '',
      diagnosisSummary: '',
    );
    final today = DateTime.now();
    final yesterday = today.subtract(const Duration(days: 1));

    int adherence(List<MedicationLog> logs) => MalvaStoreState(
          patient: patient,
          medications: [med],
          medicationLogs: logs,
        ).adherencePercent;

    MedicationLog log(String status, DateTime at) => MedicationLog(
          medicationId: 'm',
          medicationName: 'Sertraline',
          takenAt: at,
          status: status,
        );

    expect(adherence([log('taken', today)]), 100, reason: 'taken hari ini');
    expect(adherence([log('partial', today)]), 0,
        reason: 'partial tidak dihitung');
    expect(adherence([log('skipped', today)]), 0,
        reason: 'skipped tidak dihitung');
    expect(adherence([log('missed', today)]), 0,
        reason: 'missed tidak dihitung');
    expect(adherence([log('taken', yesterday)]), 0,
        reason: 'taken kemarin tidak dihitung untuk hari ini');
    // Kombinasi: 1 taken hari ini dari 1 obat → 100 walau ada status lain.
    expect(
      adherence(
          [log('taken', today), log('partial', today), log('missed', today)]),
      100,
    );
  });

  // ----------------------------------------------------------------------
  // #7 — TIDAK ADA KEBOCORAN ASYNC: server error 500 / token kosong
  // ----------------------------------------------------------------------
  test('tidak ada unhandled exception saat server error 500 di semua endpoint',
      () async {
    final api = _api(medicationsStatus: 500, logsStatus: 500);
    final store = _container(api).read(malvaStoreProvider.notifier);

    // Tidak boleh melempar keluar dari applySession (fire-and-forget aman).
    store.applySession(_session);
    await pumpEventQueue();

    // State tetap konsisten (tidak crash, tidak spinner abadi — ini store).
    expect(store.state.medications, isEmpty);
    expect(store.state.medicationLogs, isEmpty);
  });

  test('tidak ada unhandled exception saat token kosong', () async {
    final api = _api(medications: [_medJson('med_1', 3)], logs: const []);
    final store = _container(api).read(malvaStoreProvider.notifier);
    store.applySession(_offlineSession);
    await pumpEventQueue();

    // Token kosong: loadMedications/loadMedicationLogs early-return, tanpa error.
    expect(store.state.medicationLogs, isEmpty);
  });

  // ----------------------------------------------------------------------
  // #8 — REGRESI STOK: stok 2 tidak naik jadi 3 (pending dose)
  // ----------------------------------------------------------------------
  test('regresi stok: stok tidak naik kembali ke 3 sebelum server memotong',
      () async {
    final api = _api(medications: [_medJson('med_1', 3)], logs: const []);
    final store = _container(api).read(malvaStoreProvider.notifier);
    store.applySession(_session);
    await store.loadMedications(api, _session.accessToken);
    await pumpEventQueue();
    expect(store.state.medications.first.currentStock, 3);

    // Pasien minum → stok lokal 2, satu dosis pending.
    store.takeMedication('med_1', status: 'taken');
    expect(store.state.medications.first.currentStock, 2);
    expect(store.pendingDosesFor('med_1'), 1);

    // Refresh dari server yang BELUM memotong stok (masih 3) → harus tetap 2.
    store.replaceMedications([
      const Medication(
        id: 'med_1',
        name: 'Sertraline',
        dosage: '50mg',
        form: 'Tablet',
        reminders: [],
        currentStock: 3,
        alertBelow: 1,
        source: 'resep',
      ),
    ]);
    expect(store.state.medications.first.currentStock, 2,
        reason: 'pending dose harus menjaga stok tetap 2, bukan balik 3');

    // Server menerima → confirmDose → stok server jadi 2 → tetap 2.
    store.confirmDose('med_1');
    expect(store.pendingDosesFor('med_1'), 0);
    store.replaceMedications([
      const Medication(
        id: 'med_1',
        name: 'Sertraline',
        dosage: '50mg',
        form: 'Tablet',
        reminders: [],
        currentStock: 2,
        alertBelow: 1,
        source: 'resep',
      ),
    ]);
    expect(store.state.medications.first.currentStock, 2);
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
