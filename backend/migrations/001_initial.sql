CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TYPE user_role AS ENUM ('patient', 'professional', 'admin');
CREATE TYPE risk_level AS ENUM ('minimal', 'mild', 'moderate', 'severe', 'crisis');
CREATE TYPE assessment_type AS ENUM ('phq9', 'gad7');
CREATE TYPE notification_status AS ENUM ('pending', 'sent', 'failed');

CREATE TABLE users (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  email text NOT NULL UNIQUE,
  password_hash text NOT NULL,
  role user_role NOT NULL,
  display_name text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  disabled_at timestamptz
);

CREATE TABLE patient_profiles (
  user_id uuid PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  date_of_birth date,
  diagnosis_summary text,
  emergency_contact jsonb NOT NULL DEFAULT '{}'::jsonb,
  privacy_mode boolean NOT NULL DEFAULT true
);

CREATE TABLE professional_profiles (
  user_id uuid PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  professional_id text NOT NULL UNIQUE,
  license_label text,
  organization text
);

CREATE TABLE patient_professional_links (
  patient_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  professional_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  status text NOT NULL DEFAULT 'active',
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (patient_id, professional_id)
);

CREATE TABLE screening_sessions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  patient_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  submitted_by uuid NOT NULL REFERENCES users(id),
  source text NOT NULL DEFAULT 'patient_app',
  is_initial boolean NOT NULL DEFAULT false,
  rule_version text NOT NULL,
  overall_level risk_level NOT NULL,
  crisis_flag boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE screening_results (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id uuid NOT NULL REFERENCES screening_sessions(id) ON DELETE CASCADE,
  type assessment_type NOT NULL,
  score integer NOT NULL CHECK (score >= 0),
  max_score integer NOT NULL CHECK (max_score > 0),
  level risk_level NOT NULL,
  summary text NOT NULL,
  crisis_flag boolean NOT NULL DEFAULT false,
  UNIQUE (session_id, type)
);

CREATE TABLE screening_answers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  result_id uuid NOT NULL REFERENCES screening_results(id) ON DELETE CASCADE,
  question_id text NOT NULL,
  score integer NOT NULL CHECK (score BETWEEN 0 AND 3),
  position integer NOT NULL CHECK (position > 0),
  UNIQUE (result_id, question_id)
);

CREATE TABLE device_tokens (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  platform text NOT NULL,
  token text NOT NULL UNIQUE,
  enabled boolean NOT NULL DEFAULT true,
  last_seen_at timestamptz NOT NULL DEFAULT now(),
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE notifications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  type text NOT NULL,
  title text NOT NULL,
  body text NOT NULL,
  data jsonb NOT NULL DEFAULT '{}'::jsonb,
  privacy_sensitive boolean NOT NULL DEFAULT true,
  status notification_status NOT NULL DEFAULT 'pending',
  created_at timestamptz NOT NULL DEFAULT now(),
  sent_at timestamptz
);

CREATE TABLE notification_outbox (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  notification_id uuid NOT NULL REFERENCES notifications(id) ON DELETE CASCADE,
  provider text NOT NULL DEFAULT 'fcm',
  attempts integer NOT NULL DEFAULT 0,
  next_attempt_at timestamptz NOT NULL DEFAULT now(),
  locked_at timestamptz,
  delivered_at timestamptz,
  last_error text,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE audit_logs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  actor_id uuid REFERENCES users(id),
  patient_id uuid REFERENCES users(id),
  action text NOT NULL,
  entity_type text NOT NULL,
  entity_id uuid,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX screening_sessions_patient_created_idx
  ON screening_sessions (patient_id, created_at DESC);

CREATE INDEX notification_outbox_ready_idx
  ON notification_outbox (next_attempt_at)
  WHERE delivered_at IS NULL;

CREATE INDEX device_tokens_user_enabled_idx
  ON device_tokens (user_id)
  WHERE enabled;
