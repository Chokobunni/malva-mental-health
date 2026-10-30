import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:malva_mental_health/src/models.dart';
import 'package:malva_mental_health/src/providers/providers.dart';
import 'package:malva_mental_health/src/screens/chat_screen.dart';
import 'package:malva_mental_health/src/screens/medication_screen.dart';
import 'package:malva_mental_health/src/screens/portal/crisis_incident_log_screen.dart';
import 'package:malva_mental_health/src/screens/professional_dashboard_screen.dart';
import 'package:malva_mental_health/src/services/malva_api_client.dart';
import 'package:malva_mental_health/src/services/server_clock.dart';
import 'package:malva_mental_health/src/widgets/daily_checkin_flow.dart';
import 'package:malva_mental_health/src/widgets/therapy_library.dart';

// ============================================================
// QA — VERIFIKASI INDEPENDEN BUG MEDICATION CHECK-IN (UTC vs WIB)
//
// Tim QA sebelumnya lolos padahal bug masih ada karena fake API mengembalikan
// timestamp LOKAL tanpa `Z`. Di file ini SEMUA timestamp dari "server" memakai
// bentuk persis backend Go: UTC (`isUtc == true`). Tujuannya membuktikan bahwa
// dosis yang di UTC jatuh "hari sebelumnya" tetapi di WIB masih hari ini tetap
// dihitung 100% — sekaligus membuktikan kode lama (yang membandingkan
// `.day/.month/.year` mentah) akan GAGAL.
// ============================================================

const _session = AuthSession(
  role: UserRole.patient,
  identifier: 'pasien@malva.app',
  displayName: 'Pasien',
  backendUserId: 'user1',
  accessToken: 'token_test',
);

const _patient = PatientProfile(
  id: 'user1',
  name: 'Pasien',
  age: 0,
  primaryProfessional: '',
  diagnosisSummary: '',
);

/// Id obat berbentuk UUID seperti yang dikirim server (36 karakter).
const _serverMedId = 'a1b2c3d4-0000-4000-8000-000000000001';

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

/// Waktu LOKAL hari ini pada jam tertentu (belum di-UTC-kan).
DateTime _todayLocal(int hour, int minute) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day, hour, minute);
}

DateTime _yesterdayLocal(int hour, int minute) =>
    _todayLocal(hour, minute).subtract(const Duration(days: 1));

/// True bila mesin uji berada di zona yang "di depan" UTC cukup jauh sehingga
/// jam 03:20 lokal benar-benar jatuh di tanggal UTC sebelumnya (kasus WIB).
bool get _tzAheadOfUtc =>
    DateTime.now().timeZoneOffset >= const Duration(hours: 4);

http.Response _json(Object body, int status) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    );

