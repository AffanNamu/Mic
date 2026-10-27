-- An account the person deleted. The row stays (credit-ledger and audit rows point at its id) but holds
-- no email, no password hash and no sessions: see src/account.ts.
ALTER TABLE users ADD COLUMN deleted_at TEXT;
