import 'package:flutter_test/flutter_test.dart';

import 'package:malva_mental_health/src/models.dart';
import 'package:malva_mental_health/src/screens/chat_screen.dart';
import 'package:malva_mental_health/src/services/server_clock.dart';
import 'package:malva_mental_health/src/time/wib.dart';
import 'package:malva_mental_health/src/widgets/daily_checkin_flow.dart';

// ============================================================
// REGRESI ZONA WAKTU — MOOD & CHAT
//
// Kelas bug yang sama dengan medication: data dari server berbentuk UTC
// (`...Z`), lalu dibandingkan/diformat dengan field mentah (`.day/.hour`).
// Akibatnya check-in pukul 22:00 WIB terbaca "kemarin" → pasien diminta
// check-in lagi setelah logout/login, dan streak bisa jatuh ke 0.
//
// SEMUA timestamp di sini memakai bentuk server nyata (UTC, `isUtc == true`).
// ============================================================

/// Mood check-in dengan waktu UTC seperti yang dikirim backend.
MoodEntry _moodUtc(DateTime utc, {double sleepHours = 7}) => MoodEntry(
      date: utc,
      mood: MoodValue.okay,
      sleepHours: sleepHours,
      energy: 3,
      anxiety: 3,
      irritability: 3,
      note: 'catatan',
    );

/// Wall-clock WIB hari ini pada jam tertentu, dikembalikan sebagai UTC
/// (bentuk yang persis dikirim server).
///
/// WAJIB lewat [wibFromParts]: `DateTime(...)` memakai zona perangkat sehingga
/// di mesin UTC instant-nya bergeser 7 jam.
DateTime _todayLocalAsUtc(int hour, int minute) {
  final now = wibNow();
  return wibFromParts(now.year, now.month, now.day, hour, minute).toUtc();
}

