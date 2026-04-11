CREATE TABLE accounts (
    id                 TEXT PRIMARY KEY,
    name               TEXT     NOT NULL,
    type               TEXT     NOT NULL,
    currency_code      TEXT     NOT NULL,
    credit_limit_cents INTEGER,
    statement_day      SMALLINT,
    payment_due_day    SMALLINT,
    interest_rate_apr  NUMERIC(5, 2),
    term_months        SMALLINT,
    created_at         DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at         DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    deleted_at         DATETIME
);
CREATE TRIGGER set_updated_at_accounts
    AFTER UPDATE
    ON accounts
    FOR EACH ROW
    WHEN new.updated_at = old.updated_at
BEGIN
    UPDATE accounts
    SET updated_at = CURRENT_TIMESTAMP
    WHERE id = new.id;
END;

CREATE TABLE categories (
    id             TEXT PRIMARY KEY,
    name           TEXT     NOT NULL,
    icon           TEXT,
    color          TEXT,
    parent_id      TEXT REFERENCES categories (id),
    type           TEXT     NOT NULL,
    default_nature TEXT     NOT NULL DEFAULT '',
    created_at     DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at     DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    deleted_at     DATETIME
);
CREATE TRIGGER set_updated_at_categories
    AFTER UPDATE
    ON categories
    FOR EACH ROW
    WHEN new.updated_at = old.updated_at
BEGIN
    UPDATE categories
    SET updated_at = CURRENT_TIMESTAMP
    WHERE id = new.id;
END;


CREATE TABLE tags (
    id         TEXT PRIMARY KEY,
    name       TEXT     NOT NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    deleted_at DATETIME
);
CREATE TRIGGER set_updated_at_tags
    AFTER UPDATE
    ON tags
    FOR EACH ROW
    WHEN new.updated_at = old.updated_at
BEGIN
    UPDATE tags
    SET updated_at = CURRENT_TIMESTAMP
    WHERE id = new.id;
END;


