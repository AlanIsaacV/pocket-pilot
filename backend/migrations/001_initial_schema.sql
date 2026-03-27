CREATE TYPE account_type AS ENUM ('bank', 'cash', 'credit_card', 'loan', 'investment', 'crypto', 'other');
CREATE TABLE accounts
(
    id                 uuid PRIMARY KEY      DEFAULT gen_random_uuid(),
    user_id            uuid         NOT NULL,
    name               TEXT         NOT NULL,
    type               account_type NOT NULL,
    currency_code      TEXT         NOT NULL,

    credit_limit_cents INTEGER,
    statement_day      SMALLINT,
    payment_due_day    SMALLINT,
    interest_rate_apr  NUMERIC(5, 2),
    term_months        SMALLINT,

    created_at         timestamptz  NOT NULL DEFAULT NOW(),
    updated_at         timestamptz  NOT NULL DEFAULT NOW(),
    deleted_at         timestamptz -- NULL means active (not deleted)
);
CREATE INDEX idx_accounts_user_id ON accounts (user_id) WHERE deleted_at IS NULL;


CREATE TYPE category_type AS ENUM ('income', 'expense');
CREATE TABLE categories
(
    id         uuid PRIMARY KEY       DEFAULT gen_random_uuid(),
    user_id    uuid          NOT NULL,
    name       TEXT          NOT NULL,
    icon       TEXT,
    color      TEXT,
    parent_id  uuid REFERENCES categories (id),
    type       category_type NOT NULL,
    created_at timestamptz   NOT NULL DEFAULT NOW(),
    updated_at timestamptz   NOT NULL DEFAULT NOW(),
    deleted_at timestamptz
);
CREATE INDEX idx_categories_user_id ON categories (user_id) WHERE deleted_at IS NULL;


CREATE TABLE tags
(
    id         uuid PRIMARY KEY     DEFAULT gen_random_uuid(),
    user_id    uuid        NOT NULL,
    name       TEXT        NOT NULL,
    created_at timestamptz NOT NULL DEFAULT NOW(),
    updated_at timestamptz NOT NULL DEFAULT NOW(),
    deleted_at timestamptz
);
CREATE INDEX idx_tags_user_id ON tags (user_id) WHERE deleted_at IS NULL;


CREATE TYPE transaction_type AS ENUM ('income', 'expense', 'transfer_out', 'transfer_in');
CREATE TABLE transactions
(
    id            uuid PRIMARY KEY          DEFAULT gen_random_uuid(),
    user_id       uuid             NOT NULL,
    account_id    uuid             NOT NULL REFERENCES accounts (id),
    category_id   uuid             REFERENCES categories (id),
    linked_transaction_id uuid     transactions (id),
    type          transaction_type NOT NULL,
    amount_cents  BIGINT           NOT NULL,
    currency_code TEXT             NOT NULL,
    status        TEXT             NOT NULL,
    tags          TEXT[],
    description   TEXT             NOT NULL DEFAULT '',
    date          DATE             NOT NULL,
    created_at    timestamptz      NOT NULL DEFAULT NOW(),
    updated_at    timestamptz      NOT NULL DEFAULT NOW(),
    deleted_at    timestamptz
);
CREATE INDEX idx_transactions_user_date
    ON transactions (user_id, date DESC)
    WHERE deleted_at IS NULL;
CREATE INDEX idx_transactions_account_id
    ON transactions (account_id)
    WHERE deleted_at IS NULL;
CREATE INDEX idx_transactions_category_id
    ON transactions (category_id)
    WHERE deleted_at IS NULL;
CREATE INDEX idx_transactions_linked
    ON transactions (linked_transaction_id)
    WHERE linked_transaction_id IS NOT NULL;


CREATE TABLE user_preferences
(
    user_id    uuid        NOT NULL,
    pref_key   VARCHAR(50) NOT NULL,
    pref_value TEXT        NOT NULL,
    created_at timestamptz NOT NULL DEFAULT NOW(),
    updated_at timestamptz NOT NULL DEFAULT NOW(),
    deleted_at timestamptz,
    PRIMARY KEY (user_id, pref_key)
);

CREATE INDEX idx_user_preferences_user_id
    ON user_preferences (user_id)
    WHERE deleted_at IS NULL;

CREATE INDEX idx_user_preferences_user_updated_at
    ON user_preferences (user_id, updated_at);


CREATE OR REPLACE FUNCTION trigger_set_updated_at()
    RETURNS TRIGGER AS
$$
BEGIN
    new.updated_at = NOW();
    RETURN new;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER set_updated_at_accounts
    BEFORE UPDATE
    ON accounts
    FOR EACH ROW
EXECUTE FUNCTION trigger_set_updated_at();

CREATE TRIGGER set_updated_at_categories
    BEFORE UPDATE
    ON categories
    FOR EACH ROW
EXECUTE FUNCTION trigger_set_updated_at();

CREATE TRIGGER set_updated_at_tags
    BEFORE UPDATE
    ON tags
    FOR EACH ROW
EXECUTE FUNCTION trigger_set_updated_at();

CREATE TRIGGER set_updated_at_transactions
    BEFORE UPDATE
    ON transactions
    FOR EACH ROW
EXECUTE FUNCTION trigger_set_updated_at();

CREATE TRIGGER set_updated_at_user_preferences
    BEFORE UPDATE
    ON user_preferences
    FOR EACH ROW
EXECUTE FUNCTION trigger_set_updated_at();
