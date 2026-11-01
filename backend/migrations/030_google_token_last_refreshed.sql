-- 030_google_token_last_refreshed.sql
-- Catat refresh sukses atomik dengan access token/expiry. Pemeliharaan paling
-- lambat tujuh hari; access token hampir habis tetap diperbarui lebih cepat.
-- Baris lama NULL langsung memenuhi syarat refresh pada tick berikutnya.
ALTER TABLE google_oauth_tokens
    ADD COLUMN IF NOT EXISTS last_refreshed_at timestamptz;

-- Peringatan token Google dihapus sepenuhnya, termasuk push yang masih antre
-- dan notifikasi in-app lama. Jenis notifikasi lain tidak disentuh. Idempoten.
DELETE FROM notification_outbox
WHERE notification_id IN (
    SELECT id FROM notifications WHERE type = 'google_calendar_expiring'
);
DELETE FROM notifications WHERE type = 'google_calendar_expiring';
