ALTER TABLE professional_pricing
  ADD COLUMN IF NOT EXISTS patient_capacity integer CHECK (patient_capacity >= 0);
