-- 002_sync_cursors.sql
-- Per-user, per-entity cursor table feeding SyncService.GetSyncStatus.
-- A cursor is bumped by the owning repository inside the same transaction
-- as the Upsert/SoftDelete that produced a new updated_at.
CREATE TABLE user_sync_cursors (
    user_id     uuid        NOT NULL,
    entity_type TEXT        NOT NULL,
    cursor_at   timestamptz NOT NULL,
    PRIMARY KEY (user_id, entity_type)
);

CREATE INDEX idx_user_sync_cursors_user ON user_sync_cursors(user_id);
