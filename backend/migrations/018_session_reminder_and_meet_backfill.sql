-- Migration 018: pengingat sesi video
-- Idempoten: aman dijalankan ulang.

-- Kapan pengingat "sesi sebentar lagi" dikirim. NULL = belum dikirim.
-- Sweeper backend mengisi kolom ini agar pengingat tidak terkirim dua kali.
ALTER TABLE care_sessions ADD COLUMN IF NOT EXISTS reminder_sent_at timestamptz;

-- Kapan link Google Meet terakhir dibuat/di-generate ulang. Berguna untuk
-- audit bila profesional melaporkan link tidak berfungsi.
ALTER TABLE care_sessions ADD COLUMN IF NOT EXISTS meeting_link_created_at timestamptz;

-- Percepat query sweeper: sesi terjadwal yang belum dikirimi pengingat.
CREATE INDEX IF NOT EXISTS idx_care_sessions_reminder
  ON care_sessions (scheduled_at)
  WHERE status = 'scheduled' AND reminder_sent_at IS NULL;

-- Percepat pencarian sesi video yang belum punya link Google Meet (backfill).
-- Tidak memfilter kolom meeting_url karena backfill juga mencakup link dari
-- penyedia lama yang perlu diganti (predikat NOT LIKE tidak cocok dengan
-- partial index pada meeting_url).
CREATE INDEX IF NOT EXISTS idx_care_sessions_meet_backfill
  ON care_sessions (scheduled_at)
  WHERE session_type = 'video' AND status = 'scheduled';
