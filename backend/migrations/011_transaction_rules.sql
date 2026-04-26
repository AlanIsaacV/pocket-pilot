-- transaction_rules: asocia un substring (case-insensitive) en la descripción
-- de una transacción a una categoría del usuario.
--
-- Aplica a transacciones creadas vía notification_capture, CSV import y la
-- AI assistant tool. La regla se aprende automáticamente al aprobar
-- PendingTransactions con categoría asignada (no hay UI de gestión todavía).
--
-- Match: ILIKE '%' || match_text || '%' contra description. Si varias matchean,
-- gana la de mayor priority; en empate, la insertada más recientemente.

CREATE TABLE transaction_rules (
    id          uuid PRIMARY KEY      DEFAULT gen_random_uuid(),
    user_id     uuid         NOT NULL REFERENCES users (id),
    match_text  TEXT         NOT NULL,
    category_id uuid         NOT NULL REFERENCES categories (id),
    priority    INT          NOT NULL DEFAULT 0,
    match_count INT          NOT NULL DEFAULT 0,
    created_at  timestamptz  NOT NULL DEFAULT NOW(),
    updated_at  timestamptz  NOT NULL DEFAULT NOW(),
    deleted_at  timestamptz,

    CONSTRAINT transaction_rules_match_text_not_empty
        CHECK (length(trim(match_text)) > 0)
);

CREATE INDEX idx_transaction_rules_user_updated_at
    ON transaction_rules (user_id, updated_at);

CREATE INDEX idx_transaction_rules_lookup
    ON transaction_rules (user_id, priority DESC, updated_at DESC)
    WHERE deleted_at IS NULL;

CREATE TRIGGER set_updated_at_transaction_rules
    BEFORE UPDATE
    ON transaction_rules
    FOR EACH ROW
EXECUTE FUNCTION trigger_set_updated_at();
