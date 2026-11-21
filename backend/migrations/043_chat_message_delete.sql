-- Keep the message ID reserved so a sender retry cannot restore deleted content.
ALTER TABLE chat_messages ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;