MalvaApiClient _api({
  List<Map<String, dynamic>> medications = const [],
  List<Map<String, dynamic>> logs = const [],
}) {
  return MalvaApiClient(
    baseUrl: 'http://backend.test',
    httpClient: _FakeClient((request) async {
      switch (request.url.path) {
        case '/v1/medications':
          return _json({'medications': medications}, 200);
        case '/v1/medication-logs':
          return _json({'medication_logs': logs}, 200);
        default:
          return _json(<String, dynamic>{}, 200);
      }
    }),
  );
}

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
    ServerClock.reset();
  });
  tearDown(ServerClock.reset);

  // ============================================================
  // A. REGRESI INTI — SKENARIO PERSIS USER, TIMESTAMP UTC
  // ============================================================

  test('A1: sesi 1 — takeMedication → adherence 100%, riwayat 1, stok turun',
      () async {
    final api = _api(medications: [
      {
        'id': _serverMedId,
        'name': 'Sertraline',
        'current_stock': 3,
        'alert_below': 1,
        'dosage': '50mg',
        'form': 'Tablet',
        'reminder_time': '08:00',
        'source': 'resep'
      },
    ]);
    final store = _container(api).read(malvaStoreProvider.notifier);
    store.applySession(_session);
    await pumpEventQueue();

    store.takeMedication(_serverMedId, status: 'taken');
    await pumpEventQueue();

    expect(store.state.adherencePercent, 100, reason: 'adherence sesi 1');
    expect(store.state.medicationLogs, hasLength(1), reason: 'riwayat sesi 1');
    expect(store.state.medications.first.currentStock, 2, reason: 'stok turun');
  });

  test(
      'A2: sesi 2 (notifier baru = logout/login) — log server UTC hari ini → adherence 100%, riwayat 1, stok tetap',
      () async {
    // Sesi 2: notifier BARU; server mengembalikan 1 log HARI INI dalam UTC.
    final takenAtUtc = DateTime.now().toUtc();
    expect(takenAtUtc.isUtc, isTrue, reason: 'bentuk timestamp harus UTC');

    final api = _api(
      medications: [
        {
          'id': _serverMedId,
          'name': 'Sertraline',
          'current_stock': 2,
          'alert_below': 1,
          'dosage': '50mg',
          'form': 'Tablet',
          'reminder_time': '08:00',
          'source': 'resep'
        },
      ],
      logs: [
        {
          'id': 'log1',
          'medication_id': _serverMedId,
          'medication_name': 'Sertraline',
          'status': 'taken',
          'taken_at': takenAtUtc.toIso8601String(),
          'created_at': takenAtUtc.toIso8601String()
        },
      ],
    );
    final store = _container(api).read(malvaStoreProvider.notifier);
    store.applySession(_session);
    await store.loadMedications(api, _session.accessToken);
    await store.loadMedicationLogs(api, _session.accessToken);
    await pumpEventQueue();

    expect(store.state.adherencePercent, 100, reason: 'adherence pulih');
    expect(store.state.medicationLogs, hasLength(1), reason: 'riwayat pulih');
    expect(store.state.medications.first.currentStock, 2,
        reason: 'stok tetap (tidak balik ke 3)');
  });

  test(
      'A3 (paling penting): dosis 03:20 WIB (=20:20Z kemarin) tetap 100% — kode lama akan gagal',
      () {
    final localNow = DateTime.now();
    // 03:20 waktu LOKAL hari ini. Di WIB → 20:20Z KEMARIN.
    final takenLocal =
        DateTime(localNow.year, localNow.month, localNow.day, 3, 20);
    final takenAtUtc = takenLocal.toUtc();
    expect(takenAtUtc.isUtc, isTrue);

    // Bukti bahwa kode lama (perbandingan `.day` mentah) salah:
    expect(isSameLocalDay(takenAtUtc, localNow), isTrue,
        reason: 'hari kalender LOKAL harus sama');
    if (_tzAheadOfUtc) {
      expect(takenAtUtc.day, isNot(localNow.day),
          reason: 'di UTC tanggalnya memang hari sebelumnya → kode lama 0%');
    }

    final percent = _adherence(
      [_med(_serverMedId, 'Sertraline')],
      [_log(_serverMedId, 'Sertraline', takenAtUtc)],
    );
    expect(percent, 100,
        reason: 'dosis hari ini (WIB) tidak boleh 0% hanya karena UTC');
  });

  test('A3b: dosis dini hari 00:05 WIB (bentuk UTC) juga 100%', () {
    final localNow = DateTime.now();
    final takenUtc =
        DateTime(localNow.year, localNow.month, localNow.day, 0, 5).toUtc();
    expect(isSameLocalDay(takenUtc, localNow), isTrue);
    expect(
      _adherence([_med(_serverMedId, 'Sertraline')],
          [_log(_serverMedId, 'Sertraline', takenUtc)]),
      100,
    );
  });

  // ============================================================
  // B. SKALA BANYAK OBAT
  // ============================================================

  test('B4: 10 obat, 1 obat dicatat 2x hari ini = 10% (bukan 20/100)', () {
    final meds = [for (var i = 1; i <= 10; i++) _med('med_$i', 'Obat $i')];
    final percent = _adherence(meds, [
      _log('med_1', 'Obat 1', _todayLocal(7, 0).toUtc()),
      _log('med_1', 'Obat 1', _todayLocal(19, 0).toUtc()),
    ]);
    expect(percent, 10, reason: 'satu obat dua kali tetap satu obat');
  });

  test('B5: 3 obat berbeda dari 10 = 30%', () {
    final meds = [for (var i = 1; i <= 10; i++) _med('med_$i', 'Obat $i')];
    final percent = _adherence(meds, [
      _log('med_1', 'Obat 1', _todayLocal(7, 0).toUtc()),
      _log('med_2', 'Obat 2', _todayLocal(12, 0).toUtc()),
      _log('med_3', 'Obat 3', _todayLocal(19, 0).toUtc()),
    ]);
    expect(percent, 30);
  });

  test('B6: log obat yang sudah dihapus tidak menaikkan angka > 100%', () {
    final percent = _adherence([
      _med(_serverMedId, 'Sertraline')
    ], [
      _log(_serverMedId, 'Sertraline', _todayLocal(8, 0).toUtc()),
      // id UUID sah tetapi tidak ada di daftar medications → obat dihapus.
      _log('ffffffff-0000-4000-8000-000000000009', 'Obat Dihapus',
          _todayLocal(9, 0).toUtc()),
    ]);
    expect(percent, 100, reason: 'tidak boleh > 100%');
  });

  test('B7: 50 obat, 20 diminum = 40%', () {
    final meds = [for (var i = 1; i <= 50; i++) _med('med_$i', 'Obat $i')];
    final logs = [
      for (var i = 1; i <= 20; i++)
        _log('med_$i', 'Obat $i', _todayLocal(8, 0).toUtc()),
    ];
    expect(_adherence(meds, logs), 40);
  });

  test(
      'B8: log kemarin (lokal) tidak dihitung; log 00:05 WIB hari ini dihitung',
      () {
    final meds = [_med(_serverMedId, 'Sertraline')];
    expect(
      _adherence(meds, [
        _log(_serverMedId, 'Sertraline', _yesterdayLocal(23, 59).toUtc()),
      ]),
      0,
      reason: 'dosis kemarin 23:59 bukan bagian hari ini',
    );
    expect(
      _adherence(meds, [
        _log(_serverMedId, 'Sertraline', _todayLocal(0, 5).toUtc()),
      ]),
      100,
      reason: 'dosis 00:05 hari ini dihitung',
    );
  });

  // ============================================================
  // C. SERVER CLOCK
  // ============================================================

  test(
      'C9: applyHttpDate RFC1123 → offset benar (kompensasi ½ RTT), now() bergeser',
      () async {
    final started = DateTime.utc(2026, 10, 30, 3, 20, 0);
    final received = started.add(const Duration(seconds: 2));
    ServerClock.applyHttpDate(
      'Wed, 30 Oct 2026 03:20:02 GMT',
      requestStarted: started,
      responseReceived: received,
    );
    // server 03:20:02, estimasi tiba = 03:20:01 → offset +1 detik.
    expect(ServerClock.offset.inSeconds, 1,
        reason: 'kompensasi setengah RTT = 1 detik');
    expect(ServerClock.isSynced, isTrue);
    final deltaMs = ServerClock.now().difference(DateTime.now()).inMilliseconds;
    expect(deltaMs, inInclusiveRange(900, 1100),
        reason: 'now() harus bergeser ~1 detik dari jam perangkat');
    await pumpEventQueue();
  });

  test(
      'C10: header null/rusak/offset > 24 jam tidak mengubah offset, tidak melempar',
      () async {
    final started = DateTime.utc(2026, 10, 30, 3, 20, 0);
    final received = started.add(const Duration(seconds: 2));
    ServerClock.applyHttpDate('Wed, 30 Oct 2026 03:20:02 GMT',
        requestStarted: started, responseReceived: received);
    expect(ServerClock.offset.inSeconds, 1);

    ServerClock.applyHttpDate('bukan tanggal',
        requestStarted: started, responseReceived: received);
    expect(ServerClock.offset.inSeconds, 1, reason: 'header rusak diabaikan');

    ServerClock.applyHttpDate(null,
        requestStarted: started, responseReceived: received);
    expect(ServerClock.offset.inSeconds, 1, reason: 'header null diabaikan');

    ServerClock.applyHttpDate('Wed, 30 Oct 2030 03:20:00 GMT',
        requestStarted: started, responseReceived: received);
    expect(ServerClock.offset.inSeconds, 1,
        reason: 'selisih > 24 jam diabaikan');
    await pumpEventQueue();
  });

  test('C11: persist → reset → loadPersisted memulihkan offset yang sama',
      () async {
    final started = DateTime.utc(2026, 10, 30, 3, 20, 0);
    final received = started.add(const Duration(seconds: 2));
    ServerClock.applyHttpDate('Wed, 30 Oct 2026 03:20:02 GMT',
        requestStarted: started, responseReceived: received);
    await ServerClock.persist();
    expect(ServerClock.offset.inSeconds, 1);

    ServerClock.reset();
    expect(ServerClock.offset, Duration.zero);
    expect(ServerClock.isSynced, isFalse);

    await ServerClock.loadPersisted();
    expect(ServerClock.offset.inSeconds, 1,
        reason: 'offset terakhir terpakai lagi (cold start offline)');
    expect(ServerClock.isSynced, isTrue);
  });

  test(
      'C12: respons HTTP sukses dengan header Date menyinkronkan ServerClock (via klien API)',
      () async {
    final client = MalvaApiClient(
      baseUrl: 'http://backend.test',
      httpClient: _FakeClient((request) async {
        final serverNow = DateTime.now().toUtc().add(const Duration(hours: 3));
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
        reason: 'header Date dari Go net/http harus menyinkronkan jam');
    expect(ServerClock.offset.inMinutes, inInclusiveRange(170, 190));
  });

  test('C13 (negatif): setelah reset, now() == DateTime.now() (fallback aman)',
      () {
    ServerClock.reset();
    expect(ServerClock.offset, Duration.zero);
    expect(ServerClock.isSynced, isFalse);
    final diff = ServerClock.now().difference(DateTime.now()).abs();
    expect(diff, lessThan(const Duration(seconds: 1)),
        reason: 'tanpa sinkron, now() harus jatuh ke jam perangkat');
  });

  // ============================================================
  // D. MOOD, CHAT, PORTAL (kelas bug sama)
  // ============================================================

  MoodEntry _moodUtc(DateTime utc) => MoodEntry(
        date: utc,
        mood: MoodValue.okay,
        sleepHours: 7,
        energy: 3,
        anxiety: 3,
        irritability: 3,
        note: 'catatan',
      );

  test(
      'D14: hasCheckedInToday — mood 00:30 WIB (UTC kemarin) = true; mood kemarin = false',
      () {
    final localNow = DateTime.now();
    final earlyUtc =
        DateTime(localNow.year, localNow.month, localNow.day, 0, 30).toUtc();
    expect(earlyUtc.isUtc, isTrue);
    if (_tzAheadOfUtc) {
      expect(earlyUtc.day, isNot(localNow.day),
          reason: 'di UTC tanggalnya memang hari sebelumnya');
    }
    expect(hasCheckedInToday([_moodUtc(earlyUtc)]), isTrue,
        reason: 'check-in dini hari tidak boleh dianggap belum check-in');

    expect(
        hasCheckedInToday([_moodUtc(_yesterdayLocal(22, 0).toUtc())]), isFalse);
  });

  test('D15: checkInStreak — 3 hari berturut dengan timestamp UTC malam = 3',
      () {
    final moods = [
      _moodUtc(_todayLocal(20, 0).toUtc()),
      _moodUtc(_yesterdayLocal(20, 0).toUtc()),
      _moodUtc(_todayLocal(20, 0).subtract(const Duration(days: 2)).toUtc()),
    ];
    expect(moods.every((m) => m.date.isUtc), isTrue);
    expect(checkInStreak(moods), 3,
        reason: 'streak tidak boleh 0/1 hanya karena timestamp UTC');
  });

  test(
      'D16: chat formatMessageTime(20:20Z)=03:20; formatMessageDate tidak memuat tanggal UTC mentah',
      () {
    final utc = DateTime.parse('2026-10-29T20:20:00Z');
    expect(utc.isUtc, isTrue);
    expect(ChatScreen.formatMessageTime(utc), '03:20',
        reason: 'jam gelembung harus jam lokal (WIB)');

    final label = ChatScreen.formatMessageDate(utc);
    final now = DateTime.now();
    final isToday = now.year == 2026 && now.month == 10 && now.day == 30;
    expect(label, isToday ? 'Hari ini 03:20' : '30/10/2026 03:20',
        reason: 'tanggal harus tanggal LOKAL');
    expect(label.contains('29/10/2026'), isFalse,
        reason: 'tanggal UTC mentah tidak boleh tampil');
  });

  test(
      'D17: formatScreeningDate(20:20Z)=30/10/2026 dan CSV memakai tanggal lokal yang sama',
      () {
    final utc = DateTime.parse('2026-10-29T20:20:00Z');
    expect(formatScreeningDate(utc), '30/10/2026');
    expect(formatScreeningDate(utc), isNot('29/10/2026'));
    final csvRow = 'Screening Date,${formatScreeningDate(utc)}';
    expect(csvRow, 'Screening Date,30/10/2026');
  });

  test(
      'D18: formatIncidentDate & formatTherapyRecordDate untuk UTC → tanggal/jam lokal',
      () {
    final utc = DateTime.parse('2026-10-29T20:20:00Z');
    expect(formatIncidentDate(utc), '30/10/2026 03:20');
    expect(formatTherapyRecordDate(utc), '30/10/2026 03:20');
    expect(formatIncidentDate(null), '');
    expect(formatTherapyRecordDate(null), '');
  });

  // ============================================================
  // Tambahan: MedicationScreen.formatLogTime (riwayat)
  // ============================================================

  test('formatLogTime: 20:20Z → 30/10/2026 03:20 (jam lokal)', () {
    expect(
      MedicationScreen.formatLogTime(DateTime.parse('2026-10-29T20:20:00Z')),
      '30/10/2026 03:20',
    );
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
