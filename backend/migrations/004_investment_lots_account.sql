-- Adds account_id to investment_lots so a lot can settle against an account
-- different from holding.account_id (e.g. cash comes from a different broker).
-- Backfills existing rows from their holding's account_id, then enforces NOT NULL.

ALTER TABLE investment_lots
    ADD COLUMN account_id uuid REFERENCES accounts (id);

UPDATE investment_lots l
SET account_id = h.account_id
FROM investment_holdings h
WHERE l.holding_id = h.id
  AND l.account_id IS NULL;

ALTER TABLE investment_lots
    ALTER COLUMN account_id SET NOT NULL;

CREATE INDEX idx_investment_lots_account_id
    ON investment_lots (account_id)
    WHERE deleted_at IS NULL;
