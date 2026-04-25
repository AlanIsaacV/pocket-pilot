-- Investment splits: forward and reverse stock splits as first-class events.
-- Mirror del backend (007_investment_splits.sql) sin user_id.
-- See docs/context/architecture/investments.md §Splits.

CREATE TABLE investment_splits (
    id          TEXT PRIMARY KEY,
    holding_id  TEXT           NOT NULL REFERENCES investment_holdings (id),
    ratio_num   NUMERIC(18, 8) NOT NULL,
    ratio_den   NUMERIC(18, 8) NOT NULL,
    occurred_at DATE           NOT NULL,
    notes       TEXT,
    created_at  DATETIME       NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at  DATETIME       NOT NULL DEFAULT CURRENT_TIMESTAMP,
    deleted_at  DATETIME,

    CHECK (ratio_num > 0),
    CHECK (ratio_den > 0)
);

CREATE INDEX idx_investment_splits_holding
    ON investment_splits (holding_id, occurred_at)
    WHERE deleted_at IS NULL;

CREATE INDEX idx_investment_splits_updated_at
    ON investment_splits (updated_at);

CREATE TRIGGER set_updated_at_investment_splits
    AFTER UPDATE
    ON investment_splits
    FOR EACH ROW
    WHEN new.updated_at = old.updated_at
BEGIN
    UPDATE investment_splits
    SET updated_at = CURRENT_TIMESTAMP
    WHERE id = new.id;
END;
