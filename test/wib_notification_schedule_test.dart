import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_test/flutter_test.dart';
import 'package:malva_mental_health/src/services/medication_reminder_service.dart';
import 'package:malva_mental_health/src/time/wib.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

// ============================================================
// REGRESI — PENGINGAT OBAT TELAT 7 JAM (zona lokal paket = UTC)
//
// Keluhan nyata pasien: "reminder obat jam 10 harus berbunyi jam 10 WIB",
// tetapi berbunyi jam 17 WIB.
//
// Akar masalah: paket `timezone` menginisialisasi zona lokal proses ke
// **Etc/UTC** (`initializeDatabase()` memanggil `setLocalLocation(_utc)`).
// Kode lama membangun jadwal dengan `tz.TZDateTime(tz.local, ..., 10, 0)`,
// sehingga yang dijadwalkan adalah **10:00 UTC = 17:00 WIB** — telat 7 jam,
// dan `matchDateTimeComponents: DateTimeComponents.time` mengulanginya tiap
// hari pada 17:00 WIB.
//
// Test ini GAGAL pada kode lama (zona lokal masih UTC, offset 0) dan LULUS
// setelah `initializeWib()` memaksa zona lokal ke Asia/Jakarta. Tidak ada satu
// pun assert di sini yang bergantung pada jam/zona mesin uji: semua instant
// dibangun dari komponen eksplisit + zona WIB.
// ============================================================

