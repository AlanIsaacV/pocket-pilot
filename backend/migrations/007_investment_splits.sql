-- Investment splits: forward and reverse stock splits as first-class events.
-- The math walks (lots ∪ splits) chronologically; at each split the FIFO
-- state in flight is adjusted (qty *= ratio, price /= ratio). Splits do not
-- generate transactions (no cash flow). See investments.md §Splits.

CREATE TABLE investment_splits (
    id          uuid PRIMARY KEY      DEFAULT gen_random_uuid(),
    user_id     uuid         NOT NULL REFERENCES users (id),
    holding_id  uuid         NOT NULL REFERENCES investment_holdings (id),
    ratio_num   NUMERIC(18, 8) NOT NULL,
    ratio_den   NUMERIC(18, 8) NOT NULL,
    occurred_at DATE         NOT NULL,
    notes       TEXT,
    created_at  timestamptz  NOT NULL DEFAULT NOW(),
    updated_at  timestamptz  NOT NULL DEFAULT NOW(),
    deleted_at  timestamptz,

    CONSTRAINT investment_splits_ratio_num_positive
        CHECK (ratio_num > 0),
    CONSTRAINT investment_splits_ratio_den_positive
        CHECK (ratio_den > 0)
);

CREATE INDEX idx_investment_splits_user_updated_at
    ON investment_splits (user_id, updated_at);

CREATE INDEX idx_investment_splits_holding_active
    ON investment_splits (holding_id, occurred_at)
    WHERE deleted_at IS NULL;

CREATE TRIGGER set_updated_at_investment_splits
    BEFORE UPDATE
    ON investment_splits
    FOR EACH ROW
EXECUTE FUNCTION trigger_set_updated_at();
