import 'package:flutter_test/flutter_test.dart';

import 'package:malva_mental_health/src/screens/assessment_history_screen.dart';
import 'package:malva_mental_health/src/screens/mood_screen.dart';
import 'package:malva_mental_health/src/screens/record_screen.dart';
import 'package:malva_mental_health/src/services/server_clock.dart';
import 'package:malva_mental_health/src/time/wib.dart';

// ============================================================
// REGRESI ZONA WAKTU — LAYAR PASIEN (N1–N3)
//
// Semua nilai waktu di bawah berasal dari server dan berbentuk UTC
// (`DateTime.parse('...Z')` / `.toUtc()`), persis seperti yang dikirim
// backend Go. Tanpa `.toLocal()`, dini hari WIB tampil sebagai kemarin.
// ============================================================

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(ServerClock.reset);
  tearDown(ServerClock.reset);

  // ----------------------------------------------------------------------
  // N1 — Kalender mood
  // ----------------------------------------------------------------------
  test('formatMoodCalendarDate: 2026-10-29T20:20:00Z → 30 Oktober 2026', () {
    final utc = DateTime.parse('2026-10-29T20:20:00Z');
    expect(utc.isUtc, isTrue,
        reason: 'bentuk timestamp harus sama dengan server');

    final label = formatMoodCalendarDate(utc);
    expect(label, '30 Oktober 2026',
        reason: 'di WIB 20:20Z sudah tanggal 30, bukan 29 (UTC)');
    expect(label.contains('29 Oktober'), isFalse,
        reason: 'tanggal UTC mentah tidak boleh tampil di kalender mood');
  });

  test(
      'formatMoodCalendarDate: check-in dini hari (UTC kemarin) tetap hari ini',
      () {
    final now = wibNow();
    // 00:30 wall-clock WIB hari ini = 17:30Z kemarin.
    final utc = wibFromParts(now.year, now.month, now.day, 0, 30).toUtc();
    if (now.timeZoneOffset >= const Duration(minutes: 30)) {
      expect(utc.day, isNot(now.day),
          reason: 'di UTC tanggalnya memang hari sebelumnya');
    }
    const months = [
      'Januari',
      'Februari',
      'Maret',
      'April',
      'Mei',
      'Juni',
      'Juli',
      'Agustus',
      'September',
      'Oktober',
      'November',
      'Desember'
    ];
    expect(formatMoodCalendarDate(utc),
        '${now.day} ${months[now.month - 1]} ${now.year}');
  });

  // ----------------------------------------------------------------------
  // N2 — Tanggal + jam assessment record
  // ----------------------------------------------------------------------
  test('formatAssessmentDate: 2026-10-29T20:20:00Z → 30/10/2026 03:20', () {
    final utc = DateTime.parse('2026-10-29T20:20:00Z');
    final label = formatAssessmentDate(utc);
    expect(label, '30/10/2026 03:20',
        reason: 'harus tanggal + jam LOKAL (WIB = UTC+7)');
    expect(label.contains('29/10/2026'), isFalse,
        reason: 'tanggal UTC mentah tidak boleh tampil');
    expect(label.contains('20:20'), isFalse,
        reason: 'jam UTC mentah tidak boleh tampil');
  });

  test('formatAssessmentDate: entri lokal (DateTime.now) tidak berubah', () {
    final now = wibNow();
    String two(int value) => value.toString().padLeft(2, '0');
    final expected = '${two(now.day)}/${two(now.month)}/${now.year} '
        '${two(now.hour)}:${two(now.minute)}';
    expect(formatAssessmentDate(now), expected,
        reason: '.toLocal() idempoten untuk waktu lokal — tidak ada regresi');
  });

  test('formatAssessmentDate: null → "Tanggal tidak tercatat"', () {
    expect(formatAssessmentDate(null), 'Tanggal tidak tercatat');
  });

  // ----------------------------------------------------------------------
  // N3 — Label "Diperbarui" health record
  //
  // Dipilih uji unit (bukan widget test RecordScreen): layar itu memerlukan
  // apiClient + provider + pemuatan server, sehingga widget test akan rapuh
  // dan tidak menambah bukti kebenaran tanggal. Helper-nya sudah publik.
  // ----------------------------------------------------------------------
  test('formatHealthRecordUpdatedDate: timestamp UTC dini hari → tanggal lokal',
      () {
    final now = wibNow();
    final utc = wibFromParts(now.year, now.month, now.day, 0, 30).toUtc();
    expect(utc.isUtc, isTrue);
    if (now.timeZoneOffset >= const Duration(minutes: 30)) {
      expect(utc.day, isNot(now.day),
          reason: 'di UTC tanggalnya memang hari sebelumnya');
    }
    expect(formatHealthRecordUpdatedDate(utc),
        '${now.day}/${now.month}/${now.year}',
        reason: 'label "Diperbarui" harus tanggal LOKAL, bukan tanggal UTC');
  });

  test('formatHealthRecordUpdatedDate: 2026-10-29T20:20:00Z → 30/10/2026', () {
    final label =
        formatHealthRecordUpdatedDate(DateTime.parse('2026-10-29T20:20:00Z'));
    expect(label, '30/10/2026');
    expect(label, isNot('29/10/2026'));
    expect(formatHealthRecordUpdatedDate(null), '');
  });
}
