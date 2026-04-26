-- account_card_mappings: espejo local de la tabla del backend.
-- Sin user_id (la DB local pertenece a un solo usuario).
-- Resolución: SELECT WHERE bank_id=? AND last_digits=? AND deleted_at IS NULL
-- ORDER BY updated_at DESC LIMIT 1.

CREATE TABLE account_card_mappings (
    id          TEXT PRIMARY KEY,
    bank_id     TEXT     NOT NULL,
    last_digits TEXT     NOT NULL CHECK (last_digits GLOB '[0-9][0-9][0-9][0-9]'),
    account_id  TEXT     NOT NULL REFERENCES accounts (id),
    created_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    deleted_at  DATETIME
);
CREATE INDEX idx_account_card_mappings_lookup
    ON account_card_mappings (bank_id, last_digits, updated_at DESC)
    WHERE deleted_at IS NULL;
CREATE INDEX idx_account_card_mappings_updated_at
    ON account_card_mappings (updated_at);
CREATE TRIGGER set_updated_at_account_card_mappings
    AFTER UPDATE
    ON account_card_mappings
    FOR EACH ROW
    WHEN new.updated_at = old.updated_at
BEGIN
    UPDATE account_card_mappings
    SET updated_at = CURRENT_TIMESTAMP
    WHERE id = new.id;
END;
