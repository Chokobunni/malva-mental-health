-- Preserve prescription editing without deleting clinical history.
ALTER TABLE e_prescriptions ADD COLUMN IF NOT EXISTS diagnosis text NOT NULL DEFAULT '';
ALTER TABLE e_prescription_items ADD COLUMN IF NOT EXISTS active boolean NOT NULL DEFAULT true;
