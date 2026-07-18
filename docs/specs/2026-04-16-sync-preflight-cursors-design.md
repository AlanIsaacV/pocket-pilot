# Sync Preflight Cursors Design

## Problem

Every sync cycle, the client always issues one `List<Entity>` RPC per entity type (9 in total) regardless of whether anything actually changed. Even when the response is empty because there are no new deltas for that entity, each call still costs:

- A round-trip over the network (client latency, battery).
- A SQL query on the backend (`WHERE updated_at > $1`), which must scan the user's rows to prove emptiness.
- A serialized response payload with zero items.

The Delta Pull mechanism (`updated_since=last_synced_at`) already minimizes payload size per entity, but it does not eliminate the fan-out cost of asking every entity. In the common case the user opens the app and **nothing has changed** since last sync — yet we pay 9× round-trips to discover that.

## Decision

Add a **per-user, per-entity cursor table** in PostgreSQL that tracks the maximum `updated_at` observed across the user's rows for each sync entity. Expose a new lightweight RPC `SyncService.GetSyncStatus()` that returns the cursors for all entities in a single call. The client uses this preflight call to skip pulls for entities whose server cursor is `<=` the client's local `last_synced_at`.

The cursor is maintained explicitly in the Go repository layer — every `Upsert`/`SoftDelete` method calls a shared `CursorStore.Bump` helper within the same transaction as the write. No PostgreSQL triggers are used, keeping sync logic co-located with the existing repository pattern.

If the preflight call fails for any reason (network, 5xx), the client falls back to the existing flow (pull all 9 entities). The optimization is purely additive — it never blocks sync.

## Scope

- New PostgreSQL table `user_sync_cursors` with migration `002_sync_cursors.sql`.
- New `backend/internal/sync` package with `CursorStore.Bump` and `CursorStore.GetAll`.
- New `SyncService` gRPC service in `proto/pocket_pilot/v1/sync_service.proto` with a single `GetSyncStatus` RPC.
- Wire `CursorStore.Bump` into the `Upsert` and `SoftDelete` methods of all 9 sync-participating repositories: accounts, transactions, categories, goals, tags, budgets, transaction_templates, user_preferences, yield_configs.
- Frontend: new `SyncStatusRemoteService`, preflight step in `SyncService._pullPhase()`, per-entity skip logic, try/catch fallback.
- Integration tests (Go) verifying that every repo's `Upsert` and `SoftDelete` bumps the cursor.

### Out of scope

- Backfill of existing cursors via migration. The project is not yet in production, so existing users will see `epoch` once and do one full pull after migration — acceptable.
- Push notifications / server-initiated invalidation. Cursors are pull-based only.
- Sharing cursors across entity types (e.g., a single global cursor per user). Per-entity granularity preserves the ability to skip untouched entities individually.
- Changes to the existing Delta Pull semantics or pagination behavior.

---

## Design

### 1. Backend — PostgreSQL Schema

**Migration `backend/migrations/002_sync_cursors.sql`:**

```sql
CREATE TABLE user_sync_cursors (
    user_id     UUID        NOT NULL,
    entity_type TEXT        NOT NULL,
    cursor_at   TIMESTAMPTZ NOT NULL,
    PRIMARY KEY (user_id, entity_type)
);

CREATE INDEX idx_user_sync_cursors_user ON user_sync_cursors(user_id);
```

- PK `(user_id, entity_type)` enables `INSERT ... ON CONFLICT (user_id, entity_type) DO UPDATE`.
- `cursor_at` stores the latest `updated_at` observed for any write on the user's rows of that entity.
- The index on `user_id` supports the `GetAll(userID)` read pattern.

### 2. Backend — Sync Package

**New package `backend/internal/sync/`** with two files:

**`cursor.go`:**

```go
package sync

type EntityType string

const (
    EntityAccount             EntityType = "account"
    EntityTransaction         EntityType = "transaction"
    EntityCategory            EntityType = "category"
    EntityGoal                EntityType = "goal"
    EntityTag                 EntityType = "tag"
    EntityBudget              EntityType = "budget"
    EntityTransactionTemplate EntityType = "transaction_template"
    EntityUserPreference      EntityType = "user_preference"
    EntityYieldConfig         EntityType = "yield_config"
)

// AllEntityTypes returns the canonical list used by GetSyncStatus to fill
// missing cursors with epoch values. Add new entity types here.
func AllEntityTypes() []EntityType { ... }

type CursorStore struct { /* holds *sql.DB or dbtx */ }

// Bump upserts the cursor using LWW semantics: only advances if updatedAt
// is strictly greater than the stored value. Safe under concurrent writes.
// Accepts a DBTX so callers can pass either *sql.DB or *sql.Tx for
// atomicity with the triggering write.
func (c *CursorStore) Bump(
    ctx context.Context,
    tx DBTX,
    userID uuid.UUID,
    entityType EntityType,
    updatedAt time.Time,
) error

// GetAll returns cursors for all entity types, filling missing rows with
// time.Unix(0,0) so the client sees a predictable complete map.
func (c *CursorStore) GetAll(
    ctx context.Context,
    userID uuid.UUID,
) (map[EntityType]time.Time, error)
```

