-- Adds account_id to investment_lots so a lot can settle against an account
-- different from holding.account_id. Backfills from the holding and leaves the
-- column nullable (SQLite cannot enforce NOT NULL on ADD COLUMN when rows
-- already exist; the frontend enforces the invariant at the form layer).

ALTER TABLE investment_lots ADD COLUMN account_id TEXT REFERENCES accounts (id);

UPDATE investment_lots
SET account_id = (
    SELECT account_id FROM investment_holdings
    WHERE investment_holdings.id = investment_lots.holding_id
)
WHERE account_id IS NULL;

CREATE INDEX idx_investment_lots_account
    ON investment_lots (account_id)
    WHERE deleted_at IS NULL;
