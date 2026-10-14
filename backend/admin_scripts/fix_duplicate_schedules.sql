-- ============================================================
-- Perbaikan baris jadwal DUPLIKAT pada professional_schedules
-- ============================================================
--
-- MASALAH
--   `a1111111-1111-4111-8111-111111111111` punya 27 baris jadwal,
--   padahal hanya 7 kombinasi unik (day_of_week, start_time, end_time).
--   -> 20 baris duplikat.
--
-- Kenapa ini merusak tombol Nonaktifkan/Aktifkan?
--   `UpsertSchedules` (backend/internal/store/prof.go) melakukan dedup
--   payload dengan kunci `day_of_week|start_time|end_time` dan
--   **entri terakhir menang** (`seen[key] = sch` tanpa syarat).
--   Saat ada duplikat, payload memuat >1 entri untuk kunci yang sama;
--   entri terakhir menimpa yang dibalik tombol, sehingga toggle
--   DIAM-DIAM DIBATALKAN. Sudah dibuktikan:
--     a2222222 (6 baris, 0 duplikat) -> toggle PERSIST
--     a1111111 (27 baris, 20 duplikat) -> toggle TIDAK PERSIST
--   Selain itu UPDATE pada upsert tidak pakai LIMIT, jadi seluruh baris
--   dengan kunci sama selalu dipaksa bernilai sama.
--
-- STRATEGI PERBAIKAN (aman, non-destruktif terhadap makna data)
--   Simpan SATU baris per kunci, yaitu baris dengan `created_at`
--   paling awal (deterministik). Nilai `is_active` yang dipertahankan
--   adalah nilai baris yang disimpan — jadi tidak ada niat data yang
--   diubah, hanya duplikat yang dibuang.
--
-- URUTAN PEMAKAIAN
--   1. Jalankan BACKUP dulu (lihat README_ADMIN_DATABASE / pg_dump).
--   2. Jalankan blok PREVIEW -> periksa hasilnya.
--   3. Jalankan blok EKSEKUSI di dalam transaksi.
--   4. Jalankan blok VERIFIKASI -> harus 0 duplikat.
--   5. Setelah bersih, pasang migrasi 014 (unique index) agar tidak terulang.
--
-- Catatan: tabel dimiliki role `malva_app`, jadi skrip ini BISA dijalankan
-- sebagai `malva_app` (tidak butuh role admin `malva`).

-- ------------------------------------------------------------
-- 1. PREVIEW: baris yang AKAN dihapus (jalankan dulu, jangan hapus)
-- ------------------------------------------------------------
WITH ranked AS (
  SELECT id,
         professional_id,
         day_of_week,
         start_time,
         end_time,
         is_active,
         created_at,
         ROW_NUMBER() OVER (
           PARTITION BY professional_id, day_of_week, start_time, end_time
           ORDER BY created_at, id
         ) AS rn
  FROM professional_schedules
)
SELECT professional_id, day_of_week, start_time, end_time, is_active, created_at, id
FROM ranked
WHERE rn > 1
ORDER BY professional_id, day_of_week, start_time, end_time, created_at;

-- ------------------------------------------------------------
-- 2. EKSEKUSI: hapus duplikat (simpan rn = 1)
--    Jalankan sebagai satu transaksi agar bisa di-ROLLBACK bila ragu.
-- ------------------------------------------------------------
BEGIN;

WITH ranked AS (
  SELECT id,
         ROW_NUMBER() OVER (
           PARTITION BY professional_id, day_of_week, start_time, end_time
           ORDER BY created_at, id
         ) AS rn
  FROM professional_schedules
)
DELETE FROM professional_schedules ps
USING ranked r
WHERE ps.id = r.id
  AND r.rn > 1;

-- Ringkasan setelah penghapusan
SELECT professional_id,
       count(*) AS total_baris,
       count(*) - count(DISTINCT (day_of_week, start_time, end_time)) AS sisa_duplikat
FROM professional_schedules
GROUP BY professional_id
ORDER BY professional_id;

-- Periksa hasil di atas: `sisa_duplikat` harus 0 untuk semua profesional.
-- Bila sudah benar -> COMMIT; bila ragu -> ROLLBACK.
COMMIT;
-- ROLLBACK;

-- ------------------------------------------------------------
-- 3. VERIFIKASI: harus mengembalikan 0 baris
-- ------------------------------------------------------------
SELECT professional_id, day_of_week, start_time, end_time, count(*)
FROM professional_schedules
GROUP BY professional_id, day_of_week, start_time, end_time
HAVING count(*) > 1
ORDER BY 1, 2, 3, 4;
