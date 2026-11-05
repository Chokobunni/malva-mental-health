-- Independent self-reported attendance. Legacy attended_marked_at remains
-- untouched: it cannot establish which participant attended.
ALTER TABLE care_sessions
  ADD COLUMN IF NOT EXISTS patient_attendance text NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS professional_attendance text NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS patient_attendance_marked_at timestamptz,
  ADD COLUMN IF NOT EXISTS professional_attendance_marked_at timestamptz;

DO $$ BEGIN
  ALTER TABLE care_sessions ADD CONSTRAINT care_sessions_patient_attendance_check
    CHECK (patient_attendance IN ('', 'attended', 'absent'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
  ALTER TABLE care_sessions ADD CONSTRAINT care_sessions_professional_attendance_check
    CHECK (professional_attendance IN ('', 'attended', 'absent'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
