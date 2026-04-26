-- Agrega la dimensión `feature` a ai_usage para que distintos features (chat
-- conversacional vs. notification_parser) tengan cuotas independientes. El
-- valor por defecto 'chat' preserva la semántica del rate limiter previo:
-- las filas existentes quedan asignadas al feature original sin requerir
-- backfill explícito.

ALTER TABLE ai_usage ADD COLUMN feature TEXT NOT NULL DEFAULT 'chat';

-- Índice para los queries del rate limiter por usuario+feature+ventana
-- temporal (CountRequestsToday / SumTokensThisMonth filtradas por feature).
CREATE INDEX idx_ai_usage_user_feature_created
    ON ai_usage (user_id, feature, created_at);
