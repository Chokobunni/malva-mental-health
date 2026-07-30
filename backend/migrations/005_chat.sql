-- Chat messages between linked patient-professional pairs
CREATE TABLE IF NOT EXISTS chat_messages (
    id             TEXT PRIMARY KEY,
    patient_id     UUID NOT NULL REFERENCES users(id),
    professional_id UUID NOT NULL REFERENCES users(id),
    sender_id      UUID NOT NULL REFERENCES users(id),
    sender_name    TEXT NOT NULL DEFAULT '',
    text           TEXT NOT NULL,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_chat_messages_conv
    ON chat_messages (patient_id, professional_id, created_at DESC);
