CREATE TABLE goals (
    id                  uuid PRIMARY KEY      DEFAULT gen_random_uuid(),
    user_id             uuid         NOT NULL,
    name                text         NOT NULL,

    target_amount_cents bigint       NOT NULL,
    saved_amount_cents  bigint       NOT NULL DEFAULT 0,

    target_date         date         NOT NULL,

    created_at          timestamptz  NOT NULL DEFAULT now(),
    updated_at          timestamptz  NOT NULL DEFAULT now(),
    deleted_at          timestamptz
);

CREATE INDEX idx_goals_user_id
    ON goals (user_id)
    WHERE deleted_at IS NULL;

CREATE INDEX idx_goals_user_updated_at
    ON goals (user_id, updated_at);

CREATE INDEX idx_goals_user_target_date_active
    ON goals (user_id, target_date)
    WHERE deleted_at IS NULL;

CREATE TRIGGER set_updated_at_goals
    BEFORE UPDATE
    ON goals
    FOR EACH ROW
EXECUTE FUNCTION trigger_set_updated_at();
