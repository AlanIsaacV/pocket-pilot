-- Revert card_last_digits del modelo de Account.
-- Razón: una cuenta puede tener múltiples tarjetas (física + digital + efímeras),
-- por lo que un campo único no modela la realidad. La asociación se mueve a
-- la tabla `account_card_mappings` (migración 010), populada en background al
-- aprobar PendingTransactions ("learn from approval").

DROP INDEX IF EXISTS idx_accounts_user_card_digits;
ALTER TABLE accounts DROP CONSTRAINT IF EXISTS accounts_card_last_digits_format;
ALTER TABLE accounts DROP COLUMN IF EXISTS card_last_digits;
