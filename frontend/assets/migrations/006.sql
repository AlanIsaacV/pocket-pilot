-- card_last_digits: últimos 4 dígitos de la tarjeta asociada.
-- Espejo del backend (008_account_card_last_digits.sql) sin user_id.
-- Usado por la feature de captura de notificaciones bancarias.

ALTER TABLE accounts ADD COLUMN card_last_digits TEXT
    CHECK (card_last_digits IS NULL OR card_last_digits GLOB '[0-9][0-9][0-9][0-9]');

CREATE INDEX idx_accounts_card_last_digits
    ON accounts (card_last_digits)
    WHERE card_last_digits IS NOT NULL AND deleted_at IS NULL;
