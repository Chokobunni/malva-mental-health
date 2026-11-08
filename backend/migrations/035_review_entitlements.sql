-- Legacy reviews remain unlinked; no guessed historical associations or deletion.
ALTER TABLE doctor_reviews ADD COLUMN IF NOT EXISTS session_id uuid;
ALTER TABLE doctor_reviews ADD COLUMN IF NOT EXISTS care_package_id uuid;
CREATE UNIQUE INDEX IF NOT EXISTS doctor_reviews_session_uidx
  ON doctor_reviews(session_id) WHERE session_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS doctor_reviews_care_package_uidx
  ON doctor_reviews(care_package_id) WHERE care_package_id IS NOT NULL;
DO $$ BEGIN
  ALTER TABLE doctor_reviews ADD CONSTRAINT doctor_reviews_one_entitlement
    CHECK (session_id IS NULL OR care_package_id IS NULL);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
