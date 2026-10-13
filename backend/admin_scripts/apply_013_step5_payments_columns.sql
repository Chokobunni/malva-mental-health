-- 013 — LANGKAH 5 (kolom gateway pada tabel `payments`).
--
-- PENTING: tabel `payments` dimiliki role admin `malva`, sedangkan aplikasi
-- berjalan sebagai `malva_app`. `malva_app` BUKAN member dari `malva`
-- (pg_has_role('malva_app','malva','USAGE') = false), jadi:
--   ERROR: must be owner of table payments
-- Langkah 1-4 migrasi 013 (care_refunds, payment_events, refunded_amount,
-- cancelled_by) sudah terpasang dan bisa dijalankan sebagai `malva_app`.
-- Langkah 5 ini HARUS dijalankan sebagai role `malva`.
--
-- Cara menjalankan (pilih salah satu):
--   A. Azure Portal -> PostgreSQL Flexible Server -> Query editor, tempel isi file ini.
--   B. psql "<URL admin malva>" -X -v ON_ERROR_STOP=1 -1 -f apply_013_step5_payments_columns.sql
--
-- Dibutuhkan hanya bila MALVA_PAYMENT_MODE=gateway (Midtrans) diaktifkan.
-- Di mode simulation (default) kolom ini tidak pernah ditulis/dibaca.

ALTER TABLE payments ADD COLUMN IF NOT EXISTS gateway      text NOT NULL DEFAULT '';
ALTER TABLE payments ADD COLUMN IF NOT EXISTS snap_token   text NOT NULL DEFAULT '';
ALTER TABLE payments ADD COLUMN IF NOT EXISTS redirect_url text NOT NULL DEFAULT '';

-- Verifikasi: harus keluar 3 baris.
SELECT column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_name = 'payments'
  AND column_name IN ('gateway', 'snap_token', 'redirect_url')
ORDER BY column_name;
