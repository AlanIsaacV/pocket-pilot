ALTER TABLE transactions
    ADD COLUMN source TEXT NOT NULL DEFAULT 'manual';
