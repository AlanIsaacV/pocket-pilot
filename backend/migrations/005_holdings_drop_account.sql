-- Holdings become globals (no owning account). The lot's account_id is the
-- single source of truth for where cash settles; holdings just describe the
-- asset (symbol + exchange + currency).

DROP INDEX IF EXISTS idx_investment_holdings_account_id;

ALTER TABLE investment_holdings
    DROP COLUMN account_id;