void main() {
  setUpAll(initializeWib);

  group('zona lokal proses', () {
    test('initializeWib() membuat zona lokal proses menjadi Asia/Jakarta', () {
      initializeWib();
      expect(tz.local.name, wibLocationName);
      expect(tz.local, same(wibLocation));
      // Zona lokal TIDAK boleh UTC (bawaan paket) — inilah penyebab bug.
      expect(tz.local.name, isNot('Etc/UTC'));
    });

    test(
        'initializeWib() memulihkan zona lokal ke WIB setelah database zona '
        'diinisialisasi ulang (perilaku bawaan paket = Etc/UTC)', () {
      // Meniru kode lama / pihak ketiga yang memanggil initializeTimeZones().
      tzdata.initializeTimeZones();
      expect(tz.local.name, isNot(wibLocationName),
          reason: 'prasyarat: reset database memang mengembalikan zona ke UTC');

      initializeWib();

      expect(tz.local.name, wibLocationName);
      expect(tz.local, same(wibLocation));
    });
  });

  group('jadwal pengingat obat', () {
    test('pengingat 10:00 dijadwalkan 10:00 WIB (bukan 10:00 UTC)', () {
      // "Sekarang" = 08:00 WIB tanggal 1 Nov 2026 → pengingat 10:00 hari ini.
      final now = wibFromParts(2026, 11, 1, 8, 0);

      final scheduled = MedicationReminderService.nextReminderOccurrence(
        const TimeOfDay(hour: 10, minute: 0),
        now: now,
      );

      expect(scheduled.hour, 10, reason: 'jam harus 10 WIB, bukan 17 WIB');
      expect(scheduled.minute, 0);
      expect(scheduled.timeZoneOffset, const Duration(hours: 7),
          reason: 'zona jadwal harus WIB (+07:00)');
      expect(scheduled.location.name, wibLocationName);
      expect(scheduled.year, 2026);
      expect(scheduled.month, 11);
      expect(scheduled.day, 1, reason: 'tetap hari yang sama');

      // Instant-nya: 10:00+07:00 == 03:00Z. Kalau kode lama, hasilnya 10:00Z
      // (== 17:00 WIB) sehingga pasien mendengar notifikasi 7 jam terlambat.
      expect(scheduled.toUtc(), DateTime.utc(2026, 11, 1, 3, 0));
    });

    test('bukti regresi: membangun jadwal di zona UTC menggeser 10:00 → 17:00 WIB',
        () {
      // Persis pola kode LAMA (`tz.local` saat masih UTC). Dipertahankan di
      // sini sebagai dokumentasi angka sebelum/sesudah perbaikan.
      final oldScheduled = tz.TZDateTime(tz.UTC, 2026, 11, 1, 10, 0);
      expect(toWib(oldScheduled).hour, 17,
          reason: '10:00 UTC = 17:00 WIB → telat 7 jam');

      final fixed = MedicationReminderService.nextReminderOccurrence(
        const TimeOfDay(hour: 10, minute: 0),
        now: wibFromParts(2026, 11, 1, 8, 0),
      );
      expect(fixed.hour, 10);
      expect(fixed.toUtc(), isNot(oldScheduled.toUtc()));
    });

    test('jam yang sudah lewat dijadwalkan besok, tetap 10:00 WIB', () {
      // 11:30 WIB — pengingat 10:00 hari ini sudah lewat.
      final now = wibFromParts(2026, 11, 1, 11, 30);

      final scheduled = MedicationReminderService.nextReminderOccurrence(
        const TimeOfDay(hour: 10, minute: 0),
        now: now,
      );

      expect(scheduled.day, 2, reason: 'digeser ke hari berikutnya');
      expect(scheduled.month, 11);
      expect(scheduled.year, 2026);
      expect(scheduled.hour, 10);
      expect(scheduled.minute, 0);
      expect(scheduled.timeZoneOffset, const Duration(hours: 7));
      expect(scheduled.toUtc(), DateTime.utc(2026, 11, 2, 3, 0));
    });

    test('jam yang tepat sama dengan sekarang dijadwalkan besok (bukan masa lalu)',
        () {
      final now = wibFromParts(2026, 11, 1, 10, 0);
      final scheduled = MedicationReminderService.nextReminderOccurrence(
        const TimeOfDay(hour: 10, minute: 0),
        now: now,
      );
      expect(scheduled.isAfter(now), isTrue);
      expect(scheduled.day, 2);
      expect(scheduled.hour, 10);
    });

    test('perhitungan tidak memakai jam/zona perangkat', () {
      // `wibNow()` menghasilkan wall-clock WIB berapa pun zona mesin uji.
      final nowWib = wibNow();
      expect(nowWib.timeZoneOffset, const Duration(hours: 7));
      expect(nowWib.location.name, wibLocationName);

      final scheduled = MedicationReminderService.nextReminderOccurrence(
        const TimeOfDay(hour: 10, minute: 0),
        now: nowWib,
      );
      expect(scheduled.hour, 10);
      expect(scheduled.minute, 0);
      expect(scheduled.timeZoneOffset, const Duration(hours: 7));
      // Wall-clock UTC dari instant yang sama selalu 7 jam "di belakang" WIB.
      final utcWall = scheduled.toUtc();
      expect(utcWall.hour, (scheduled.hour - 7) % 24);
      expect(utcWall.minute, scheduled.minute);
    });

    test('rollover akhir bulan: 31 Oktober → 1 November (bukan error)', () {
      // 31 Okt 2026 11:00 WIB — pengingat 10:00 sudah lewat, jadi "besok"
      // dibangun dengan `day + 1` = 32. Normalisasi kalender WAJIB menghasilkan
      // 1 November, bukan exception / tanggal tidak sah.
      final now = wibFromParts(2026, 10, 31, 11, 0);

      final scheduled = MedicationReminderService.nextReminderOccurrence(
        const TimeOfDay(hour: 10, minute: 0),
        now: now,
      );

      expect(scheduled.year, 2026);
      expect(scheduled.month, 11, reason: '32 Okt harus normal jadi 1 Nov');
      expect(scheduled.day, 1);
      expect(scheduled.hour, 10);
      expect(scheduled.minute, 0);
      expect(scheduled.timeZoneOffset, const Duration(hours: 7));
      expect(scheduled.toUtc(), DateTime.utc(2026, 11, 1, 3, 0));
    });

    test('rollover pergantian tahun: 31 Desember → 1 Januari tahun berikutnya',
        () {
      final now = wibFromParts(2026, 12, 31, 11, 0);

      final scheduled = MedicationReminderService.nextReminderOccurrence(
        const TimeOfDay(hour: 10, minute: 0),
        now: now,
      );

      expect(scheduled.year, 2027, reason: 'tahun harus naik');
      expect(scheduled.month, 1);
      expect(scheduled.day, 1);
      expect(scheduled.hour, 10);
      expect(scheduled.timeZoneOffset, const Duration(hours: 7));
      expect(scheduled.toUtc(), DateTime.utc(2027, 1, 1, 3, 0));
    });

    test('rollover 29 Februari tahun kabisat → 1 Maret', () {
      final now = wibFromParts(2028, 2, 29, 23, 30);

      final scheduled = MedicationReminderService.nextReminderOccurrence(
        const TimeOfDay(hour: 10, minute: 0),
        now: now,
      );

      expect(scheduled.year, 2028);
      expect(scheduled.month, 3);
      expect(scheduled.day, 1);
      expect(scheduled.hour, 10);
      expect(scheduled.toUtc(), DateTime.utc(2028, 3, 1, 3, 0));
    });

    test('push notification: konversi instant UTC ke WIB memakai wibLocation',
        () {
      // Pola yang dipakai PushNotificationService.showLocalNotification.
      final scheduledTime = DateTime.utc(2026, 11, 1, 3, 0);
      final tzScheduled = tz.TZDateTime.from(scheduledTime, wibLocation);
      expect(tzScheduled.hour, 10);
      expect(tzScheduled.minute, 0);
      expect(tzScheduled.timeZoneOffset, const Duration(hours: 7));
    });
  });
}