**SQL for `Bump`:**

```sql
INSERT INTO user_sync_cursors (user_id, entity_type, cursor_at)
VALUES ($1, $2, $3)
ON CONFLICT (user_id, entity_type) DO UPDATE
SET cursor_at = EXCLUDED.cursor_at
WHERE user_sync_cursors.cursor_at < EXCLUDED.cursor_at
```

The `WHERE ... < EXCLUDED.cursor_at` guard prevents out-of-order writes from regressing the cursor (mirrors the LWW pattern already used on entity upserts).

**`service.go`** — gRPC service implementation (see §4).

### 3. Backend — Proto Contract

**New file `proto/pocket_pilot/v1/sync_service.proto`:**

```proto
syntax = "proto3";
package pocket_pilot.v1;

import "google/protobuf/timestamp.proto";

service SyncService {
  rpc GetSyncStatus(GetSyncStatusRequest) returns (GetSyncStatusResponse);
}

message GetSyncStatusRequest {}

message GetSyncStatusResponse {
  // entity_type → server's latest cursor for that entity.
  // Always contains every known entity_type. Entities with no data
  // report `1970-01-01T00:00:00Z`.
  map<string, google.protobuf.Timestamp> cursors = 1;
  // Server's current time, useful for debugging / drift detection.
  google.protobuf.Timestamp synced_at = 2;
}
```

No `updated_since` or paging — the response is O(9) rows, tiny.

### 4. Backend — Handler

**`internal/sync/service.go`:**

- Register `SyncServiceServer` in `main.go` alongside the existing services.
- `GetSyncStatus` reads `userID` from request context (JWT middleware), calls `CursorStore.GetAll(userID)`, and fills missing entity types with `time.Unix(0, 0)`.

### 5. Backend — Repository Integration

For each of the 9 sync-participating repos, modify `Upsert` and `SoftDelete` methods:

```go
// Before: just the INSERT/UPDATE
// After:
func (r *accountRepo) Upsert(ctx context.Context, userID uuid.UUID, acc *Account) (*Account, bool, error) {
    tx, err := r.db.BeginTx(ctx, nil)
    if err != nil { return nil, false, err }
    defer tx.Rollback()

    // ... existing INSERT ... ON CONFLICT ... (but using tx)

    if err := r.cursor.Bump(ctx, tx, userID, sync.EntityAccount, acc.UpdatedAt); err != nil {
        return nil, false, err
    }

    if err := tx.Commit(); err != nil { return nil, false, err }
    return result, conflictResolved, nil
}
```

**Key invariants:**

- The bump MUST run in the same transaction as the write. If the write rolls back, the cursor must not move.
- The bump uses the `updated_at` of the write (the one that was actually persisted after LWW resolution on conflict). When `conflict_resolved=true` and the server's existing row is newer, the repo's resulting `updated_at` is the server's existing value — the cursor already reflects that, so re-bumping with the same value is a no-op (the `WHERE ... <` guard short-circuits).
- `SoftDelete` uses the new `deleted_at` timestamp as both `updated_at` and cursor input (consistent with the existing LWW handling of soft-deletes).

**Repos to modify:**

| Repo | Files to touch |
|------|----------------|
| accounts | `backend/internal/account/repository.go` |
| transactions | `backend/internal/transaction/repository.go` |
| categories | `backend/internal/category/repository.go` |
| goals | `backend/internal/goal/repository.go` |
| tags | `backend/internal/tag/repository.go` |
| budgets | `backend/internal/budget/repository.go` |
| transaction_templates | `backend/internal/transactiontemplate/repository.go` |
| user_preferences | `backend/internal/userpreference/repository.go` |
| yield_configs | `backend/internal/yieldconfig/repository.go` |

`user_preferences` uses `pref_key` (string) as its `entity_id` rather than a UUID; this is irrelevant to the cursor mechanism since cursors are per-entity-type, not per-row. No special handling required.

**Constructor wiring:** each repo's constructor accepts a `*sync.CursorStore` (or an interface it satisfies). The DI wiring in `main.go` builds one shared `CursorStore` and passes it into every repo.

### 6. Backend — Tests

Integration tests in `backend/internal/sync/cursor_integration_test.go`:

- For each of the 9 entity types, a test that:
  1. Sets up a test DB with the entity's table and `user_sync_cursors`.
  2. Calls the repo's `Upsert` with a fresh row.
  3. Asserts that `CursorStore.GetAll(userID)[entityType]` equals the row's `updated_at`.
