-- ============================================================
-- 014 — Cegah baris jadwal duplikat (unique index)
-- ============================================================
--
-- LATAR BELAKANG
--   `professional_schedules` tidak punya unique constraint selain PK `id`,
--   sehingga kombinasi (professional_id, day_of_week, start_time, end_time)
--   bisa berisi banyak baris. Terbukti di produksi: profesional
--   `a1111111-...` punya 27 baris untuk 7 kunci unik (20 duplikat).
--
--   Dampaknya nyata: `UpsertSchedules` (backend/internal/store/prof.go)
--   melakukan dedup payload dengan kunci `dow|start|end` dan
--   **entri terakhir menang**, sehingga tombol Nonaktifkan/Aktifkan
--   diam-diam dibatalkan oleh baris duplikat.
--
-- URUTAN (WAJIB)
--   1. Bersihkan duplikat lebih dulu:
--      `psql "$MALVA_DATABASE_URL" -f backend/admin_scripts/fix_duplicate_schedules.sql`
--   2. Baru jalankan migrasi ini. Bila masih ada duplikat, CREATE INDEX
--      akan GAGAL (dan itu memang yang kita inginkan — jangan dipaksa).
--
-- Kepemilikan: tabel dimiliki `malva_app`, jadi migrasi ini cukup
-- dijalankan sebagai `malva_app` (tidak butuh role admin `malva`).

-- Gagalkan lebih awal dengan pesan jelas bila masih ada duplikat.
DO $$
DECLARE
  dup_count integer;
BEGIN
  SELECT count(*) INTO dup_count
  FROM (
    SELECT professional_id, day_of_week, start_time, end_time
    FROM professional_schedules
    GROUP BY professional_id, day_of_week, start_time, end_time
    HAVING count(*) > 1
  ) d;

  IF dup_count > 0 THEN
    RAISE EXCEPTION
      'Masih ada % kombinasi jadwal duplikat. Jalankan backend/admin_scripts/fix_duplicate_schedules.sql lebih dulu.',
      dup_count;
  END IF;
END $$;

-- Idempoten: hanya dibuat bila belum ada.
CREATE UNIQUE INDEX IF NOT EXISTS professional_schedules_unique_slot
  ON professional_schedules (professional_id, day_of_week, start_time, end_time);

-- Verifikasi: harus menampilkan index professional_schedules_unique_slot.
SELECT indexname, indexdef
FROM pg_indexes
WHERE tablename = 'professional_schedules'
ORDER BY indexname;
