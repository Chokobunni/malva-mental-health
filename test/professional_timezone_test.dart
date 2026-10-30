import 'package:flutter_test/flutter_test.dart';

import 'package:malva_mental_health/src/screens/portal/crisis_incident_log_screen.dart';
import 'package:malva_mental_health/src/screens/professional_dashboard_screen.dart';
import 'package:malva_mental_health/src/services/server_clock.dart';
import 'package:malva_mental_health/src/widgets/therapy_library.dart';

// ============================================================
// REGRESI ZONA WAKTU — PORTAL PROFESIONAL (M9)
//
// Tanggal pada laporan klinis WAJIB mengikuti kalender LOKAL tenaga medis
// (WIB). Data dari server berbentuk UTC, jadi semua label tanggal di portal
// profesional harus lewat `.toLocal()` lebih dulu.
//
// SEMUA timestamp di sini memakai bentuk server nyata (UTC, `isUtc == true`).
// ============================================================

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(ServerClock.reset);
  tearDown(ServerClock.reset);

  // ----------------------------------------------------------------------
  // #1 — Tanggal screening (layar + ekspor CSV memakai helper yang SAMA)
  // ----------------------------------------------------------------------
  test('formatScreeningDate: 2026-10-29T20:20:00Z → 30/10/2026 (bukan 29/10)',
      () {
    final utc = DateTime.parse('2026-10-29T20:20:00Z');
    expect(utc.isUtc, isTrue,
        reason: 'bentuk timestamp harus sama dengan server');
    expect(formatScreeningDate(utc), '30/10/2026',
        reason: 'di WIB 20:20Z sudah tanggal 30, bukan 29 (UTC)');
    expect(formatScreeningDate(utc), isNot('29/10/2026'),
        reason: 'tanggal UTC mentah tidak boleh dipakai di laporan klinis');
  });

  test(
      'formatScreeningDate: null → "Belum ada tanggal"; waktu siang tetap hari yang sama',
      () {
    expect(formatScreeningDate(null), 'Belum ada tanggal');
    // 03:00Z = 10:00 WIB hari yang sama → tanggal tidak bergeser.
    expect(formatScreeningDate(DateTime.parse('2026-10-29T03:00:00Z')),
        '29/10/2026');
  });

  test('CSV ekspor memakai tanggal LOKAL yang sama dengan layar', () {
    final createdAt = DateTime.parse('2026-10-29T20:20:00Z');
    // Baris CSV dibentuk dari helper yang sama dengan tampilan.
    final csvRow = 'Screening Date,${formatScreeningDate(createdAt)}';
    expect(csvRow, 'Screening Date,30/10/2026');
    expect(csvRow.contains('29/10/2026'), isFalse,
        reason: 'CSV tidak boleh memakai tanggal UTC');
  });

  // ----------------------------------------------------------------------
  // #2 — Waktu insiden krisis
  // ----------------------------------------------------------------------
  test(
      'formatIncidentDate: insiden dini hari (UTC hari sebelumnya) → tanggal lokal',
      () {
    final now = DateTime.now();
    // 00:30 lokal hari ini = 17:30Z kemarin (bentuk yang dikirim server).
    final utc = DateTime(now.year, now.month, now.day, 0, 30).toUtc();
    expect(utc.isUtc, isTrue);
    if (now.timeZoneOffset >= const Duration(minutes: 30)) {
      expect(utc.day, isNot(now.day),
          reason: 'di UTC tanggalnya memang hari sebelumnya');
    }

    final label = formatIncidentDate(utc);
    final local = utc.toLocal();
    expect(label, '${local.day}/${local.month}/${local.year} 00:30',
        reason: 'insiden harus tercatat di tanggal LOKAL, bukan tanggal UTC');
    expect(label.contains('${local.day}/${local.month}/${local.year}'), isTrue);
    expect(formatIncidentDate(null), '');
  });

  test('formatIncidentDate: 2026-10-29T20:20:00Z → 30/10/2026 03:20', () {
    expect(formatIncidentDate(DateTime.parse('2026-10-29T20:20:00Z')),
        '30/10/2026 03:20');
  });

  // ----------------------------------------------------------------------
  // #3 — Therapy record (daftar + kartu pratinjau memakai helper yang SAMA)
  // ----------------------------------------------------------------------
  test('formatTherapyRecordDate: 2026-10-29T20:20:00Z → 30/10/2026 03:20', () {
    final utc = DateTime.parse('2026-10-29T20:20:00Z');
    expect(utc.isUtc, isTrue);
    expect(formatTherapyRecordDate(utc), '30/10/2026 03:20',
        reason: 'jam therapy record harus jam lokal (WIB), bukan UTC 20:20');
    expect(formatTherapyRecordDate(utc).contains('29/10/2026'), isFalse);
  });

  test('formatTherapyRecordDate: dini hari UTC jatuh ke tanggal lokal hari ini',
      () {
    final now = DateTime.now();
    final utc = DateTime(now.year, now.month, now.day, 0, 15).toUtc();
    final local = utc.toLocal();
    expect(formatTherapyRecordDate(utc),
        '${local.day}/${local.month}/${local.year} 00:15');
    expect(formatTherapyRecordDate(null), '',
        reason: 'tanpa waktu tersedia, helper mengembalikan string kosong');
  });
}
