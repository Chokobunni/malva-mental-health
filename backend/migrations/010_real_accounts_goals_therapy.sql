-- Migration 010: Real accounts & admin, goals/habits, therapy, diary detail, chat share.
-- Semua idempotent (IF NOT EXISTS) agar aman dijalankan ulang.

-- 1. SSO: satu akun sosial hanya untuk satu user.
CREATE UNIQUE INDEX IF NOT EXISTS users_sso_unique
  ON users (sso_provider, sso_id)
  WHERE sso_provider IS NOT NULL AND sso_id IS NOT NULL;

-- 2. Diary History (Figma): mood check-in diperkaya agar satu baris riwayat
-- memuat mood + gejala + tidur + obat + catatan + feedback dokter.
ALTER TABLE mood_checkins
  ADD COLUMN IF NOT EXISTS medication_taken BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE mood_checkins
  ADD COLUMN IF NOT EXISTS professional_feedback TEXT NOT NULL DEFAULT '';
ALTER TABLE mood_checkins
  ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT now();
ALTER TABLE mood_checkins
  ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;

-- 3. Goals & Habits: tersimpan di server, tidak hilang saat restart aplikasi.
CREATE TABLE IF NOT EXISTS goals (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  patient_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  title text NOT NULL,
  category text NOT NULL DEFAULT 'general',
  target_per_week integer NOT NULL DEFAULT 3,
  is_active boolean NOT NULL DEFAULT true,
  sort_order integer NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS goals_patient_idx
  ON goals (patient_id, is_active, sort_order);

CREATE TABLE IF NOT EXISTS habit_logs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  goal_id uuid NOT NULL REFERENCES goals(id) ON DELETE CASCADE,
  patient_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  logged_date date NOT NULL DEFAULT CURRENT_DATE,
  done boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (goal_id, logged_date)
);
CREATE INDEX IF NOT EXISTS habit_logs_patient_idx
  ON habit_logs (patient_id, logged_date DESC);

-- 4. Therapy: hasil worksheet pasien per modul, bisa dibagikan & diunduh.
CREATE TABLE IF NOT EXISTS therapy_submissions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  patient_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  module_id text NOT NULL,
  title text NOT NULL DEFAULT '',
  answers jsonb NOT NULL DEFAULT '{}'::jsonb,
  summary text NOT NULL DEFAULT '',
  shared_with_professional_id uuid REFERENCES users(id) ON DELETE SET NULL,
  shared_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS therapy_submissions_patient_idx
  ON therapy_submissions (patient_id, created_at DESC);

-- 5. Chat share: jenis pesan terstruktur (summary/assessment/resep/goals/diary).
ALTER TABLE chat_messages
  ADD COLUMN IF NOT EXISTS kind VARCHAR(20) NOT NULL DEFAULT 'text';

-- 6. Continuous care 7 hari: tanpa slot jam spesifik (async), jadi boleh NULL.
ALTER TABLE bookings ALTER COLUMN slot_time DROP NOT NULL;
