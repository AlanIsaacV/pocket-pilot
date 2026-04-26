-- Trazabilidad parser → suggestion. Las nuevas columnas registran qué parser
-- (si fue match local) o qué método de extracción (LLM en Fase 4) produjo
-- la PendingTransaction asociada a esta notificación. Permite, en el
-- futuro, mostrar al usuario la noti origen para feedback ("¿el parser
-- acertó?") y deprecar patterns que generen falsos positivos. SQLite no
-- soporta ADD COLUMN IF NOT EXISTS — se asume idempotencia del runner por
-- número de versión.

ALTER TABLE captured_notifications ADD COLUMN matched_parser_version INTEGER;
ALTER TABLE captured_notifications ADD COLUMN matched_pattern_id TEXT;
ALTER TABLE captured_notifications ADD COLUMN extraction_method TEXT;