CREATE TABLE transaction_templates (
    id             TEXT PRIMARY KEY,
    name           TEXT     NOT NULL,
    account_id     TEXT     NOT NULL REFERENCES accounts (id),
    to_account_id  TEXT REFERENCES accounts (id),
    category_id    TEXT REFERENCES categories (id),
    type           TEXT     NOT NULL,
    nature         TEXT     NOT NULL DEFAULT '',
    is_auto_charge INTEGER  NOT NULL DEFAULT 0,
    is_active      INTEGER  NOT NULL DEFAULT 1,
    amount_cents   BIGINT,
    currency_code  TEXT     NOT NULL,
    tags           TEXT,
    description    TEXT     NOT NULL DEFAULT '',
    frequency      TEXT,
    next_date      DATE,
    end_date       DATE,
    created_at     DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at     DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    deleted_at     DATETIME
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


CREATE TABLE yield_configs (
    id               TEXT PRIMARY KEY,
    account_id       TEXT          NOT NULL REFERENCES accounts (id),
    name             TEXT          NOT NULL,
    amount_cents     BIGINT        NOT NULL,
    apy_rate         NUMERIC(7, 4) NOT NULL,
    payout_frequency TEXT          NOT NULL,
    next_date        DATE          NOT NULL,
    maturity_date    DATE,
    term_days        INTEGER,
    auto_renew       INTEGER       NOT NULL DEFAULT 0,
    status           TEXT          NOT NULL,
    created_at       DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at       DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    deleted_at       DATETIME
);


CREATE INDEX idx_yield_configs_next_date_active
    ON yield_configs (next_date)
    WHERE deleted_at IS NULL
        AND status = 'active';

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


CREATE TABLE transactions (
    id                    TEXT PRIMARY KEY,
    account_id            TEXT     NOT NULL REFERENCES accounts (id),
    category_id           TEXT REFERENCES categories (id),
    linked_transaction_id TEXT,
    template_id           TEXT REFERENCES transaction_templates (id),
    yield_id              TEXT REFERENCES yield_configs (id),
    type                  TEXT     NOT NULL,
    nature                TEXT     NOT NULL DEFAULT '',
    amount_cents          BIGINT   NOT NULL,
    installments_count    INTEGER  NOT NULL DEFAULT 1,
    currency_code         TEXT     NOT NULL,
    status                TEXT     NOT NULL,
    tags                  TEXT,
    description           TEXT     NOT NULL DEFAULT '',
    date                  DATE     NOT NULL,
    created_at            DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at            DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    deleted_at            DATETIME
);
CREATE INDEX idx_transactions_date
    ON transactions (date) WHERE deleted_at IS NULL;

CREATE INDEX idx_transactions_template_id
    ON transactions (template_id)
    WHERE template_id IS NOT NULL;


CREATE INDEX idx_transactions_yield_id
    ON transactions (yield_id)
    WHERE yield_id IS NOT NULL;


CREATE TRIGGER set_updated_at_transactions
    AFTER UPDATE
    ON transactions
    FOR EACH ROW
    WHEN new.updated_at = old.updated_at
BEGIN
    UPDATE transactions
    SET updated_at = CURRENT_TIMESTAMP
    WHERE id = new.id;
END;


CREATE TABLE user_preferences (
    pref_key   TEXT PRIMARY KEY,
    pref_value TEXT     NOT NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    deleted_at DATETIME
);

CREATE TRIGGER set_updated_at_user_preferences
    AFTER UPDATE
    ON user_preferences
    FOR EACH ROW
    WHEN new.updated_at = old.updated_at
BEGIN
    UPDATE user_preferences
    SET updated_at = CURRENT_TIMESTAMP
    WHERE pref_key = new.pref_key;
END;

CREATE INDEX idx_user_preferences_updated_at
    ON user_preferences (updated_at);


CREATE INDEX idx_transactions_account_id
    ON transactions (account_id)
    WHERE deleted_at IS NULL;

CREATE INDEX idx_transactions_category_id
    ON transactions (category_id)
    WHERE deleted_at IS NULL;

CREATE INDEX idx_transactions_currency_code
    ON transactions (currency_code)
    WHERE deleted_at IS NULL;

CREATE INDEX idx_transactions_linked
    ON transactions (linked_transaction_id)
    WHERE linked_transaction_id IS NOT NULL;


CREATE TABLE goals (
    id                  TEXT PRIMARY KEY,
    name                TEXT     NOT NULL,
    target_amount_cents INTEGER  NOT NULL,
    target_date         DATE     NOT NULL,
    currency_code       TEXT     NOT NULL,
    created_at          DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at          DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    deleted_at          DATETIME
);

CREATE INDEX idx_goals_target_date_active
    ON goals (target_date)
    WHERE deleted_at IS NULL;

CREATE INDEX idx_goals_updated_at
    ON goals (updated_at);

CREATE TRIGGER set_updated_at_goals
    AFTER UPDATE
    ON goals
    FOR EACH ROW
    WHEN new.updated_at = old.updated_at
BEGIN
    UPDATE goals
    SET updated_at = CURRENT_TIMESTAMP
    WHERE id = new.id;
END;


CREATE TABLE budgets (
    id                 TEXT PRIMARY KEY,
    category_id        TEXT     NOT NULL REFERENCES categories (id),
    limit_amount_cents INTEGER  NOT NULL,
    currency_code      TEXT     NOT NULL,
    period             TEXT     NOT NULL,
    created_at         DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at         DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    deleted_at         DATETIME,
    UNIQUE (category_id)
);

CREATE INDEX idx_budgets_category_id
    ON budgets (category_id)
    WHERE deleted_at IS NULL;

CREATE INDEX idx_budgets_updated_at
    ON budgets (updated_at);

CREATE TRIGGER set_updated_at_budgets
    AFTER UPDATE
    ON budgets
    FOR EACH ROW
    WHEN new.updated_at = old.updated_at
BEGIN
    UPDATE budgets
    SET updated_at = CURRENT_TIMESTAMP
    WHERE id = new.id;
END;


CREATE TABLE sync_outbox (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    entity_type TEXT    NOT NULL,
    entity_id   TEXT    NOT NULL,
    operation   TEXT    NOT NULL,
    payload     TEXT    NOT NULL,
    created_at  TEXT    NOT NULL DEFAULT (DATETIME('now')),
    retry_count INTEGER NOT NULL DEFAULT 0,
    last_error  TEXT
);
CREATE UNIQUE INDEX idx_sync_outbox_entity ON sync_outbox (entity_type, entity_id);


CREATE TABLE sync_metadata (
    entity_type TEXT PRIMARY KEY, last_synced_at TEXT
);


CREATE TABLE app_metadata (
    key TEXT PRIMARY KEY, value TEXT NOT NULL
);


CREATE TABLE IF NOT EXISTS notifications (
    id           TEXT PRIMARY KEY,
    title        TEXT    NOT NULL,
    subtitle     TEXT    NOT NULL DEFAULT '',
    date         TEXT    NOT NULL,
    type         TEXT    NOT NULL,
    amount_cents INTEGER,
    source_id    TEXT    NOT NULL,
    is_read      INTEGER NOT NULL DEFAULT 0,
    deleted_at   TEXT,
    created_at   TEXT    NOT NULL
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_notifications_source_date_type
    ON notifications (source_id, date, type);
