-- =============================================================================
-- Migration: 001_initial_schema.sql
-- Description: Core tables for Pocket Pilot MVP
--   - Uses gen_random_uuid() (built-in since PostgreSQL 13, no extension needed)
--   - All monetary values stored as INTEGER in minor units (e.g., cents)
--     to avoid floating-point precision issues. $10.50 = 1050.
--   - Soft deletes via deleted_at (essential for offline-first sync reconciliation)
--   - All timestamps use TIMESTAMPTZ (timezone-aware)
-- =============================================================================

-- ---------------------------------------------------------------------------
-- ACCOUNTS
-- Represents a financial account (bank, cash, credit card, etc.)
-- ---------------------------------------------------------------------------
CREATE TABLE accounts (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID        NOT NULL,
    name            TEXT        NOT NULL,
    -- Possible values: 'checking', 'savings', 'credit_card', 'cash', 'investment'
    type            TEXT        NOT NULL,
    -- Stored in minor units (cents). e.g., $100.00 = 10000
    initial_balance BIGINT      NOT NULL DEFAULT 0,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at      TIMESTAMPTZ          -- NULL means active (not deleted)
);

-- Index for the most common query pattern: "get all accounts for a user"
CREATE INDEX idx_accounts_user_id ON accounts (user_id) WHERE deleted_at IS NULL;

-- ---------------------------------------------------------------------------
-- CATEGORIES
-- Income or expense categories, per user
-- ---------------------------------------------------------------------------
CREATE TABLE categories (
    id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     UUID        NOT NULL,
    name        TEXT        NOT NULL,
    -- Possible values: 'income', 'expense'
    type        TEXT        NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at  TIMESTAMPTZ
);

CREATE INDEX idx_categories_user_id ON categories (user_id) WHERE deleted_at IS NULL;

-- ---------------------------------------------------------------------------
-- TRANSACTIONS
-- A single financial movement linked to an account and a category
-- ---------------------------------------------------------------------------
CREATE TABLE transactions (
    id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     UUID        NOT NULL,
    account_id  UUID        NOT NULL REFERENCES accounts(id),
    category_id UUID        NOT NULL REFERENCES categories(id),
    -- Amount in minor units. Always positive; direction is determined by
    -- the category type (income = positive flow, expense = negative flow).
    amount      BIGINT      NOT NULL CHECK (amount > 0),
    description TEXT        NOT NULL DEFAULT '',
    -- The logical date of the transaction (when it happened), not the
    -- insert timestamp. Stored as DATE since time-of-day is not relevant.
    date        DATE        NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at  TIMESTAMPTZ
);

-- Composite index for the most common query: "transactions for a user, newest first"
CREATE INDEX idx_transactions_user_date
    ON transactions (user_id, date DESC)
    WHERE deleted_at IS NULL;

-- Supports queries filtered by account (e.g., account statement)
CREATE INDEX idx_transactions_account_id
    ON transactions (account_id)
    WHERE deleted_at IS NULL;

-- Supports queries filtered by category (e.g., spending by category)
CREATE INDEX idx_transactions_category_id
    ON transactions (category_id)
    WHERE deleted_at IS NULL;

-- ---------------------------------------------------------------------------
-- TRIGGER: auto-update updated_at on row modification
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION trigger_set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER set_updated_at_accounts
    BEFORE UPDATE ON accounts
    FOR EACH ROW EXECUTE FUNCTION trigger_set_updated_at();

CREATE TRIGGER set_updated_at_categories
    BEFORE UPDATE ON categories
    FOR EACH ROW EXECUTE FUNCTION trigger_set_updated_at();

CREATE TRIGGER set_updated_at_transactions
    BEFORE UPDATE ON transactions
    FOR EACH ROW EXECUTE FUNCTION trigger_set_updated_at();
