-- 024_google_refresh_token_grant.sql
-- Kapan refresh token Google terakhir DITERBITKAN (grant) oleh profesional.
--
-- Kenapa kolom ini TERPISAH dari updated_at:
--   `updated_at` pada google_oauth_tokens ditulis ulang pada SETIAP pemanggilan
--   UpsertGoogleToken — termasuk auto-refresh access token jangka pendek di
--   internal/google/calendar.go. Akibatnya updated_at BUKAN tanggal grant, dan
--   tidak bisa dipakai menghitung umur refresh token. Umur refresh token-lah
--   yang menentukan kapan izin berakhir (consent screen Google masih "Testing"
--   -> refresh token hanya berlaku 7 hari). Karena itu dibutuhkan kolom khusus
--   yang HANYA berubah saat grant baru terjadi (penukaran authorization code),
--   bukan saat access token di-refresh.
--
-- Idempoten: ADD COLUMN IF NOT EXISTS + backfill bersyarat, aman dijalankan
-- berulang.

ALTER TABLE google_oauth_tokens
    ADD COLUMN IF NOT EXISTS refresh_token_issued_at timestamptz;

-- Backfill perkiraan terbaik untuk baris lama: pakai updated_at sebagai
-- pendekatan (di produksi tabel ini kosong, jadi backfill hanya untuk data uji).
UPDATE google_oauth_tokens
    SET refresh_token_issued_at = updated_at
    WHERE refresh_token_issued_at IS NULL;
