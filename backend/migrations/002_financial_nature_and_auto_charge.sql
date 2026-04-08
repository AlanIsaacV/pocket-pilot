-- Add default_nature to categories
ALTER TABLE categories ADD COLUMN default_nature TEXT NOT NULL DEFAULT '';

-- Add nature to transactions
ALTER TABLE transactions ADD COLUMN nature TEXT NOT NULL DEFAULT '';

-- Add is_auto_charge and is_active to transaction_templates
ALTER TABLE transaction_templates ADD COLUMN is_auto_charge BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE transaction_templates ADD COLUMN is_active BOOLEAN NOT NULL DEFAULT TRUE;
