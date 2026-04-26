-- captured_notifications: notificaciones push del SO interceptadas por el
-- NotificationListenerService nativo Android. Esta tabla es local-only (no se
-- sincroniza con backend); solo el dispositivo que las captura las almacena.
--
-- Flujo:
--   1. NLS recibe StatusBarNotification de un paquete bancario en allowlist.
--   2. NLS escribe directo en SQLite (Kotlin) → status='received'.
--   3. Al abrir la app, el isolate Dart procesa las pendientes:
--      - Aplica parsers locales → status='matched_local' (Fase 2)
--      - Si no match, llama backend → status='matched_server' o 'llm_used' (Fase 4)
--      - Si is_transaction=false → status='ignored'
--      - Si nada produce campos válidos → status='unparseable'
--   4. Cuando se aprueba una PendingTransaction → status='consumed'.
--
-- pending_tx_id queda en NULL hasta que un parser/LLM produce una sugerencia.

CREATE TABLE captured_notifications (
    id            TEXT PRIMARY KEY,
    package_name  TEXT NOT NULL,
    title         TEXT,
    text          TEXT,
    big_text      TEXT,
    posted_at     DATETIME NOT NULL,
    status        TEXT NOT NULL DEFAULT 'received'
                  CHECK (status IN ('received','matched_local','matched_server','llm_used','unparseable','ignored','consumed')),
    pending_tx_id TEXT,
    created_at    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX idx_captured_notifications_status
    ON captured_notifications (status, posted_at);

-- Dedupe entre minuto y hash del texto para evitar que la misma notificación
-- (BBVA emite título + expandida en el mismo evento) se procese dos veces.
CREATE INDEX idx_captured_notifications_dedupe
    ON captured_notifications (package_name, posted_at);
