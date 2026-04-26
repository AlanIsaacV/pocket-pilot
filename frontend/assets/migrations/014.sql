-- parser_feedback: señal de calidad por sugerencia. Mirror del schema BE
-- (mig 015). Push-only: el cliente inserta acá al aprobar/descartar y el
-- sync handler drena via outbox; saveLocally es no-op (no se hace pull de
-- feedback hacia el cliente). Booleans almacenados como INTEGER 0|1|NULL.

CREATE TABLE parser_feedback (
    id                       TEXT PRIMARY KEY,
    pending_transaction_id   TEXT NOT NULL,
    captured_notification_id TEXT,
    bank_id                  TEXT,
    pattern_id               TEXT,
    parser_version           INTEGER,
    extraction_method        TEXT,
    was_helpful              INTEGER,                -- 0|1|NULL (tri-estado)
    account_changed          INTEGER NOT NULL DEFAULT 0,
    category_changed         INTEGER NOT NULL DEFAULT 0,
    amount_changed           INTEGER NOT NULL DEFAULT 0,
    description_changed      INTEGER NOT NULL DEFAULT 0,
    was_dismissed            INTEGER NOT NULL DEFAULT 0,
    created_at               TEXT NOT NULL,
    updated_at               TEXT NOT NULL,
    deleted_at               TEXT,
    UNIQUE (pending_transaction_id)
);

CREATE INDEX idx_parser_feedback_pattern
    ON parser_feedback (bank_id, pattern_id);