/// Wall-clock WIB `daysAgo` hari lalu pada jam tertentu, sebagai UTC.
DateTime _daysAgoLocalAsUtc(int daysAgo, int hour, int minute) {
  final now = wibNow();
  return wibFromParts(now.year, now.month, now.day, hour, minute)
      .subtract(Duration(days: daysAgo))
      .toUtc();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(ServerClock.reset);
  tearDown(ServerClock.reset);

  // ----------------------------------------------------------------------
  // #1 — hasCheckedInToday: mood malam hari (UTC) tetap "hari ini"
  // ----------------------------------------------------------------------
  test('hasCheckedInToday: mood 22:00 WIB (bentuk UTC) dihitung sudah check-in',
      () {
    final occurredAtUtc = _todayLocalAsUtc(22, 0);
    expect(occurredAtUtc.isUtc, isTrue,
        reason: 'bentuk timestamp harus sama dengan server (UTC/Z)');
    // Di WIB, 22:00 lokal = 15:00Z hari yang sama; kode lama membandingkan
    // `.day` UTC (15) dengan `.day` lokal → tetap sama, jadi untuk 22:00
    // justru UTC-nya masih tanggal yang sama. Kasus paling rawan adalah
    // dini hari (lihat #1b).
    expect(hasCheckedInToday([_moodUtc(occurredAtUtc)]), isTrue);
  });

  test('hasCheckedInToday: mood 00:30 WIB (UTC hari sebelumnya) tetap check-in',
      () {
    final occurredAtUtc = _todayLocalAsUtc(0, 30);
    final now = wibNow();
    // Di WIB, 00:30 lokal = 17:30Z KEMARIN → kode lama menghitung false.
    if (now.timeZoneOffset >= const Duration(minutes: 30)) {
      expect(occurredAtUtc.day, isNot(now.day),
          reason: 'di UTC tanggalnya memang hari sebelumnya');
    }
    expect(hasCheckedInToday([_moodUtc(occurredAtUtc)]), isTrue,
        reason: 'check-in dini hari tidak boleh dianggap belum check-in');
  });

  // ----------------------------------------------------------------------
  // #2 — hasCheckedInToday: mood kemarin (lokal) → false
  // ----------------------------------------------------------------------
  test('hasCheckedInToday: mood kemarin (lokal) → false', () {
    expect(
        hasCheckedInToday([_moodUtc(_daysAgoLocalAsUtc(1, 22, 0))]), isFalse);
    expect(hasCheckedInToday([_moodUtc(_daysAgoLocalAsUtc(2, 9, 0))]), isFalse);
    // Tanpa durasi tidur tercatat = check-in belum lengkap.
    expect(hasCheckedInToday([_moodUtc(_todayLocalAsUtc(8, 0), sleepHours: 0)]),
        isFalse);
    expect(hasCheckedInToday(const []), isFalse);
  });

  // ----------------------------------------------------------------------
  // #3 — checkInStreak: 3 hari berturut-turut (mood malam, bentuk UTC)
  // ----------------------------------------------------------------------
  test('checkInStreak: 3 hari berturut-turut dengan timestamp UTC malam = 3',
      () {
    final moods = [
      _moodUtc(_todayLocalAsUtc(20, 0)),
      _moodUtc(_daysAgoLocalAsUtc(1, 20, 0)),
      _moodUtc(_daysAgoLocalAsUtc(2, 20, 0)),
    ];
    // Semua timestamp berbentuk UTC; untuk WIB jam 20:00 lokal = 13:00Z.
    expect(moods.every((m) => m.date.isUtc), isTrue);
    expect(checkInStreak(moods), 3,
        reason: 'streak tidak boleh 0/1 hanya karena timestamp berbentuk UTC');
  });

  test('checkInStreak: hari ini + kemarin = 2', () {
    final moods = [
      _moodUtc(_todayLocalAsUtc(23, 30)),
      _moodUtc(_daysAgoLocalAsUtc(1, 0, 10)),
    ];
    expect(checkInStreak(moods), 2);
  });

  test('checkInStreak: ada lubang sehari → streak berhenti', () {
    final moods = [
      _moodUtc(_todayLocalAsUtc(20, 0)),
      // Hari kemarin TIDAK ada check-in.
      _moodUtc(_daysAgoLocalAsUtc(2, 20, 0)),
      _moodUtc(_daysAgoLocalAsUtc(3, 20, 0)),
    ];
    expect(checkInStreak(moods), 1,
        reason: 'streak berhenti pada hari pertama yang tidak berurutan');
  });

  test('checkInStreak: beberapa check-in di hari yang sama dihitung satu hari',
      () {
    final moods = [
      _moodUtc(_todayLocalAsUtc(8, 0)),
      _moodUtc(_todayLocalAsUtc(21, 0)),
      _moodUtc(_daysAgoLocalAsUtc(1, 12, 0)),
    ];
    expect(checkInStreak(moods), 2);
  });

  // ----------------------------------------------------------------------
  // #4 — CHAT: label tanggal/jam memakai waktu LOKAL
  // ----------------------------------------------------------------------
  test('chat: 2026-10-29T20:20:00Z ditampilkan sebagai jam lokal 03:20', () {
    final utc = DateTime.parse('2026-10-29T20:20:00Z');
    expect(utc.isUtc, isTrue);

    final label = ChatScreen.formatMessageDate(utc);
    final timeLabel = ChatScreen.formatMessageTime(utc);

    expect(timeLabel, '03:20', reason: 'jam gelembung harus jam lokal (WIB)');
    // Bila "hari ini" lokal = 30/10/2026 → label "Hari ini 03:20",
    // selain itu tanggal lokal 30/10/2026 dengan jam 03:20.
    final now = wibNow();
    final isToday = now.year == 2026 && now.month == 10 && now.day == 30;
    expect(
      label,
      isToday ? 'Hari ini 03:20' : '30/10/2026 03:20',
      reason: 'tanggal pesan harus tanggal LOKAL, bukan tanggal UTC (29/10)',
    );
    expect(label.contains('29/10/2026'), isFalse,
        reason: 'tanggal UTC mentah tidak boleh tampil');
  });

  test('chat: pesan hari ini (lokal) diberi label "Hari ini"', () {
    final utc = _todayLocalAsUtc(22, 0);
    final label = ChatScreen.formatMessageDate(utc);
    expect(label, 'Hari ini 22:00',
        reason: 'pesan malam hari tidak boleh diberi tanggal kemarin');
  });

  // ----------------------------------------------------------------------
  // #5 — Kontrak helper bersama (dipakai diary, riwayat mood, notifikasi)
  // ----------------------------------------------------------------------
  test('isSameLocalDay: timestamp UTC dini hari tetap hari ini secara lokal',
      () {
    final utc = _todayLocalAsUtc(0, 30);
    expect(isSameLocalDay(utc, wibNow()), isTrue);
    expect(toWib(utc).hour, 0);
    expect(toWib(utc).minute, 30);
  });
}
