-- Profile avatars + pinned chats
ALTER TABLE users ADD COLUMN avatar_key TEXT;
ALTER TABLE conversation_members ADD COLUMN pinned_at TEXT;
