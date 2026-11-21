CREATE TABLE IF NOT EXISTS diary_recipients (
    diary_id uuid NOT NULL REFERENCES diary_entries(id) ON DELETE CASCADE,
    professional_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    requires_legacy_consent boolean NOT NULL DEFAULT false,
    PRIMARY KEY (diary_id, professional_id)
);

CREATE INDEX IF NOT EXISTS diary_recipients_professional_idx ON diary_recipients (professional_id);
