-- Agrega la dimensión `model` a ai_usage para análisis de costos por
-- modelo concreto. Cada modelo Gemini tiene tarifas distintas (flash-lite
-- vs. flash vs. pro), y al permitir que cada feature use un modelo
-- distinto (ver AI_CHAT_MODEL / NOTIFICATION_PARSER_MODEL en config),
-- necesitamos saber el modelo efectivo de cada llamada para atribuir
-- gasto correctamente.
--
-- Backfill implícito: las filas históricas quedan etiquetadas con
-- 'gemini-3.1-flash-lite-preview', el único modelo en uso antes de esta
-- migración (constante hardcoded en aiassistant/provider.go). Es
-- documentalmente correcto.

ALTER TABLE ai_usage
    ADD COLUMN model TEXT NOT NULL DEFAULT 'gemini-3.1-flash-lite-preview';

-- Índice para queries de costos por modelo (ad-hoc analysis: gasto por
-- modelo en una ventana, breakdown feature × modelo).
CREATE INDEX idx_ai_usage_model_created
    ON ai_usage (model, created_at);
