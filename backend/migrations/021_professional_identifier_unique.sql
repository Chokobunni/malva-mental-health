-- Each nonempty STR and SIP is unique within its own kind.
-- Existing normalized duplicates must be resolved before this migration can apply.
CREATE UNIQUE INDEX IF NOT EXISTS professional_credentials_str_uidx
    ON professional_credentials (lower(btrim(str_number)))
    WHERE str_number IS NOT NULL AND btrim(str_number) <> '';

CREATE UNIQUE INDEX IF NOT EXISTS professional_credentials_sip_uidx
    ON professional_credentials (lower(btrim(sip_number)))
    WHERE sip_number IS NOT NULL AND btrim(sip_number) <> '';

ALTER TABLE users ADD COLUMN IF NOT EXISTS sso_linked_at TIMESTAMPTZ;
ALTER TABLE users ADD COLUMN IF NOT EXISTS sso_email VARCHAR(255);

-- Legacy Calendar grants have no verified subject and must be authorized again.
ALTER TABLE google_oauth_tokens ADD COLUMN IF NOT EXISTS google_subject VARCHAR(255);

CREATE UNIQUE INDEX IF NOT EXISTS users_sso_email_uidx
    ON users (lower(btrim(sso_email)))
    WHERE sso_email IS NOT NULL AND btrim(sso_email) <> '';

-- Only Google-created professional placeholders have a known Google email.
-- Legacy password accounts may have bound a different email; leave it unknown
-- until a verified Google login or bind supplies it. Do not invent link dates.
UPDATE users u
SET sso_email = lower(btrim(u.email))
FROM professional_profiles pp
WHERE pp.user_id = u.id
  AND pp.professional_id = left('g-' || u.sso_id, 30)
  AND u.sso_provider = 'google' AND btrim(u.sso_id) <> ''
  AND u.sso_email IS NULL AND btrim(u.email) <> ''
  AND lower(btrim(u.email)) NOT LIKE '%@professional.malva.local'
  AND NOT EXISTS (
    SELECT 1 FROM users other
    WHERE other.id <> u.id
      AND (lower(btrim(other.email)) = lower(btrim(u.email))
        OR lower(btrim(other.sso_email)) = lower(btrim(u.email)))
  );
