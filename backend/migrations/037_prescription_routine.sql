-- Persist professional routines and supply; legacy medication times remain valid.
ALTER TABLE medications ADD COLUMN IF NOT EXISTS schedule jsonb NOT NULL DEFAULT '{}'::jsonb;
ALTER TABLE e_prescription_items ADD COLUMN IF NOT EXISTS schedule jsonb NOT NULL DEFAULT '{}'::jsonb;
ALTER TABLE e_prescription_items ADD COLUMN IF NOT EXISTS current_stock integer NOT NULL DEFAULT 0 CHECK (current_stock >= 0);
ALTER TABLE e_prescription_items ADD COLUMN IF NOT EXISTS alert_below integer NOT NULL DEFAULT 3 CHECK (alert_below >= 0);
