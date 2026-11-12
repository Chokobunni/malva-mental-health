-- Additive goal configuration and independent habit progress. Existing goals
-- remain legacy yes/no habits (details NULL); their history is untouched.
ALTER TABLE goals ADD COLUMN IF NOT EXISTS details jsonb;
ALTER TABLE habit_logs ADD COLUMN IF NOT EXISTS value integer NOT NULL DEFAULT 0;
ALTER TABLE habit_logs ADD COLUMN IF NOT EXISTS completed_step_ids jsonb NOT NULL DEFAULT '[]'::jsonb;
