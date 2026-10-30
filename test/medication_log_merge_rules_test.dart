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
// QA — T6 ROUND 2: UJI INDEPENDEN ATURAN MERGE BARU
//
// Perbaikan engineer: dedupe berbasis jendela waktu 2 menit + aturan
// "obat sama" (id sama non-kosong ATAU nama sama bila salah satu id
// sementara/kosong). Heuristik "newestServer" dihapus → log lokal yang
// lebih lama dari log server terbaru TIDAK dibuang.
//
// Test ini TIDAK menyalin test engineer; menulis ulang skenario batas
// dari sudut pandang QA untuk memastikan aturan benar-benar ditegakkan.
// ============================================================

const _session = AuthSession(
  role: UserRole.patient,
  identifier: 'pasien@malva.app',
  displayName: 'Pasien',
  backendUserId: 'user1',
  accessToken: 'token_test',
);

const _offlineSession = AuthSession(
  role: UserRole.patient,
  identifier: 'pasien@malva.app',
  displayName: 'Pasien',
  backendUserId: 'user1',
  accessToken: '',
);

MedicationLog _log(String id, String name, DateTime at, String status) =>
    MedicationLog(
      medicationId: id,
      medicationName: name,
      takenAt: at,
      status: status,
    );

Map<String, dynamic> _medJson(String id, String name, int stock) => {
      'id': id,
      'name': name,
      'dosage': '50mg',
      'current_stock': stock,
      'alert_below': 1,
      'form': 'Tablet',
      'reminder_time': '08:00',
      'source': 'resep',
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
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
  });

  // A — dua obat BERBEDA (UUID + nama beda) pada menit sama → 2 entri.
  test('A: dua obat berbeda pada menit sama tidak digabung (2 entri)', () async {
    final api = _api();
    final store = _container(api).read(malvaStoreProvider.notifier);
    store.applySession(_session);
    await pumpEventQueue();

    final t = DateTime(2026, 3, 1, 9, 0, 0);
    store.replaceMedicationLogs([
      _log('11111111-aaaa', 'Sertraline', t, 'taken'),
    ]);
    store.replaceMedicationLogs([
      _log('22222222-bbbb', 'Metformin', t, 'taken'),
    ]);

    expect(store.state.medicationLogs, hasLength(2),
        reason: 'jendela 2 menit tidak boleh menyatukan obat berbeda');
  });

  // B — dua resep NAMA SAMA tapi UUID berbeda → 2 entri.
  test('B: nama obat sama tetapi id UUID berbeda = dua resep (2 entri)',
      () async {
    final api = _api();
    final store = _container(api).read(malvaStoreProvider.notifier);
    store.applySession(_session);
    await pumpEventQueue();

    final t = DateTime(2026, 3, 1, 9, 0, 0);
    store.replaceMedicationLogs([
      _log('33333333-cccc', 'Lamictal', t, 'taken'),
    ]);
    store.replaceMedicationLogs([
      _log('44444444-dddd', 'Lamictal', t, 'taken'),
    ]);

    expect(store.state.medicationLogs, hasLength(2),
        reason: 'dua id server sah yang berbeda = dua resep (mis. 20mg vs 50mg)');
  });

  // C — batas jendela: tepat 2 menit = satu dosis; 2 menit 1 detik = dua.
  test('C: selisih tepat 2 menit = satu dosis', () async {
    final api = _api();
    final store = _container(api).read(malvaStoreProvider.notifier);
    store.applySession(_session);
    await pumpEventQueue();

    final base = DateTime(2026, 3, 1, 8, 0, 0);
    store.replaceMedicationLogs([_log('uuid-x', 'X', base, 'taken')]);
    store.replaceMedicationLogs([
      _log('uuid-x', 'X', base.add(const Duration(minutes: 2)), 'taken'),
    ]);
    expect(store.state.medicationLogs, hasLength(1),
        reason: 'Δt tepat 2 menit (<= batas) = dosis sama');
  });

  test('C: selisih 2 menit 1 detik = dua dosis', () async {
    final api = _api();
    final store = _container(api).read(malvaStoreProvider.notifier);
    store.applySession(_session);
    await pumpEventQueue();

    final base = DateTime(2026, 3, 1, 8, 0, 0);
    store.replaceMedicationLogs([_log('uuid-x', 'X', base, 'taken')]);
    store.replaceMedicationLogs([
      _log('uuid-x', 'X',
          base.add(const Duration(minutes: 2, seconds: 1)), 'taken'),
    ]);
    expect(store.state.medicationLogs, hasLength(2),
        reason: 'Δt 121 detik (> batas) = dua dosis berbeda');
  });

  // D — status berbeda pada waktu berdekatan (partial lalu taken) → 2 entri,
  //     adherence hanya menghitung yang 'taken'.
  test('D: partial lalu taken (obat sama, 1 menit) = 2 entri; adherence hanya taken',
      () async {
    // Dua obat dimuat agar adherence bisa membedakan "partial dihitung/tidak".
    final api = _api(medications: [
      _medJson('uuid-a', 'ObatA', 5),
      _medJson('uuid-b', 'ObatB', 5),
    ]);
    final store = _container(api).read(malvaStoreProvider.notifier);
    store.applySession(_session);
    await store.loadMedications(api, _session.accessToken);
    await pumpEventQueue();
    expect(store.state.medications, hasLength(2));

    final t = DateTime.now();
    store.replaceMedicationLogs([_log('uuid-a', 'ObatA', t, 'partial')]);
    store.replaceMedicationLogs([
      _log('uuid-a', 'ObatA', t.add(const Duration(minutes: 1)), 'taken'),
    ]);

    // Status berbeda → dua entri (bukan dosis sama).
    expect(store.state.medicationLogs, hasLength(2));
    // Hanya 1 'taken' hari ini dari 2 obat → 50%. Bila 'partial' ikut
    // dihitung akan jadi 100% (salah).
    expect(store.state.adherencePercent, 50,
        reason: 'partial tidak boleh menaikkan adherence');
  });

  // E — idempoten: dua panggilan replaceMedicationLogs dengan data server sama.
  test('E: replaceMedicationLogs idempoten (data server sama, 2x panggil)',
      () async {
    final api = _api();
    final store = _container(api).read(malvaStoreProvider.notifier);
    store.applySession(_session);
    await pumpEventQueue();

    final base = DateTime(2026, 3, 1, 8, 0, 0);
    final server = [
      _log('uuid-p', 'P', base, 'taken'),
      _log('uuid-q', 'Q', base.add(const Duration(hours: 1)), 'taken'),
    ];
    store.replaceMedicationLogs(server);
    final afterFirst = store.state.medicationLogs.length;
    store.replaceMedicationLogs(server);
    expect(store.state.medicationLogs.length, afterFirst,
        reason: 'memanggil ulang dengan data sama tidak menambah entri');
    expect(afterFirst, 2);
  });

  // F — cache ditulis ulang setelah merge; sesi offline memuat gabungan
  //     termasuk log lokal lama yang dipertahankan.
  test('F: cache menyimpan gabungan (log lokal lama + server) untuk sesi offline',
      () async {
    final api = _api(medications: [_medJson('uuid-1', 'X', 5)], logs: const []);
    final store1 = _container(api).read(malvaStoreProvider.notifier);
    store1.applySession(_session);
    await store1.loadMedications(api, _session.accessToken);
    await pumpEventQueue();

    // Log lokal lama (offline, 08:00) yang belum ada di server.
    final oldLocal = _log('uuid-1', 'X', DateTime(2026, 3, 1, 8, 0), 'taken');
    store1.replaceMedicationLogs([oldLocal]);
    // Server punya dosis jam 20:00 (12 jam kemudian) → bukan dosis sama.
    final serverLate = _log('uuid-1', 'X', DateTime(2026, 3, 1, 20, 0), 'taken');
    store1.replaceMedicationLogs([serverLate]);
    await pumpEventQueue();

    expect(store1.state.medicationLogs, hasLength(2),
        reason: 'log lokal lama tidak boleh dibuang oleh log server lebih baru');

    // Sesi baru OFFLINE: hidrasi dari cache harus memuat gabungan terakhir.
    final store2 = _container(api).read(malvaStoreProvider.notifier);
    store2.applySession(_offlineSession);
    await pumpEventQueue();

    expect(store2.state.medicationLogs, hasLength(2),
        reason: 'cache harus memuat 2 entri gabungan');
    expect(
      store2.state.medicationLogs.any((l) => l.takenAt == oldLocal.takenAt),
      isTrue,
      reason: 'log lokal lama harus ikut tersimpan di cache',
    );
    expect(
      store2.state.medicationLogs.any((l) => l.takenAt == serverLate.takenAt),
      isTrue,
    );
  });

  // #5 — tidak ada kebocoran async dari unawaited(_persistMedicationLogs()).
  test('merge berulang tidak menghasilkan unhandled exception (persist fire-and-forget)',
      () async {
    final api = _api(medications: [_medJson('uuid-1', 'X', 5)], logs: const []);
    final store = _container(api).read(malvaStoreProvider.notifier);
    store.applySession(_session);
    await pumpEventQueue();

    // 50 merge beruntun; tiap merge memicu unawaited persist.
    for (var i = 0; i < 50; i++) {
      store.replaceMedicationLogs([
        _log('uuid-1', 'X',
            DateTime(2026, 3, 1).add(Duration(minutes: i * 5)), 'taken'),
      ]);
    }
    await pumpEventQueue();

    // Tidak ada unhandled exception (kalau ada, test ini gagal). State konsisten.
    expect(store.state.medicationLogs, isNotEmpty);
    // Semua 50 dosis berbeda (>2 menit) tetap ada.
    expect(store.state.medicationLogs, hasLength(50));
  });
}

/// Klien HTTP palsu (pola repo).
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
