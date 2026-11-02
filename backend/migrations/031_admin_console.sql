-- 031_admin_console.sql
-- Indeks pendukung konsol admin (dashboard Flutter web): daftar transaksi,
-- ringkasan pendapatan bulanan, ledger refund, dan daftar pengguna per role.
--
-- Aturan: TANPA kolom baru (skema tidak berubah), seluruh pernyataan idempoten
-- (IF NOT EXISTS / dijaga to_regclass). Hanya menambah indeks baca agar query
-- konsol admin tidak memindai seluruh tabel.

-- 1. Riwayat pembayaran admin: filter status + urut created_at menurun.
CREATE INDEX IF NOT EXISTS payments_status_created_idx
  ON payments (status, created_at DESC);

-- 2. Ringkasan pendapatan bulan berjalan (SUM gross_amount status 'paid').
CREATE INDEX IF NOT EXISTS payments_paid_at_idx
  ON payments (paid_at DESC)
  WHERE status = 'paid';

-- 3. Daftar pengguna admin: filter per role.
CREATE INDEX IF NOT EXISTS users_role_idx
  ON users (role);

-- 4. Ledger refund admin (created_at menurun). Dijaga to_regclass agar DB lama
--    yang belum punya tabel care_refunds tidak menggagalkan migrasi.
DO $$
BEGIN
  IF to_regclass('public.care_refunds') IS NOT NULL THEN
    CREATE INDEX IF NOT EXISTS care_refunds_created_idx
      ON care_refunds (created_at DESC);
  END IF;
END $$;

-- 5. Hitungan sesi "hari ini" di beranda admin (status + jadwal).
DO $$
BEGIN
  IF to_regclass('public.care_sessions') IS NOT NULL THEN
    CREATE INDEX IF NOT EXISTS care_sessions_status_scheduled_idx
      ON care_sessions (status, scheduled_at);
  END IF;
END $$;
