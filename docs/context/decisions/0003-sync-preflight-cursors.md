# ADR 0003: Sync Preflight Cursors

## Status
Accepted

## Context
Delta Pull (ADR 0001) already minimizes payload size per entity by filtering on `updated_at > last_synced_at`. However, every sync cycle still issues one `List<Entity>` RPC per entity type (9 in total) even when nothing has changed on any of them. In the common case — user reopens the app after a short idle — every one of those 9 calls pays for:

- A network round-trip (client latency, battery).
- A SQL scan on the backend (`WHERE updated_at > $1`) that proves emptiness.
- A zero-item gRPC response.

We wanted to reduce cold-sync cost without changing the Delta Pull semantics or introducing server-to-client push.

## Decision
Add a per-user, per-entity cursor table in PostgreSQL (`user_sync_cursors`) and a lightweight `SyncService.GetSyncStatus` RPC that returns every cursor in one call. The client runs this preflight once per sync cycle and skips the per-entity pull when `server_cursor <= local_last_synced_at`.

### Cursor maintenance
The cursor is owned by the **Go repository layer**, not by PostgreSQL triggers. Every `Upsert` / `SoftDelete` method wraps its write in a `pool.Begin(ctx)` transaction and calls `sync.CursorStore.Bump(ctx, tx, userID, sync.EntityX, updatedAt)` within the same tx. The bump query is:

```sql
INSERT INTO user_sync_cursors (user_id, entity_type, cursor_at)
VALUES ($1, $2, $3)
ON CONFLICT (user_id, entity_type) DO UPDATE
SET cursor_at = EXCLUDED.cursor_at
WHERE user_sync_cursors.cursor_at < EXCLUDED.cursor_at
```

The `WHERE ... < EXCLUDED.cursor_at` guard mirrors the LWW pattern used on the entities themselves and prevents regressions under concurrent writes.

### Why repository-layer (not triggers)
- Sync semantics already live next to the repositories (LWW upsert SQL, `SoftDelete` methods). Dispersing them into DB triggers would break the existing convention.
- Easier to unit/integration-test (mock `CursorStore` or run against a disposable DB).
- No magic: a new engineer adding a sync-participating entity sees the same `cursor.Bump` call they have to replicate.

The trade-off: adding a new sync entity requires remembering three things (proto, repo, `AllEntityTypes()`). The integration test suite makes the omission loud.

### Why preflight RPC (not piggyback in every response)
A preflight dedicated call reduces the best case (nothing changed) from 9 RPCs to 1. Piggybacking cursors in existing `List*` responses would still require the first RPC per entity, defeating the purpose.

### Fallback
If `GetSyncStatus` fails, the client logs a warning and falls back to the previous flow (pull all 9). The feature is purely additive — removing it restores current behavior.

## Consequences

### Positive
- Cold-sync (nothing changed) drops from 9 RPCs to 1.
- Backend load drops proportionally: 9 `SELECT ... WHERE updated_at > $1` queries replaced by one bounded `SELECT ... FROM user_sync_cursors WHERE user_id = $1`.
- Per-entity granularity: if only transactions changed, the other 8 entities still skip.

### Negative
- Every write in the sync path becomes transactional. The 9 repos that were non-tx on the happy path (`accounts`, `categories`, `tag`, `transaction_templates`, `goals`, `budgets`, `yieldconfig`, `userpreference` upserts — `transaction.SoftDelete` already used a tx) now pay one extra `BEGIN`/`COMMIT` per write. Overhead is negligible compared to the cursor bump being in the same round-trip to PG.
- Adding a new sync entity requires appending to `sync.AllEntityTypes()` in addition to the usual proto + repo + handler. Forgetting this is caught by the per-repo integration test suite.
- The `user_sync_cursors` table grows `O(users × entity_types)` — bounded at ~9 rows per user.

### Neutral
- No migration backfill was performed (project is pre-production). Existing users see `epoch` on the first preflight after the migration and do one full pull, identical to a cold install. Acceptable.

## References
- Spec: `docs/superpowers/specs/2026-04-16-sync-preflight-cursors-design.md`
- Plan: `docs/superpowers/plans/2026-04-16-sync-preflight-cursors.md`
- Migration: `backend/migrations/002_sync_cursors.sql`
- Package: `backend/internal/sync/`
- Proto: `proto/pocket_pilot/v1/sync_service.proto`
- Frontend preflight: `frontend/lib/src/core/sync/sync_service.dart` (`_runSyncLoop`)
