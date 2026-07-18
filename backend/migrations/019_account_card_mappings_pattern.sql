-- Permite asociar una cuenta con el patrón que originó una notificación sin
-- dígitos de tarjeta. Los mapeos por patrón conservan la semántica LWW de
-- inserción de nuevas filas; el índice no impone unicidad.

ALTER TABLE account_card_mappings ADD COLUMN pattern_id TEXT;

CREATE INDEX idx_account_card_mappings_bank_pattern
    ON account_card_mappings (bank_id, pattern_id);

-- Notificaciones sin dígitos de tarjeta (ej. BBVA "COMPRA TDC") solo tienen
-- pattern_id, no last_digits. Relajamos la columna a NULL-able; el CHECK de
-- formato original (`... ~ '^[0-9]{4}$'`) ya es NULL-safe (NULL no viola un
-- CHECK en SQL), así que basta con quitar el NOT NULL y agregar la garantía
-- de que al menos una de las dos dimensiones esté presente.
ALTER TABLE account_card_mappings ALTER COLUMN last_digits DROP NOT NULL;

ALTER TABLE account_card_mappings
    ADD CONSTRAINT account_card_mappings_digits_or_pattern
    CHECK (last_digits IS NOT NULL OR pattern_id IS NOT NULL);
