CREATE TABLE IF NOT EXISTS clinical_allergies (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  patient_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  reaction_type text NOT NULL CHECK (reaction_type IN ('allergy', 'side_effect')),
  substance text NOT NULL CHECK (octet_length(substance) BETWEEN 1 AND 240),
  symptoms text NOT NULL CHECK (octet_length(symptoms) BETWEEN 1 AND 2000),
  severity text NOT NULL CHECK (severity IN ('mild', 'moderate', 'high')),
  occurred_when text NOT NULL DEFAULT '' CHECK (octet_length(occurred_when) <= 240),
  reported_by text NOT NULL CHECK (reported_by IN ('patient', 'professional')),
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS clinical_allergies_patient_created_idx
  ON clinical_allergies (patient_id, created_at DESC, id DESC);
