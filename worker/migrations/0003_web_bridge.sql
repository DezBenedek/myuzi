CREATE TABLE web_bridge_tokens (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  token_hash TEXT NOT NULL UNIQUE,
  expires_at TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX idx_web_bridge_user ON web_bridge_tokens(user_id);
CREATE INDEX idx_web_bridge_hash ON web_bridge_tokens(token_hash);
