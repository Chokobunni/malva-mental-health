-- ============================================================
-- Perbaikan jadwal dr. Hafid Algistian, Sp.KJ (a1111111)
-- ============================================================
--
-- MASALAH
--   `professional_schedules` milik a1111111 hanya menyisakan SATU hari
--   aktif (Senin). Akibatnya sisi pasien melihat "jadwal tidak ada" dan
--   tidak bisa booking pada hari lain. Akar masalahnya adalah
--   `Store.UpsertSchedules` yang menonaktifkan SEMUA baris lebih dulu lalu
--   hanya mengaktifkan ulang baris yang ada di payload (lihat commit fix
--   di backend/internal/store/prof.go).
--
-- BASELINE YANG DIMAKSUD (migrasi 007 + 008)
--   Senin–Jumat 09:00–16:00 (30 mnt) + Sabtu 09:00–12:00 (30 mnt),
--   SEMUA AKTIF — sama seperti tiga profesional demo lainnya.
--
-- SIFAT SKRIP
--   - Idempoten: aman dijalankan berulang.
--   - TIDAK menjalankan DELETE / TRUNCATE / DROP. Semua baris disimpan;
--     hanya kolom `is_active` yang diatur.
--   - Baris artefak (mis. dow=3 09:00–13:00 60 mnt) hanya DINONAKTIFKAN,
--     tidak dihapus, agar tidak menghasilkan slot tumpang tindih.
--
-- URUTAN
--   1. BACKUP dulu: pg_dump tabel professional_schedules.
--   2. Jalankan blok PREVIEW (sebelum).
--   3. Jalankan transaksi perbaikan.
--   4. Jalankan blok PREVIEW (sesudah) -> harus 6 baris aktif (dow 1–6).
--
-- Kepemilikan: tabel dimiliki `malva_app`; jalankan sebagai `malva_app`.

-- ------------------------------------------------------------
-- 0. PREVIEW sebelum perbaikan
-- ------------------------------------------------------------
SELECT day_of_week, start_time, end_time, slot_duration_minutes, is_active
  FROM professional_schedules
 WHERE professional_id = 'a1111111-1111-4111-8111-111111111111'
 ORDER BY day_of_week, start_time;

-- ------------------------------------------------------------
-- 1. EKSEKUSI (satu transaksi; ROLLBACK bila ragu)
-- ------------------------------------------------------------
BEGIN;

-- 1a. Aktifkan kembali baris baseline yang sah.
UPDATE professional_schedules
   SET is_active = true
 WHERE professional_id = 'a1111111-1111-4111-8111-111111111111'
   AND slot_duration_minutes = 30
   AND (
        (day_of_week BETWEEN 1 AND 5
         AND start_time = '09:00'::time AND end_time = '16:00'::time)
     OR (day_of_week = 6
         AND start_time = '09:00'::time AND end_time = '12:00'::time)
   );

-- 1b. Nonaktifkan baris lain (artefak) agar tidak tumpang tindih.
UPDATE professional_schedules
   SET is_active = false
 WHERE professional_id = 'a1111111-1111-4111-8111-111111111111'
   AND NOT (
        slot_duration_minutes = 30
        AND (
             (day_of_week BETWEEN 1 AND 5
              AND start_time = '09:00'::time AND end_time = '16:00'::time)
          OR (day_of_week = 6
              AND start_time = '09:00'::time AND end_time = '12:00'::time)
        )
   );

-- 1c. Ringkasan hasil: diharapkan aktif = 6 (dow 1..6), nonaktif = sisanya.
SELECT is_active, count(*) AS jumlah
  FROM professional_schedules
 WHERE professional_id = 'a1111111-1111-4111-8111-111111111111'
 GROUP BY is_active
 ORDER BY is_active;

-- Periksa hasil di atas. Bila benar -> COMMIT; bila ragu -> ROLLBACK.
COMMIT;
-- ROLLBACK;

-- ------------------------------------------------------------
-- 2. PREVIEW sesudah perbaikan (harus 6 baris aktif)
-- ------------------------------------------------------------
SELECT day_of_week, start_time, end_time, slot_duration_minutes, is_active
  FROM professional_schedules
 WHERE professional_id = 'a1111111-1111-4111-8111-111111111111'
 ORDER BY day_of_week, start_time;
