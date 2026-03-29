CREATE TABLE transaction_templates
(
    id              uuid PRIMARY KEY      DEFAULT gen_random_uuid(),
    user_id         uuid         NOT NULL,
    name            TEXT         NOT NULL,
    account_id      uuid         NOT NULL REFERENCES accounts (id),
    to_account_id   uuid REFERENCES accounts (id),
    category_id     uuid REFERENCES categories (id),
    type            transaction_type NOT NULL,
    amount_cents    BIGINT,
    currency_code   TEXT         NOT NULL,
    tags            TEXT[],
    description     TEXT         NOT NULL DEFAULT '',
    frequency       TEXT,
    next_date       DATE,
    end_date        DATE,
    created_at      timestamptz  NOT NULL DEFAULT NOW(),
    updated_at      timestamptz  NOT NULL DEFAULT NOW(),
    deleted_at      timestamptz
);

CREATE INDEX idx_transaction_templates_user_next_date
    ON transaction_templates (user_id, next_date)
    WHERE deleted_at IS NULL
      AND frequency IS NOT NULL
      AND next_date IS NOT NULL;

CREATE INDEX idx_transaction_templates_user_updated_at
    ON transaction_templates (user_id, updated_at);

ALTER TABLE transactions
    ADD COLUMN template_id uuid REFERENCES transaction_templates (id);

CREATE INDEX idx_transactions_template_id
    ON transactions (template_id)
    WHERE template_id IS NOT NULL;

CREATE TRIGGER set_updated_at_transaction_templates
    BEFORE UPDATE
    ON transaction_templates
    FOR EACH ROW
EXECUTE FUNCTION trigger_set_updated_at();
