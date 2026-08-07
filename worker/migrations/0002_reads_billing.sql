-- Unread tracking per conversation member
ALTER TABLE conversation_members ADD COLUMN last_read_at TEXT;

-- Optional billing profile on family (owner fills before Stripe checkout)
ALTER TABLE families ADD COLUMN billing_type TEXT CHECK (billing_type IN ('individual', 'company'));
ALTER TABLE families ADD COLUMN billing_name TEXT;
ALTER TABLE families ADD COLUMN billing_tax_id TEXT;
ALTER TABLE families ADD COLUMN billing_address_line1 TEXT;
ALTER TABLE families ADD COLUMN billing_city TEXT;
ALTER TABLE families ADD COLUMN billing_postal_code TEXT;
ALTER TABLE families ADD COLUMN billing_country TEXT DEFAULT 'HU';
