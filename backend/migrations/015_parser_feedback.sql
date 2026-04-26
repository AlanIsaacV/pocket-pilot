-- parser_feedback: señal de calidad por sugerencia. Se inserta una fila por
-- cada decisión final del usuario (aprobar O descartar) en PendingReviewSheet.
-- Combina un thumb explícito opcional (was_helpful) con flags derivados que
-- comparan suggested_* vs final. Habilita análisis para el admin que promueve
-- candidate_parsers a notification_parsers.
--
-- Tabla push-only: el cliente envía vía outbox; el servidor jamás hace pull
-- de feedback hacia el cliente (saveLocally es no-op del lado FE).

CREATE TABLE parser_feedback (
    id                       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id                  uuid NOT NULL REFERENCES users (id),

    -- pending_transaction_id es un string (el cliente lo genera para sus
    -- PendingTransactions locales) — no es un uuid validado server-side.
    pending_transaction_id   TEXT NOT NULL,
    captured_notification_id TEXT,

    -- Snapshot de trazabilidad. Cualquier campo puede venir vacío/null si la
    -- sugerencia provenía de una ruta sin parser identificable.
    bank_id                  TEXT,
    pattern_id               TEXT,
    parser_version           INTEGER,
    extraction_method        TEXT,

    -- Tri-estado: NULL si el usuario no tocó el thumb.
    was_helpful              BOOLEAN,

    account_changed          BOOLEAN NOT NULL DEFAULT FALSE,
    category_changed         BOOLEAN NOT NULL DEFAULT FALSE,
    amount_changed           BOOLEAN NOT NULL DEFAULT FALSE,
    description_changed      BOOLEAN NOT NULL DEFAULT FALSE,

    was_dismissed            BOOLEAN NOT NULL DEFAULT FALSE,

    created_at               timestamptz NOT NULL DEFAULT NOW(),
    updated_at               timestamptz NOT NULL DEFAULT NOW(),
    deleted_at               timestamptz,

    CONSTRAINT parser_feedback_extraction_method_check
        CHECK (extraction_method IS NULL OR extraction_method IN ('local','llm')),

    -- Salvaguarda: un row por (user, pending). El LWW real se resuelve por id
    -- (el cliente reusa el id si re-upserta el mismo pending).
    CONSTRAINT parser_feedback_user_pending_unique
        UNIQUE (user_id, pending_transaction_id)
);

CREATE INDEX idx_parser_feedback_user_updated_at
    ON parser_feedback (user_id, updated_at);

-- Lookup de análisis por parser/pattern (admin queries).
CREATE INDEX idx_parser_feedback_pattern
    ON parser_feedback (user_id, bank_id, pattern_id)
    WHERE deleted_at IS NULL;

CREATE TRIGGER set_updated_at_parser_feedback
    BEFORE UPDATE
    ON parser_feedback
    FOR EACH ROW
EXECUTE FUNCTION trigger_set_updated_at();
