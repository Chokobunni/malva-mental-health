ALTER TABLE professional_credentials
    ADD COLUMN IF NOT EXISTS practice_locations jsonb;
