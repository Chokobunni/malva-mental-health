import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:malva_mental_health/src/models.dart';
import 'package:malva_mental_health/src/providers/providers.dart';
import 'package:malva_mental_health/src/screens/medication_screen.dart';
import 'package:malva_mental_health/src/services/malva_api_client.dart';
import 'package:malva_mental_health/src/services/offline_sync_service.dart';
import 'package:malva_mental_health/src/services/server_clock.dart';
import 'package:malva_mental_health/src/time/wib.dart';
import 'package:malva_mental_health/src/theme.dart';

// ============================================================
// REGRESI ZONA WAKTU + SERVER CLOCK (obat)
//
// Pelajaran dari putaran sebelumnya: test LULUS padahal bug masih ada karena
// fake API mengembalikan timestamp LOKAL tanpa `Z`. Backend Go menyerialkan
// `taken_at` (timestamptz) sebagai RFC3339 UTC, jadi SEMUA test di sini
// memakai bentuk yang sama dengan server nyata: `DateTime` UTC (`isUtc`).
// ============================================================

const _session = AuthSession(
  role: UserRole.patient,
  identifier: 'pasien@malva.app',
  displayName: 'Pasien',
  backendUserId: 'user1',
  accessToken: 'token_test',
);

/// Id obat berbentuk UUID seperti yang dikirim server (36 karakter).
const _serverMedId = 'a1b2c3d4-0000-4000-8000-000000000001';

const _patient = PatientProfile(
  id: 'user1',
  name: 'Pasien',
  age: 0,
  primaryProfessional: '',
  diagnosisSummary: '',
);

Medication _med(String id, String name, {int stock = 10}) => Medication(
      id: id,
      name: name,
      dosage: '50mg',
      form: 'Tablet',
      reminders: const [
        MedicationReminder(
            time: TimeOfDay(hour: 8, minute: 0), relationToMeal: ''),
      ],
      currentStock: stock,
      alertBelow: 1,
      source: 'resep',
    );

MedicationLog _log(String id, String name, DateTime at,
        {String status = 'taken'}) =>
    MedicationLog(
      medicationId: id,
      medicationName: name,
      takenAt: at,
      status: status,
    );

int _adherence(List<Medication> meds, List<MedicationLog> logs) =>
    MalvaStoreState(
      patient: _patient,
      medications: meds,
      medicationLogs: logs,
    ).adherencePercent;

/// Wall-clock WIB hari ini pada jam tertentu.
///
/// WAJIB lewat [wibFromParts]: `DateTime(...)` memakai zona perangkat sehingga
/// di mesin UTC instant-nya bergeser 7 jam.
DateTime _todayAt(int hour, int minute) {
  final now = wibNow();
  return wibFromParts(now.year, now.month, now.day, hour, minute);
}

/// Wall-clock WIB kemarin pada jam tertentu.
DateTime _yesterdayAt(int hour, int minute) {
  final now = wibNow();
  return wibFromParts(now.year, now.month, now.day, hour, minute)
      .subtract(const Duration(days: 1));
}

http.Response _json(Object body, int status) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    );

MalvaApiClient _api({
  List<Map<String, dynamic>> medications = const [],
  List<Map<String, dynamic>> logs = const [],
  int medicationLogStatus = 200,
}) {
  return MalvaApiClient(
    baseUrl: 'http://backend.test',
    httpClient: _FakeClient((request) async {
      switch (request.url.path) {
        case '/v1/medications':
          return _json({'medications': medications}, 200);
        case '/v1/medication-logs':
          if (request.method == 'POST') {
            return _json(
                {'error': 'server sedang tidak tersedia'}, medicationLogStatus);
          }
          return _json({'medication_logs': logs}, 200);
        default:
          return _json(<String, dynamic>{}, 200);
      }
    }),
  );
}

