-- ============================================================
-- 016 — Earnings per sesi (kolom session_id + unique index)
-- ============================================================
-- LATAR BELAKANG
--   Keputusan pemilik produk: pendapatan profesional diakui saat SESI
--   SELESAI, bukan saat pembayaran lunas. Alasannya: sesi bisa dibatalkan
--   atau di-refund, sehingga mengakui pendapatan lebih awal memaksa koreksi
--   manual di belakang.
--
--   Supaya satu sesi tidak pernah menghasilkan dua baris earnings (misalnya
--   bila status "completed" terkirim dua kali karena tombol ditekan ganda
--   atau retry jaringan), setiap baris earnings perlu menunjuk sesi asalnya
--   dan sesi itu harus unik.
--
-- CATATAN KOMPATIBILITAS
--   Kolom session_id sengaja NULLABLE. Baris earnings lama dibuat saat
--   pembayaran lunas dan tidak punya sesi, sehingga tetap bernilai NULL.
--   Backend memperlakukan pembayaran yang sudah punya baris NULL itu sebagai
--   "pembayaran model lama" dan TIDAK membuat earnings per sesi untuknya,
--   agar tidak terjadi hitung ganda. Baris lama tidak diubah sama sekali.
--
-- Idempoten: aman dijalankan berulang seperti migrasi lain di folder ini.
-- ============================================================

ALTER TABLE earnings
  ADD COLUMN IF NOT EXISTS session_id uuid;

-- Unique parsial: banyak baris NULL boleh ada (data lama), tetapi satu sesi
-- hanya boleh muncul sekali. Ini yang menjamin idempoten di level database.
CREATE UNIQUE INDEX IF NOT EXISTS earnings_session_unique
  ON earnings (session_id)
  WHERE session_id IS NOT NULL;

-- Mempercepat pencarian pembayaran model lama (session_id IS NULL) per
-- pembayaran, dipakai setiap kali sesi diselesaikan.
CREATE INDEX IF NOT EXISTS earnings_payment_legacy_idx
  ON earnings (payment_id)
  WHERE session_id IS NULL;
