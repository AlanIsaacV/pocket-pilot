CREATE TABLE transaction_templates
(
    id            TEXT PRIMARY KEY,
    name          TEXT     NOT NULL,
    account_id    TEXT     NOT NULL REFERENCES accounts (id),
    to_account_id TEXT REFERENCES accounts (id),
    category_id   TEXT REFERENCES categories (id),
    type          TEXT     NOT NULL,
    amount_cents  BIGINT,
    currency_code TEXT     NOT NULL,
    tags          TEXT,
    description   TEXT     NOT NULL DEFAULT '',
    frequency     TEXT,
    next_date     DATE,
    end_date      DATE,
    created_at    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    deleted_at    DATETIME
);

CREATE INDEX idx_transaction_templates_next_date
    ON transaction_templates (next_date)
    WHERE deleted_at IS NULL
      AND frequency IS NOT NULL
      AND next_date IS NOT NULL;

CREATE INDEX idx_transaction_templates_updated_at
    ON transaction_templates (updated_at);

CREATE TRIGGER set_updated_at_transaction_templates
    AFTER UPDATE
    ON transaction_templates
    FOR EACH ROW
    WHEN new.updated_at = old.updated_at
BEGIN
    UPDATE transaction_templates
    SET updated_at = CURRENT_TIMESTAMP
    WHERE id = new.id;
END;

ALTER TABLE transactions
    ADD COLUMN template_id TEXT REFERENCES transaction_templates (id);

CREATE INDEX idx_transactions_template_id
    ON transactions (template_id)
    WHERE template_id IS NOT NULL;
