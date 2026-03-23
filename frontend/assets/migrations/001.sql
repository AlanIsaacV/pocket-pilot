CREATE TABLE accounts
(
    id                 TEXT PRIMARY KEY,
    name               TEXT     NOT NULL,
    type               TEXT     NOT NULL,
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
WHEN NEW.updated_at = OLD.updated_at
BEGIN
    UPDATE accounts
    SET updated_at = CURRENT_TIMESTAMP
    WHERE id = new.id;
END;

CREATE TABLE categories
(
    id         TEXT PRIMARY KEY,
    name       TEXT     NOT NULL,
    icon       TEXT,
    color      TEXT,
    parent_id  TEXT REFERENCES categories (id),
    type       TEXT     NOT NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    deleted_at DATETIME
);
CREATE TRIGGER set_updated_at_categories
    AFTER UPDATE
    ON categories
    FOR EACH ROW
WHEN NEW.updated_at = OLD.updated_at
BEGIN
    UPDATE categories
    SET updated_at = CURRENT_TIMESTAMP
    WHERE id = new.id;
END;


CREATE TABLE tags
(
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
WHEN NEW.updated_at = OLD.updated_at
BEGIN
    UPDATE tags
    SET updated_at = CURRENT_TIMESTAMP
    WHERE id = new.id;
END;


CREATE TABLE transactions
(
    id            TEXT PRIMARY KEY,
    account_id    TEXT     NOT NULL REFERENCES accounts (id),
    category_id   TEXT     NOT NULL REFERENCES categories (id),
    type          TEXT     NOT NULL,
    amount_cents  BIGINT   NOT NULL,
    currency_code TEXT     NOT NULL,
    status        TEXT     NOT NULL,
    tags          TEXT,
    description   TEXT     NOT NULL DEFAULT '',
    date          DATE     NOT NULL,
    created_at    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    deleted_at    DATETIME
);
CREATE TRIGGER set_updated_at_transactions
    AFTER UPDATE
    ON transactions
    FOR EACH ROW
WHEN NEW.updated_at = OLD.updated_at
BEGIN
    UPDATE transactions
    SET updated_at = CURRENT_TIMESTAMP
    WHERE id = new.id;
END;


CREATE INDEX idx_transactions_account_id
    ON transactions (account_id)
    WHERE deleted_at IS NULL;

CREATE INDEX idx_transactions_category_id
    ON transactions (category_id)
    WHERE deleted_at IS NULL;

CREATE INDEX idx_transactions_currency_code
    ON transactions (currency_code)
    WHERE deleted_at IS NULL;


CREATE TABLE sync_outbox
(
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


CREATE TABLE sync_metadata
(
    entity_type    TEXT PRIMARY KEY,
    last_synced_at TEXT
);


CREATE TABLE app_metadata (
    key   TEXT PRIMARY KEY,
    value TEXT NOT NULL
);
