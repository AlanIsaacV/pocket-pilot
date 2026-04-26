-- pending_transactions: sugerencias de transacciones extraídas de
-- notificaciones bancarias capturadas. Local-only en el dispositivo Android.
-- Al aprobarse se materializan como `Transaction` regular vía
-- `TransactionRepository.createTransaction()`.

CREATE TABLE pending_transactions (
    id                       TEXT PRIMARY KEY,
    captured_notification_id TEXT REFERENCES captured_notifications (id),
    suggested_account_id     TEXT REFERENCES accounts (id),
    -- suggested_category_id se agrega vía migración 012 (reparación).
    amount_cents             INTEGER NOT NULL,
    currency_code            TEXT    NOT NULL,
    merchant_description     TEXT,
    card_last_digits         TEXT,
    transaction_type         TEXT    NOT NULL CHECK (transaction_type IN ('income','expense')),
    occurred_at              DATETIME NOT NULL,
    source                   TEXT    NOT NULL CHECK (source IN ('parser_local','parser_server','llm')),
    parser_id                TEXT,
    parser_version           INTEGER,
    confidence               REAL,
    status                   TEXT    NOT NULL DEFAULT 'pending'
                             CHECK (status IN ('pending','approved','dismissed')),
    created_at               DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX idx_pending_transactions_status
    ON pending_transactions (status, created_at);
CREATE INDEX idx_pending_transactions_captured
    ON pending_transactions (captured_notification_id);

-- notification_parsers: cache local de los parsers descargados desde backend.
-- En Fase 2 esta tabla se llena desde un asset embebido (`bbva_mx.json`).
-- En Fase 3 se reemplaza el seed por sync delta-pull desde el servidor.

CREATE TABLE notification_parsers (
    bank_id    TEXT PRIMARY KEY,
    version    INTEGER NOT NULL,
    definition TEXT    NOT NULL,            -- JSON serializado del schema
    updated_at DATETIME NOT NULL,
    deleted_at DATETIME
);
CREATE INDEX idx_notification_parsers_updated_at
    ON notification_parsers (updated_at);
