-- QR / in-app invites can target a specific user id (not only email).
ALTER TABLE invites ADD COLUMN target_user_id TEXT REFERENCES users(id);
CREATE INDEX IF NOT EXISTS idx_invites_target ON invites(target_user_id);
