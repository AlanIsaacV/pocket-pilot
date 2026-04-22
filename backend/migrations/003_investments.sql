-- Investments: renta variable (acciones, ETFs) with offline-first sync.
-- See docs/context/architecture/investments.md for the full design.

-- =============================================================================
-- investment_holdings
-- =============================================================================
-- One row per (account, symbol+exchange) position a user tracks. Quantities
-- and P&L are derived on-the-fly from investment_lots.
CREATE TABLE investment_holdings (
    id            uuid PRIMARY KEY     DEFAULT gen_random_uuid(),
    user_id       uuid        NOT NULL REFERENCES users (id),
    account_id    uuid        NOT NULL REFERENCES accounts (id),
    symbol        TEXT        NOT NULL,
    exchange      TEXT        NOT NULL,
    display_name  TEXT        NOT NULL DEFAULT '',
    currency_code TEXT        NOT NULL,
    asset_type    TEXT        NOT NULL,
    status        TEXT        NOT NULL DEFAULT 'active',
    manual_price  NUMERIC(18, 4),
    notes         TEXT,
    created_at    timestamptz NOT NULL DEFAULT NOW(),
    updated_at    timestamptz NOT NULL DEFAULT NOW(),
    deleted_at    timestamptz
);

CREATE INDEX idx_investment_holdings_user_id
    ON investment_holdings (user_id)
    WHERE deleted_at IS NULL;

CREATE INDEX idx_investment_holdings_user_updated_at
    ON investment_holdings (user_id, updated_at);

CREATE INDEX idx_investment_holdings_account_id
    ON investment_holdings (account_id)
    WHERE deleted_at IS NULL;

-- For the cron: distinct symbol+exchange pairs needing price refresh.
CREATE INDEX idx_investment_holdings_symbol_exchange_active
    ON investment_holdings (symbol, exchange)
    WHERE deleted_at IS NULL;

-- =============================================================================
-- investment_lots
-- =============================================================================
-- Each buy or sell event. Fully replayable source of truth for positions.
CREATE TABLE investment_lots (
    id          uuid PRIMARY KEY      DEFAULT gen_random_uuid(),
    user_id     uuid         NOT NULL REFERENCES users (id),
    holding_id  uuid         NOT NULL REFERENCES investment_holdings (id),
    kind        TEXT         NOT NULL,
    quantity    NUMERIC(18, 8) NOT NULL,
    price       NUMERIC(18, 4) NOT NULL,
    fee_cents   BIGINT       NOT NULL DEFAULT 0,
    fx_rate     NUMERIC(18, 8),
    occurred_at DATE         NOT NULL,
    validity    TEXT         NOT NULL DEFAULT 'valid',
    notes       TEXT,
    created_at  timestamptz  NOT NULL DEFAULT NOW(),
    updated_at  timestamptz  NOT NULL DEFAULT NOW(),
    deleted_at  timestamptz,

    CONSTRAINT investment_lots_kind_check
        CHECK (kind IN ('buy', 'sell')),
    CONSTRAINT investment_lots_quantity_positive
        CHECK (quantity > 0)
);

CREATE INDEX idx_investment_lots_user_updated_at
    ON investment_lots (user_id, updated_at);

CREATE INDEX idx_investment_lots_holding_id
    ON investment_lots (holding_id, occurred_at)
    WHERE deleted_at IS NULL;

-- =============================================================================
-- market_prices
-- =============================================================================
-- Read-only from the client's perspective. Populated by the server cron that
-- fetches quotes 1x/day. Natural key is (symbol, exchange).
CREATE TABLE market_prices (
    symbol        TEXT        NOT NULL,
    exchange      TEXT        NOT NULL,
    currency_code TEXT        NOT NULL,
    price         NUMERIC(18, 4) NOT NULL,
    price_date    DATE        NOT NULL,
    source        TEXT        NOT NULL,
    fetched_at    timestamptz NOT NULL DEFAULT NOW(),
    updated_at    timestamptz NOT NULL DEFAULT NOW(),
    PRIMARY KEY (symbol, exchange)
);

CREATE INDEX idx_market_prices_updated_at
    ON market_prices (updated_at);

-- =============================================================================
-- transactions: link columns for derived investment transactions
-- =============================================================================
ALTER TABLE transactions
    ADD COLUMN holding_id uuid REFERENCES investment_holdings (id),
    ADD COLUMN lot_id     uuid REFERENCES investment_lots (id);

CREATE INDEX idx_transactions_holding_id
    ON transactions (holding_id)
    WHERE holding_id IS NOT NULL;

CREATE INDEX idx_transactions_lot_id
    ON transactions (lot_id)
    WHERE lot_id IS NOT NULL;

-- Prevent a transaction from being simultaneously a yield and an investment
-- event. yield_id + holding_id mutual exclusion.
ALTER TABLE transactions
    ADD CONSTRAINT transactions_yield_vs_holding_check
    CHECK (NOT (yield_id IS NOT NULL AND holding_id IS NOT NULL));

-- =============================================================================
-- updated_at triggers
-- =============================================================================
CREATE TRIGGER set_updated_at_investment_holdings
    BEFORE UPDATE
    ON investment_holdings
    FOR EACH ROW
EXECUTE FUNCTION trigger_set_updated_at();

CREATE TRIGGER set_updated_at_investment_lots
    BEFORE UPDATE
    ON investment_lots
    FOR EACH ROW
EXECUTE FUNCTION trigger_set_updated_at();

CREATE TRIGGER set_updated_at_market_prices
    BEFORE UPDATE
    ON market_prices
    FOR EACH ROW
EXECUTE FUNCTION trigger_set_updated_at();
