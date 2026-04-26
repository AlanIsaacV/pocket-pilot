-- Revert card_last_digits del modelo Account.
-- Espejo de backend/migrations/009_drop_account_card_last_digits.sql.

DROP INDEX IF EXISTS idx_accounts_card_last_digits;
ALTER TABLE accounts DROP COLUMN card_last_digits;
