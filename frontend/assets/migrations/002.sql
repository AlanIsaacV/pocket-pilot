-- Investments schema: renta variable (acciones, ETFs). Mirrors 003_investments.sql
-- in the backend. See docs/context/architecture/investments.md.

CREATE TABLE investment_holdings (
    id            TEXT PRIMARY KEY,
    account_id    TEXT     NOT NULL REFERENCES accounts (id),
    symbol        TEXT     NOT NULL,
    exchange      TEXT     NOT NULL,
    display_name  TEXT     NOT NULL DEFAULT '',
    currency_code TEXT     NOT NULL,
    asset_type    TEXT     NOT NULL,
    status        TEXT     NOT NULL DEFAULT 'active',
    manual_price  NUMERIC(18, 4),
    notes         TEXT,
    created_at    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    deleted_at    DATETIME
);

CREATE INDEX idx_investment_holdings_account
    ON investment_holdings (account_id)
    WHERE deleted_at IS NULL;

CREATE INDEX idx_investment_holdings_updated_at
    ON investment_holdings (updated_at);

CREATE INDEX idx_investment_holdings_symbol_exchange
    ON investment_holdings (symbol, exchange)
    WHERE deleted_at IS NULL;

CREATE TRIGGER set_updated_at_investment_holdings
    AFTER UPDATE
    ON investment_holdings
    FOR EACH ROW
    WHEN new.updated_at = old.updated_at
BEGIN
    UPDATE investment_holdings
    SET updated_at = CURRENT_TIMESTAMP
    WHERE id = new.id;
END;


CREATE TABLE investment_lots (
    id          TEXT PRIMARY KEY,
    holding_id  TEXT           NOT NULL REFERENCES investment_holdings (id),
    kind        TEXT           NOT NULL,
    quantity    NUMERIC(18, 8) NOT NULL,
    price       NUMERIC(18, 4) NOT NULL,
    fee_cents   BIGINT         NOT NULL DEFAULT 0,
    fx_rate     NUMERIC(18, 8),
    occurred_at DATE           NOT NULL,
    validity    TEXT           NOT NULL DEFAULT 'valid',
    notes       TEXT,
    created_at  DATETIME       NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at  DATETIME       NOT NULL DEFAULT CURRENT_TIMESTAMP,
    deleted_at  DATETIME,

    CHECK (kind IN ('buy', 'sell')),
    CHECK (quantity > 0)
);

CREATE INDEX idx_investment_lots_holding
    ON investment_lots (holding_id, occurred_at)
    WHERE deleted_at IS NULL;

CREATE INDEX idx_investment_lots_updated_at
    ON investment_lots (updated_at);

CREATE TRIGGER set_updated_at_investment_lots
    AFTER UPDATE
    ON investment_lots
    FOR EACH ROW
    WHEN new.updated_at = old.updated_at
BEGIN
    UPDATE investment_lots
    SET updated_at = CURRENT_TIMESTAMP
    WHERE id = new.id;
END;


-- market_prices is a local cache of server-provided prices. Read-only from the
-- app's perspective: the MarketPriceSyncHandler only pulls, never pushes.
CREATE TABLE market_prices (
    symbol        TEXT           NOT NULL,
    exchange      TEXT           NOT NULL,
    currency_code TEXT           NOT NULL,
    price         NUMERIC(18, 4) NOT NULL,
    price_date    DATE           NOT NULL,
    source        TEXT           NOT NULL,
    fetched_at    DATETIME       NOT NULL,
    updated_at    DATETIME       NOT NULL,
    PRIMARY KEY (symbol, exchange)
);

CREATE INDEX idx_market_prices_updated_at
    ON market_prices (updated_at);


-- transactions: link columns for derived investment transactions.
ALTER TABLE transactions ADD COLUMN holding_id TEXT REFERENCES investment_holdings (id);
ALTER TABLE transactions ADD COLUMN lot_id     TEXT REFERENCES investment_lots (id);

CREATE INDEX idx_transactions_holding_id
    ON transactions (holding_id)
    WHERE holding_id IS NOT NULL;

CREATE INDEX idx_transactions_lot_id
    ON transactions (lot_id)
    WHERE lot_id IS NOT NULL;
