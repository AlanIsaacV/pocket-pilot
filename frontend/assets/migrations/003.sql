CREATE TABLE yield_configs
(
    id               TEXT PRIMARY KEY,
    account_id       TEXT     NOT NULL REFERENCES accounts (id),
    name             TEXT     NOT NULL,

    amount_cents     BIGINT   NOT NULL,
    apy_rate         NUMERIC(7,4) NOT NULL,

    payout_frequency TEXT     NOT NULL,
    next_date        DATE     NOT NULL,
    maturity_date    DATE,
    term_days        INTEGER,

    auto_renew       INTEGER  NOT NULL DEFAULT 0,
    status           TEXT     NOT NULL,

    created_at       DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at       DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    deleted_at       DATETIME
);

CREATE INDEX idx_yield_configs_next_date_active
    ON yield_configs (next_date)
    WHERE deleted_at IS NULL
      AND status = 'active';

CREATE INDEX idx_yield_configs_updated_at
    ON yield_configs (updated_at);

CREATE TRIGGER set_updated_at_yield_configs
    AFTER UPDATE
    ON yield_configs
    FOR EACH ROW
    WHEN new.updated_at = old.updated_at
BEGIN
    UPDATE yield_configs
    SET updated_at = CURRENT_TIMESTAMP
    WHERE id = new.id;
END;

ALTER TABLE transactions
    ADD COLUMN yield_id TEXT REFERENCES yield_configs (id);

CREATE INDEX idx_transactions_yield_id
    ON transactions (yield_id)
    WHERE yield_id IS NOT NULL;