ProviderContainer _container(MalvaApiClient api, {AuthSession? session}) {
  final container = ProviderContainer(
    overrides: [
      apiClientProvider.overrideWithValue(api),
      if (session != null)
        authStateProvider.overrideWith((ref) {
          final notifier = AuthNotifier();
          notifier.setSession(session);
          return notifier;
        }),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

Widget _screenApp(ProviderContainer container, MalvaApiClient api) {
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      theme: buildMalvaTheme(),
      home: MedicationScreen(session: _session, apiClient: api),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
    ServerClock.reset();
  });

  tearDown(ServerClock.reset);

  // ----------------------------------------------------------------------
  // #1 — REGRESI INTI: log server UTC yang di WIB masih hari ini
  // ----------------------------------------------------------------------
  test(
      'regresi UTC: dosis pukul 00:05 WIB (tersimpan sebagai hari sebelumnya di UTC) tetap 100%',
      () {
    final now = wibNow();
    // 00:05 waktu LOKAL hari ini. Di WIB (UTC+7) ini menjadi 17:05 UTC
    // KEMARIN — bentuk yang persis dikirim backend Go.
    final takenLocalEarly = _todayAt(0, 5);
    final takenAtUtc = takenLocalEarly.toUtc();

    expect(takenAtUtc.isUtc, isTrue,
        reason: 'bentuk timestamp harus sama dengan server (UTC/Z)');

    // Pembanding hari: LOKAL sama, tetapi `.day` UTC berbeda dari `.day`
    // lokal — inilah yang membuat kode lama menghitung 0.
    expect(isSameLocalDay(takenAtUtc, now), isTrue,
        reason: 'hari kalender lokal harus sama');
    if (now.timeZoneOffset >= const Duration(minutes: 5)) {
      expect(takenAtUtc.day, isNot(now.day),
          reason: 'di UTC tanggalnya memang hari sebelumnya');
    }

    final percent = _adherence(
      [_med(_serverMedId, 'Sertraline')],
      [_log(_serverMedId, 'Sertraline', takenAtUtc)],
    );
    expect(percent, 100,
        reason: 'dosis hari ini (WIB) tidak boleh terbaca 0% hanya karena UTC');
  });

  // ----------------------------------------------------------------------
  // #2 — RIWAYAT: jam yang tampil harus jam LOKAL, bukan jam UTC
  // ----------------------------------------------------------------------
  test(
      'riwayat: log UTC 2026-10-29T20:20:00Z diformat sebagai 30/10/2026 03:20',
      () {
    final utc = DateTime.parse('2026-10-29T20:20:00Z');
    expect(utc.isUtc, isTrue);
    final formatted = MedicationScreen.formatLogTime(utc);
    expect(formatted, '30/10/2026 03:20',
        reason: 'harus dikonversi ke waktu lokal (WIB = UTC+7)');
  });

  testWidgets('riwayat: kartu riwayat menampilkan waktu lokal untuk log UTC',
      (tester) async {
    // Layar uji diperbesar agar seluruh ListView (termasuk riwayat) terbangun.
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final api = _api();
    final container = _container(api);
    final store = container.read(malvaStoreProvider.notifier);
    store.replaceMedications([_med(_serverMedId, 'Sertraline')]);
    store.replaceMedicationLogs([
      _log(_serverMedId, 'Sertraline', DateTime.parse('2026-10-29T20:20:00Z')),
    ]);

    await tester.pumpWidget(_screenApp(container, api));
    await tester.pumpAndSettle();

    expect(find.textContaining('30/10/2026 03:20'), findsOneWidget,
        reason: 'riwayat harus memakai jam lokal');
    expect(find.textContaining('29/10/2026 20:20'), findsNothing,
        reason: 'jam UTC mentah tidak boleh tampil');
  });

  // ----------------------------------------------------------------------
  // #3 — SERVER CLOCK: offset, header rusak, reset
  // ----------------------------------------------------------------------
  test(
      'ServerClock: applyHttpDate menghitung offset dengan kompensasi setengah RTT',
      () async {
    // Semua waktu uji dalam UTC agar hasilnya tidak bergantung zona mesin.
    final started = DateTime.utc(2026, 10, 30, 3, 20, 0);
    final received = started.add(const Duration(seconds: 2));

    // Header: server menjawab pukul 03:20:02 GMT. Estimasi saat jawaban itu
    // tiba di perangkat = started + ½ RTT = 03:20:01 → offset = +1 detik
    // (tanpa kompensasi ½ RTT hasilnya +2 detik, jadi angka ini membuktikan
    // kompensasi bekerja).
    ServerClock.applyHttpDate(
      'Wed, 30 Oct 2026 03:20:02 GMT',
      requestStarted: started,
      responseReceived: received,
    );

    expect(ServerClock.offset.inSeconds, 1,
        reason: 'kompensasi setengah RTT = 1 detik');
    expect(ServerClock.isSynced, isTrue);

    // now() bergeser sebesar offset.
    final deltaMs = ServerClock.now().difference(wibNow()).inMilliseconds;
    expect(deltaMs, inInclusiveRange(900, 1100),
        reason: 'now() harus bergeser ~1 detik dari jam perangkat');

    await pumpEventQueue();
  });

  test(
      'ServerClock: header rusak/null tidak mengubah offset dan tidak melempar',
      () async {
    final started = DateTime.utc(2026, 10, 30, 3, 20, 0);
    final received = started.add(const Duration(seconds: 2));

    // Offset acuan: +1 detik.
    ServerClock.applyHttpDate(
      'Wed, 30 Oct 2026 03:20:02 GMT',
      requestStarted: started,
      responseReceived: received,
    );
    expect(ServerClock.offset.inSeconds, 1);

    // Header tidak bisa diparse → tidak berubah, tidak melempar.
    ServerClock.applyHttpDate(
      'bukan tanggal',
      requestStarted: started,
      responseReceived: received,
    );
    expect(ServerClock.offset.inSeconds, 1,
        reason: 'header rusak harus diabaikan');

    ServerClock.applyHttpDate(
      null,
      requestStarted: started,
      responseReceived: received,
    );
    expect(ServerClock.offset.inSeconds, 1, reason: 'header null diabaikan');

    // Tanggal tidak masuk akal (> 24 jam dari jam perangkat) → diabaikan.
    ServerClock.applyHttpDate(
      'Wed, 30 Oct 2030 03:20:00 GMT',
      requestStarted: started,
      responseReceived: received,
    );
    expect(ServerClock.offset.inSeconds, 1,
        reason: 'selisih > 24 jam diabaikan (header/proxy rusak)');

    // reset() mengembalikan ke kondisi awal.
    ServerClock.reset();
    expect(ServerClock.offset, Duration.zero);
    expect(ServerClock.isSynced, isFalse);

    await pumpEventQueue();
  });

  // ----------------------------------------------------------------------
  // #4 — SERVER CLOCK: offset dipersist lalu dipulihkan
  // ----------------------------------------------------------------------
  test('ServerClock: offset bertahan setelah persist → reset → loadPersisted',
      () async {
    final started = DateTime.utc(2026, 10, 30, 3, 20, 0);
    final received = started.add(const Duration(seconds: 2));
    ServerClock.applyHttpDate(
      'Wed, 30 Oct 2026 03:20:02 GMT',
      requestStarted: started,
      responseReceived: received,
    );
    await ServerClock.persist();
    expect(ServerClock.offset.inSeconds, 1);

    ServerClock.reset();
    expect(ServerClock.offset, Duration.zero);
    expect(ServerClock.isSynced, isFalse);

    await ServerClock.loadPersisted();
    expect(ServerClock.offset.inSeconds, 1,
        reason:
            'offset terakhir harus terpakai lagi (mis. cold start offline)');
    expect(ServerClock.isSynced, isTrue);
  });

  // ----------------------------------------------------------------------
  // #5 — ADHERENCE SKALABEL: jumlah OBAT unik, bukan jumlah dosis
  // ----------------------------------------------------------------------
  test('adherence banyak obat: 1 obat dicatat 2x dari 10 obat = 10%', () {
    final meds = [for (var i = 1; i <= 10; i++) _med('med_$i', 'Obat $i')];
    final percent = _adherence(meds, [
      _log('med_1', 'Obat 1', _todayAt(7, 0)),
      _log('med_1', 'Obat 1', _todayAt(19, 0)),
    ]);
    expect(percent, 10,
        reason: 'satu obat dua kali tetap satu obat (bukan 20%)');
  });

  test('adherence banyak obat: 3 obat berbeda dari 10 obat = 30%', () {
    final meds = [for (var i = 1; i <= 10; i++) _med('med_$i', 'Obat $i')];
    final percent = _adherence(meds, [
      _log('med_1', 'Obat 1', _todayAt(7, 0)),
      _log('med_2', 'Obat 2', _todayAt(12, 0)),
      _log('med_3', 'Obat 3', _todayAt(19, 0)),
    ]);
    expect(percent, 30);
  });

  test(
      'adherence: log obat yang sudah dihapus tidak menaikkan angka di atas 100%',
      () {
    final meds = [_med(_serverMedId, 'Sertraline')];
    final percent = _adherence(meds, [
      _log(_serverMedId, 'Sertraline', _todayAt(8, 0)),
      // Obat ini sudah tidak ada di daftar medications (id UUID lain).
      _log('ffffffff-0000-4000-8000-000000000009', 'Obat Dihapus',
          _todayAt(9, 0)),
    ]);
    expect(percent, 100,
        reason: 'log obat terhapus tidak boleh membuat kepatuhan > 100%');
  });

  // ----------------------------------------------------------------------
  // #6 — BATAS HARI (LOKAL)
  // ----------------------------------------------------------------------
  test(
      'batas hari: log kemarin tidak dihitung, log 00:05 WIB hari ini dihitung',
      () {
    final meds = [_med(_serverMedId, 'Sertraline')];

    expect(
      _adherence(
          meds, [_log(_serverMedId, 'Sertraline', _yesterdayAt(23, 59))]),
      0,
      reason: 'dosis kemarin 23:59 bukan bagian hari ini',
    );
    expect(
      _adherence(meds, [_log(_serverMedId, 'Sertraline', _todayAt(0, 5))]),
      100,
      reason: 'dosis 00:05 hari ini dihitung',
    );
    // Bentuk UTC dari 00:05 lokal juga harus dihitung.
    expect(
      _adherence(meds, [
        _log(_serverMedId, 'Sertraline', _todayAt(0, 5).toUtc()),
      ]),
      100,
      reason: 'bentuk UTC dari dosis 00:05 lokal harus tetap dihitung',
    );
  });

  // ----------------------------------------------------------------------
  // #7 — DURABILITAS OFFLINE: POST gagal → masuk antrean offline
  // ----------------------------------------------------------------------
  testWidgets(
      'POST log gagal: log masuk antrean offline dengan taken_at dari ServerClock',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final api = _api(medicationLogStatus: 500);
    final container = _container(api, session: _session);
    final store = container.read(malvaStoreProvider.notifier);
    store.replaceMedications([_med(_serverMedId, 'Sertraline')]);

    final syncService = container.read(offlineSyncServiceProvider);
    expect(syncService.queue, isEmpty, reason: 'antrean awal harus kosong');

    await tester.pumpWidget(_screenApp(container, api));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Take Now'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Taken'));
    await tester.pumpAndSettle();

    expect(syncService.queue, hasLength(1),
        reason: 'log yang gagal dikirim harus masuk antrean, bukan hilang');
    final item = syncService.queue.single;
    expect(item.operation, SyncOperation.medicationLog);
    expect(item.payload['medication_id'], _serverMedId);
    expect(item.payload['medication_name'], 'Sertraline');
    expect(item.payload['status'], 'taken');

    final takenAt = DateTime.parse(item.payload['taken_at'] as String);
    final drift = takenAt.difference(ServerClock.now()).abs();
    expect(drift, lessThan(const Duration(minutes: 1)),
        reason: 'taken_at antrean harus memakai acuan ServerClock');

    // SnackBar jujur: menyebut antrean offline. SnackBar error dari jalur sync
    // tampil lebih dulu, jadi majukan waktu agar SnackBar antrean yang tampil.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('antrean offline'),
      findsWidgets,
      reason: 'pesan ke pengguna harus menyebut log masuk antrean',
    );

    // Biarkan SnackBar kedaluwarsa agar tidak ada timer yang menggantung.
    await tester.pumpAndSettle(const Duration(seconds: 6));
  });

  // ----------------------------------------------------------------------
  // #8 — Sinkronisasi jam dari header Date lewat klien API nyata
  // ----------------------------------------------------------------------
  test('klien API: header Date pada respons sukses menyinkronkan ServerClock',
      () async {
    final client = MalvaApiClient(
      baseUrl: 'http://backend.test',
      httpClient: _FakeClient((request) async {
        final serverNow = wibNow().toUtc().add(const Duration(hours: 3));
        return http.Response(
          jsonEncode({'medications': <dynamic>[]}),
          200,
          headers: {
            'content-type': 'application/json',
            'date': _formatHttpDate(serverNow),
          },
        );
      }),
    );

    ServerClock.reset();
    await client.listMedications(accessToken: 'token_test');

    expect(ServerClock.isSynced, isTrue,
        reason: 'setiap respons sukses membawa header Date dari Go net/http');
    // Offset ≈ +3 jam (toleransi lebar karena melibatkan jam nyata + RTT).
    expect(ServerClock.offset.inMinutes, inInclusiveRange(175, 185));
  });
}

/// Format tanggal gaya HTTP (RFC1123) untuk fake respons server.
String _formatHttpDate(DateTime utc) {
  const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final d = utc.toUtc();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${days[d.weekday - 1]}, ${two(d.day)} ${months[d.month - 1]} '
      '${d.year} ${two(d.hour)}:${two(d.minute)}:${two(d.second)} GMT';
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
