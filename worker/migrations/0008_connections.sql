ALTER TABLE users ADD COLUMN contact_discoverable INTEGER NOT NULL DEFAULT 0;

CREATE TABLE family_link_invites (
  id TEXT PRIMARY KEY,
  source_family_id TEXT NOT NULL REFERENCES families(id) ON DELETE CASCADE,
  target_email TEXT NOT NULL COLLATE NOCASE,
  token TEXT NOT NULL UNIQUE,
  invited_by TEXT NOT NULL REFERENCES users(id),
  status TEXT NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'accepted', 'revoked', 'expired')),
  expires_at TEXT NOT NULL,
  accepted_by TEXT REFERENCES users(id),
  accepted_at TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX idx_family_link_invites_token ON family_link_invites(token);
CREATE INDEX idx_family_link_invites_target ON family_link_invites(target_email, status);
CREATE INDEX idx_family_link_invites_source ON family_link_invites(source_family_id, status);

CREATE TABLE family_connections (
  id TEXT PRIMARY KEY,
  family_a_id TEXT NOT NULL REFERENCES families(id) ON DELETE CASCADE,
  family_b_id TEXT NOT NULL REFERENCES families(id) ON DELETE CASCADE,
  status TEXT NOT NULL DEFAULT 'active'
    CHECK (status IN ('active', 'revoked')),
  created_by TEXT NOT NULL REFERENCES users(id),
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  revoked_at TEXT,
  CHECK (family_a_id < family_b_id),
  UNIQUE (family_a_id, family_b_id)
);

CREATE INDEX idx_family_connections_a ON family_connections(family_a_id, status);
CREATE INDEX idx_family_connections_b ON family_connections(family_b_id, status);

CREATE TABLE user_connections (
  id TEXT PRIMARY KEY,
  user_a_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  user_b_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  status TEXT NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'accepted', 'rejected', 'revoked')),
  requested_by TEXT NOT NULL REFERENCES users(id),
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  accepted_at TEXT,
  UNIQUE (user_a_id, user_b_id),
  CHECK (user_a_id < user_b_id)
);

CREATE INDEX idx_user_connections_a ON user_connections(user_a_id, status);
CREATE INDEX idx_user_connections_b ON user_connections(user_b_id, status);
