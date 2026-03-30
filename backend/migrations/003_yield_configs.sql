CREATE TABLE yield_configs
(
    id               uuid PRIMARY KEY      DEFAULT gen_random_uuid(),
    user_id          uuid         NOT NULL,
    account_id       uuid         NOT NULL REFERENCES accounts (id),
    name             TEXT         NOT NULL,

    amount_cents     BIGINT       NOT NULL,
    apy_rate         NUMERIC(7,4) NOT NULL,

    payout_frequency TEXT         NOT NULL,
    next_date        DATE         NOT NULL,
    maturity_date    DATE,
    term_days        INTEGER,

    auto_renew       BOOLEAN      NOT NULL DEFAULT FALSE,
    status           TEXT         NOT NULL,

    created_at       timestamptz  NOT NULL DEFAULT NOW(),
    updated_at       timestamptz  NOT NULL DEFAULT NOW(),
    deleted_at       timestamptz
);

CREATE INDEX idx_yield_configs_user_updated_at
    ON yield_configs (user_id, updated_at);

CREATE INDEX idx_yield_configs_user_next_date_active
    ON yield_configs (user_id, next_date)
    WHERE deleted_at IS NULL
      AND status = 'active';

ALTER TABLE transactions
    ADD COLUMN yield_id uuid REFERENCES yield_configs (id);

CREATE INDEX idx_transactions_yield_id
    ON transactions (yield_id)
    WHERE yield_id IS NOT NULL;

CREATE TRIGGER set_updated_at_yield_configs
    BEFORE UPDATE
    ON yield_configs
    FOR EACH ROW
EXECUTE FUNCTION trigger_set_updated_at();
