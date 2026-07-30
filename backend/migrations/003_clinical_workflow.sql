CREATE TABLE IF NOT EXISTS screening_reviews (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  screening_session_id uuid NOT NULL REFERENCES screening_sessions(id) ON DELETE CASCADE,
  patient_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  professional_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  status text NOT NULL DEFAULT 'reviewed' CHECK (status IN ('reviewed', 'needs_follow_up', 'closed')),
  note text NOT NULL DEFAULT '',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (screening_session_id, professional_id)
);

CREATE INDEX IF NOT EXISTS screening_reviews_patient_idx
  ON screening_reviews (patient_id, updated_at DESC);

CREATE TABLE IF NOT EXISTS professional_notes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  patient_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  professional_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  body text NOT NULL,
  visibility text NOT NULL DEFAULT 'private' CHECK (visibility IN ('private', 'shared_with_patient')),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  archived_at timestamptz
);

CREATE INDEX IF NOT EXISTS professional_notes_patient_idx
  ON professional_notes (patient_id, updated_at DESC)
  WHERE archived_at IS NULL;

CREATE TABLE IF NOT EXISTS follow_up_messages (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  patient_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  professional_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  body text NOT NULL,
  status text NOT NULL DEFAULT 'sent' CHECK (status IN ('draft', 'sent')),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  read_at timestamptz,
  archived_at timestamptz
);

CREATE INDEX IF NOT EXISTS follow_up_messages_patient_idx
  ON follow_up_messages (patient_id, created_at DESC)
  WHERE archived_at IS NULL;

CREATE TABLE IF NOT EXISTS mood_checkins (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  patient_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  mood text NOT NULL,
  sleep_hours numeric(4,1) NOT NULL DEFAULT 0,
  energy integer NOT NULL CHECK (energy BETWEEN 0 AND 10),
  anxiety integer NOT NULL CHECK (anxiety BETWEEN 0 AND 10),
  irritability integer NOT NULL CHECK (irritability BETWEEN 0 AND 10),
  note text NOT NULL DEFAULT '',
  occurred_at timestamptz NOT NULL DEFAULT now(),
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS mood_checkins_patient_idx
  ON mood_checkins (patient_id, occurred_at DESC);

CREATE TABLE IF NOT EXISTS diary_entries (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  patient_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  mood text NOT NULL,
  title text NOT NULL,
  note text NOT NULL,
  shared_with_professionals boolean NOT NULL DEFAULT true,
  professional_feedback text,
  occurred_at timestamptz NOT NULL DEFAULT now(),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  deleted_at timestamptz
);

CREATE INDEX IF NOT EXISTS diary_entries_patient_idx
  ON diary_entries (patient_id, occurred_at DESC)
  WHERE deleted_at IS NULL;

CREATE TABLE IF NOT EXISTS medications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  patient_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  name text NOT NULL,
  dosage text NOT NULL,
  form text NOT NULL,
  reminder_time text NOT NULL DEFAULT '',
  relation_to_meal text NOT NULL DEFAULT '',
  current_stock integer NOT NULL DEFAULT 0 CHECK (current_stock >= 0),
  alert_below integer NOT NULL DEFAULT 0 CHECK (alert_below >= 0),
  source text NOT NULL DEFAULT 'patient',
  active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS medications_patient_idx
  ON medications (patient_id, updated_at DESC)
  WHERE active;

CREATE TABLE IF NOT EXISTS medication_logs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  patient_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  medication_id uuid REFERENCES medications(id) ON DELETE SET NULL,
  medication_name text NOT NULL,
  status text NOT NULL DEFAULT 'taken' CHECK (status IN ('taken', 'missed', 'skipped')),
  taken_at timestamptz NOT NULL DEFAULT now(),
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS medication_logs_patient_idx
  ON medication_logs (patient_id, taken_at DESC);

CREATE TABLE IF NOT EXISTS patient_data_consents (
  patient_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  professional_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  share_screenings boolean NOT NULL DEFAULT true,
  share_mood_diary boolean NOT NULL DEFAULT true,
  share_medications boolean NOT NULL DEFAULT true,
  share_timeline boolean NOT NULL DEFAULT true,
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (patient_id, professional_id)
);

CREATE INDEX IF NOT EXISTS audit_logs_patient_created_idx
  ON audit_logs (patient_id, created_at DESC);
