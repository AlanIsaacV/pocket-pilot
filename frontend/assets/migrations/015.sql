-- Retención 90-day en captured_notifications. El sweeper Dart corre cada
-- 24h en app launch (ver retention_sweeper.dart) y NULLea title/text/big_text
-- de filas con posted_at < now-90d. La fila se preserva con todos sus
-- metadatos (status, parser_version, pattern_id, extraction_method,
-- pending_tx_id) para mantener trazabilidad y agregados de parser_feedback.
-- purged_at marca el momento de la purga; queries de bandeja filtran
-- WHERE purged_at IS NULL para no mostrar filas sin texto.

ALTER TABLE captured_notifications ADD COLUMN purged_at TEXT;

CREATE INDEX idx_captured_notifications_posted_active
    ON captured_notifications (posted_at)
    WHERE purged_at IS NULL;
