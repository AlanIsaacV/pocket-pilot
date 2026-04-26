-- Retención 90-day en candidate_parsers. Aunque la tabla ya es anónima
-- (sin user_id), los samples capturan el texto crudo de la notificación
-- bancaria que el LLM intentó parsear (montos, merchants, últimos 4
-- dígitos). Esta migración añade un cuarto status `purged` y una columna
-- `purged_at` para marcar cuándo el sweeper anonimizó los sample_*. El
-- `proposed_regex`/`extracted_fields` se preservan: no contienen PII y
-- siguen siendo útiles para análisis agregado del loop LLM.
--
-- El sweeper Go (cmd/server/main.go con time.NewTicker(24h)) ejecuta el
-- UPDATE; ver candidate_repo.go::PurgeOldSamples.

ALTER TABLE candidate_parsers
    DROP CONSTRAINT candidate_parsers_status_check;

ALTER TABLE candidate_parsers
    ADD CONSTRAINT candidate_parsers_status_check
        CHECK (status IN ('pending', 'promoted', 'rejected', 'purged'));

ALTER TABLE candidate_parsers
    ADD COLUMN purged_at TIMESTAMPTZ;

-- Índice parcial para el sweeper: la query típica es
-- WHERE status='pending' AND created_at < $cutoff. El índice existente
-- idx_candidate_parsers_status_bank lo cubre (status como prefijo), así
-- que no hace falta uno nuevo.
