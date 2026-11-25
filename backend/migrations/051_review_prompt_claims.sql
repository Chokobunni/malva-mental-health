CREATE TABLE IF NOT EXISTS review_prompt_claims (
  patient_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  unit_id uuid NOT NULL,
  unit_type text NOT NULL CHECK (unit_type IN ('session', 'package')),
  claim_id uuid NOT NULL,
  PRIMARY KEY (patient_id, unit_id, unit_type)
);
