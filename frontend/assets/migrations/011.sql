-- transaction_rules: espejo local de la tabla del backend.
-- Aplica substring case-insensitive de match_text contra description.

CREATE TABLE transaction_rules (
    id          TEXT PRIMARY KEY,
    match_text  TEXT     NOT NULL CHECK (length(trim(match_text)) > 0),
    category_id TEXT     NOT NULL REFERENCES categories (id),
    priority    INTEGER  NOT NULL DEFAULT 0,
    match_count INTEGER  NOT NULL DEFAULT 0,
    created_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    deleted_at  DATETIME
);
CREATE INDEX idx_transaction_rules_lookup
    ON transaction_rules (priority DESC, updated_at DESC)
    WHERE deleted_at IS NULL;
CREATE INDEX idx_transaction_rules_updated_at
    ON transaction_rules (updated_at);
CREATE TRIGGER set_updated_at_transaction_rules
    AFTER UPDATE
    ON transaction_rules
    FOR EACH ROW
    WHEN new.updated_at = old.updated_at
BEGIN
    UPDATE transaction_rules
    SET updated_at = CURRENT_TIMESTAMP
    WHERE id = new.id;
END;