- A matching test for `SoftDelete`.
- A test that calling `Upsert` with an older `updated_at` (simulating LWW rejection) does NOT regress the cursor.

These tests live next to the sync package and use `testcontainers` (or the existing test DB helper — match the convention already in use in `backend/internal/*/repository_test.go`).

### 7. Frontend — Data Layer

**New file `frontend/lib/src/core/sync/sync_status_remote_service.dart`:**

```dart
class SyncStatusRemoteService {
  final SyncServiceClient _client;

  Future<Map<String, DateTime>> getSyncStatus() async {
    final response = await _client.getSyncStatus(GetSyncStatusRequest());
    return {
      for (final entry in response.cursors.entries)
        entry.key: entry.value.toDateTime().toUtc(),
    };
  }
}
```

No local persistence — the preflight result is ephemeral, consumed once per sync cycle.

### 8. Frontend — SyncService Integration

**Modify `frontend/lib/src/core/sync/sync_service.dart`:**

```dart
Future<void> _pullPhase() async {
  Map<String, DateTime>? serverCursors;
  try {
    serverCursors = await _statusService.getSyncStatus();
  } catch (e, st) {
    _log.warning('GetSyncStatus failed, falling back to full pull', e, st);
    serverCursors = null;
  }

  for (final handler in _handlers) {
    final localCursor = await _metadataStore.getLastSyncedAt(handler.entityType);

    // Skip only when we have both a preflight result AND a local cursor.
    // A null local cursor means first-ever sync → always pull.
    if (serverCursors != null && localCursor != null) {
      final serverCursor = serverCursors[handler.entityType];
      if (serverCursor != null && !serverCursor.isAfter(localCursor)) {
        _log.fine('Skipping pull for ${handler.entityType}: no server changes');
        continue;
      }
    }

    await _pullEntity(handler, localCursor);
  }
}
```

**Wiring** in `main.dart`:
- Build one `SyncServiceClient` (gRPC stub) alongside the existing service clients.
- Construct `SyncStatusRemoteService(client)`.
- Inject into `SyncService` constructor.

### 9. Frontend — Observability

- `_log.fine` log line per skipped entity so we can verify the optimization is firing.
- Expose a counter on `SyncService` (e.g., `int lastCycleSkippedCount`) surfaced in the existing Sync Status screen as a small diagnostic line: "N/9 entidades saltadas en último ciclo". Purely informational, helps confirm behavior during manual testing.

---

## Fallback Behavior Matrix

| Scenario | Behavior |
|----------|----------|
| `GetSyncStatus` succeeds, all cursors `<=` local | Skip all 9 pulls. 1 RPC total. |
| `GetSyncStatus` succeeds, subset changed | Pull only changed entities. 1 + K RPCs. |
| `GetSyncStatus` fails (network/5xx) | Log warning, pull all 9 as before. Current behavior preserved. |
| Local `last_synced_at` is null (first sync) | Always pull regardless of preflight result. |
| New entity added in future (client doesn't know about it yet) | Unknown keys in the response map are ignored. Safe forward-compat. |
| New entity added server-side but `AllEntityTypes()` not updated | Cursor is bumped on writes, but `GetAll` will not return it. Frontend falls back to normal pull for that entity. Fix: update `AllEntityTypes()`. |

---

## Verification

Once implemented, a manual verification sequence:

1. Clean-install the app, log in, observe the first sync: preflight returns `epoch` for all entities, all 9 pulls happen (expected).
2. Close the app, reopen immediately: preflight returns current cursors, all 9 entities report "no changes", 0 pulls happen (expected). Sync Status screen shows "9/9 entidades saltadas".
3. Create a transaction on another device, wait for it to sync to the server. Reopen first device: preflight shows `transaction` cursor advanced; only that entity is pulled.
4. Shut down the backend. Trigger a manual sync. Preflight fails; client falls back to the existing flow and logs the warning. Verify sync still completes (will fail per-entity too in this test, but the *flow* is the point).

---

## Consequences

- Cold-sync (nothing changed) cost drops from 9 RPCs to 1 RPC. Backend load drops proportionally.
- Every write in a sync-participating repo becomes transactional (if it was not already) and does one extra row upsert. Negligible overhead; the cursor row is in the same database.
- Adding a new sync-participating entity now requires three touches instead of two: proto/repo/handler **plus** `AllEntityTypes()` in the sync package and a `CursorStore.Bump` call in its repo. The integration test suite makes it obvious when the bump is missing.
- The `user_sync_cursors` table grows `O(users × entity_types)` — bounded and tiny (~9 rows per user).
- The feature is purely additive: if the new RPC or helper is removed, the system degrades to the current behavior.
