-- Call events appear in chat (ringing → missed / ended with duration).
ALTER TABLE voice_messages ADD COLUMN kind TEXT NOT NULL DEFAULT 'voice';
ALTER TABLE voice_messages ADD COLUMN call_id TEXT;
ALTER TABLE voice_messages ADD COLUMN call_status TEXT;
ALTER TABLE voice_messages ADD COLUMN call_type TEXT;

ALTER TABLE calls ADD COLUMN answered_at TEXT;
ALTER TABLE calls ADD COLUMN event_message_id TEXT;

CREATE INDEX IF NOT EXISTS idx_voice_messages_call ON voice_messages(call_id);
