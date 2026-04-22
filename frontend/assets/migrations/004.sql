-- Holdings become globals (no owning account). The lot's account_id is the
-- single source of truth for where cash settles.

DROP INDEX IF EXISTS idx_investment_holdings_account;

ALTER TABLE investment_holdings DROP COLUMN account_id;
