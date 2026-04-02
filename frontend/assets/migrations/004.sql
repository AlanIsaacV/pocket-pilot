CREATE TABLE goals (
    id                  TEXT PRIMARY KEY,
    name                TEXT     NOT NULL,

    target_amount_cents INTEGER  NOT NULL,
    saved_amount_cents  INTEGER  NOT NULL DEFAULT 0,

    target_date         DATE     NOT NULL,

    created_at          DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at          DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    deleted_at          DATETIME
);

CREATE INDEX idx_goals_target_date_active
    ON goals (target_date)
    WHERE deleted_at IS NULL;

CREATE INDEX idx_goals_updated_at
    ON goals (updated_at);

CREATE TRIGGER set_updated_at_goals
    AFTER UPDATE
    ON goals
    FOR EACH ROW
    WHEN new.updated_at = old.updated_at
BEGIN
    UPDATE goals
    SET updated_at = CURRENT_TIMESTAMP
    WHERE id = new.id;
END;
