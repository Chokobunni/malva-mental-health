-- Migration 017: Google Meet integration + OAuth token storage
-- Idempoten: aman dijalankan ulang.

-- Kolom untuk melacak event Google Calendar yang terkait sesi video.
-- Digunakan saat reschedule/cancel agar event di kalender ikut diperbarui.
ALTER TABLE care_sessions ADD COLUMN IF NOT EXISTS google_event_id text NOT NULL DEFAULT '';

-- Penyimpanan refresh token Google OAuth per profesional.
-- Token ini dipakai server-side untuk membuat event Calendar + link Meet
-- atas nama profesional (menggunakan akun Gmail pribadinya).
CREATE TABLE IF NOT EXISTS google_oauth_tokens (
  user_id       uuid PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  refresh_token text NOT NULL,
  access_token  text NOT NULL DEFAULT '',
  token_expiry  timestamptz NOT NULL DEFAULT now(),
  scope         text NOT NULL DEFAULT '',
  updated_at    timestamptz NOT NULL DEFAULT now()
);
