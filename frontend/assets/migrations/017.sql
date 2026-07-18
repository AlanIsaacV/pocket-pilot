-- Espejo local de pattern_id para resolver notificaciones sin dígitos de
-- tarjeta. El índice no es único: la resolución elige la fila activa más
-- reciente por updated_at.
--
-- Además, las notificaciones sin dígitos (ej. BBVA "COMPRA TDC") solo
-- resuelven por (bank_id, pattern_id); last_digits pasa a ser NULL-able.
-- SQLite no soporta DROP NOT NULL / DROP CONSTRAINT, así que reconstruimos
-- la tabla completa (patrón estándar de "12 pasos" de sqlite.org) en vez de
-- solo agregar la columna.

CREATE TABLE account_card_mappings_new (
    id          TEXT PRIMARY KEY,
    bank_id     TEXT     NOT NULL,
    last_digits TEXT     CHECK (last_digits IS NULL OR last_digits GLOB '[0-9][0-9][0-9][0-9]'),
    pattern_id  TEXT,
    account_id  TEXT     NOT NULL REFERENCES accounts (id),
    created_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    deleted_at  DATETIME,

    CHECK (last_digits IS NOT NULL OR pattern_id IS NOT NULL)
);

INSERT INTO account_card_mappings_new (
    id, bank_id, last_digits, pattern_id, account_id, created_at, updated_at, deleted_at
)
SELECT id, bank_id, last_digits, NULL, account_id, created_at, updated_at, deleted_at
FROM account_card_mappings;

DROP TABLE account_card_mappings;

ALTER TABLE account_card_mappings_new RENAME TO account_card_mappings;

CREATE INDEX idx_account_card_mappings_lookup
    ON account_card_mappings (bank_id, last_digits, updated_at DESC)
    WHERE deleted_at IS NULL;
CREATE INDEX idx_account_card_mappings_updated_at
    ON account_card_mappings (updated_at);
CREATE INDEX idx_account_card_mappings_bank_pattern
    ON account_card_mappings (bank_id, pattern_id);

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
