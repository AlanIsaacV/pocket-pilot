-- account_card_mappings: relaciona (banco, últimos 4 dígitos) → cuenta.
-- Se popula automáticamente al aprobar PendingTransactions con dígitos de
-- tarjeta — el usuario nunca crea estas filas directamente.
--
-- Resolución: SELECT por (user_id, bank_id, last_digits) WHERE deleted_at IS
-- NULL ORDER BY updated_at DESC LIMIT 1. Esto permite que un nuevo INSERT
-- "gane" sobre uno previo del mismo natural key sin requerir UPDATE complejo
-- a través del outbox.

CREATE TABLE account_card_mappings (
    id          uuid PRIMARY KEY      DEFAULT gen_random_uuid(),
    user_id     uuid         NOT NULL REFERENCES users (id),
    bank_id     TEXT         NOT NULL,
    last_digits VARCHAR(4)   NOT NULL,
    account_id  uuid         NOT NULL REFERENCES accounts (id),
    created_at  timestamptz  NOT NULL DEFAULT NOW(),
    updated_at  timestamptz  NOT NULL DEFAULT NOW(),
    deleted_at  timestamptz,

    CONSTRAINT account_card_mappings_last_digits_format
        CHECK (last_digits ~ '^[0-9]{4}$')
);

CREATE INDEX idx_account_card_mappings_user_updated_at
    ON account_card_mappings (user_id, updated_at);

CREATE INDEX idx_account_card_mappings_lookup
    ON account_card_mappings (user_id, bank_id, last_digits, updated_at DESC)
    WHERE deleted_at IS NULL;

CREATE TRIGGER set_updated_at_account_card_mappings
    BEFORE UPDATE
    ON account_card_mappings
    FOR EACH ROW
EXECUTE FUNCTION trigger_set_updated_at();
