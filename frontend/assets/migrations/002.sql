ALTER TABLE categories ADD COLUMN default_nature TEXT NOT NULL DEFAULT '';
ALTER TABLE transactions ADD COLUMN nature TEXT NOT NULL DEFAULT '';
ALTER TABLE transaction_templates ADD COLUMN is_auto_charge INTEGER NOT NULL DEFAULT 0;
ALTER TABLE transaction_templates ADD COLUMN is_active INTEGER NOT NULL DEFAULT 1;
