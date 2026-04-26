-- card_last_digits: últimos 4 dígitos de la tarjeta asociada a la cuenta.
-- Solo aplica cuando type ∈ {bank, credit_card}; nullable en otros casos.
-- Usado por la captura de notificaciones bancarias para emparejar
-- automáticamente una notificación recibida con una cuenta del usuario.

ALTER TABLE accounts
    ADD COLUMN card_last_digits VARCHAR(4);

ALTER TABLE accounts
    ADD CONSTRAINT accounts_card_last_digits_format
        CHECK (card_last_digits IS NULL OR card_last_digits ~ '^[0-9]{4}$');

CREATE INDEX idx_accounts_user_card_digits
    ON accounts (user_id, card_last_digits)
    WHERE card_last_digits IS NOT NULL AND deleted_at IS NULL;
