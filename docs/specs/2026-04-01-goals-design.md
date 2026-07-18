# Financial Goals Design

## Summary

This design adds a new syncable entity, `goals`, to model future financial objectives (for example: laptop, travel, annual medical insurance).

Goals are logical liquidity allocations, not balances tied to a specific bank account. The client computes progress and monthly savings projections in real time. Persisted data remains simple and sync-friendly; derived metrics are never stored.

The solution follows the existing Pocket Pilot offline-first architecture:

- Local-first writes in SQLite.
- Outbox push + delta pull sync.
- Last Write Wins (LWW) conflict resolution by `updated_at`.
- Amounts stored as integer cents (`*_cents`).

## Scope and Non-Goals

### In scope

- New `goals` schema in PostgreSQL and SQLite.
- New gRPC contract `GoalService` with `ListGoals`, `UpsertGoal`, `DeleteGoal`.
- New backend module `internal/goal` (handler/repository/validation/model).
- New frontend feature module `features/goals` with domain/data/ui layers.
- Goal math in Flutter domain/viewmodel:
  - progress percentage
  - months remaining
  - monthly required cents
  - overdue flag
  - dashboard total monthly required aggregation

### Out of scope

- Complex new goals UI flows or visual redesign.
- Moving projection logic to backend.
- Any change to global sync strategy (LWW + outbox remains unchanged).

## Confirmed Product Decisions

| Decision | Choice |
|---|---|
| Service contract shape | Standard sync pattern: `List + Upsert + Delete` |
| `monthly_required_cents` rounding | `ceil` (never underestimate) |
| Past-due goals UX | Immediate monthly requirement + explicit overdue flag |
| `category_id` when category is soft-deleted | Keep `category_id` for historical linkage |
| Goal validations | Enforce all: non-empty name, valid date, amount bounds |
| `months_remaining` rule | Calendar-month difference, ignore day-of-month, minimum `1` |
| Backend FK pre-check on `category_id` | No explicit pre-validation query; rely on DB FK |
| Month-calculation timezone | Use device local calendar month (`DateTime.now()` local) |
| `updated_at` semantics | LWW comparison uses request timestamp; persisted `updated_at` follows DB trigger on updates |

## Architecture

### High-level flow

1. User creates/updates/deletes a goal locally.
2. Repository writes SQLite and enqueues an outbox entry (`entity_type=goal`).
3. Sync cycle pulls remote changes (`ListGoals(updated_since)`), then pushes outbox (`UpsertGoal`/`DeleteGoal`).
4. Backend applies LWW by `updated_at`.
5. Flutter computes derived goal metrics on read for list/dashboard rendering.

### Unit boundaries

- `goals` domain model: normalized persistence mapping + derived math getters.
- `goals` data layer: local store, remote service, repository, sync handler.
- `goals` view model: local-first loading, sync trigger, aggregate monthly requirement.
- Backend `goal` service: persistence and wire contract only (no projection math).

Each unit remains understandable and testable independently.

## Data Model Design

### PostgreSQL

Add `backend/migrations/004_goals.sql`:

```sql
CREATE TABLE goals (
    id                  uuid PRIMARY KEY      DEFAULT gen_random_uuid(),
    user_id             uuid         NOT NULL,
    name                text         NOT NULL,

    target_amount_cents bigint       NOT NULL,
    saved_amount_cents  bigint       NOT NULL DEFAULT 0,

    target_date         date         NOT NULL,
    category_id         uuid                  REFERENCES categories (id),

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
```

`user_id` intentionally mirrors existing syncable tables in this codebase: it is required and indexed, but it is not declared as an FK to a users table.

`set_updated_at_goals` follows the existing backend convention: accepted updates stamp persisted `updated_at` with server `NOW()`.

### SQLite

Add `frontend/assets/migrations/004.sql`:

```sql
CREATE TABLE goals (
    id                  TEXT PRIMARY KEY,
    name                TEXT     NOT NULL,

    target_amount_cents INTEGER  NOT NULL,
    saved_amount_cents  INTEGER  NOT NULL DEFAULT 0,

    target_date         DATE     NOT NULL,
    category_id         TEXT              REFERENCES categories (id),

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
```

Also bump `DatabaseHelper._version` from `3` to `4`.

## gRPC Contract Design

Add `proto/pocket_pilot/v1/goal_service.proto`:

```proto
syntax = "proto3";

package pocket_pilot.v1;

import "pocket_pilot/v1/common.proto";
import "google/protobuf/empty.proto";
import "google/protobuf/timestamp.proto";

option go_package = "github.com/AlanIsaacV/pocket-pilot/backend/internal/gen/proto/pocket_pilot/v1;pocketpilotv1";

message Goal {
  string id = 1;
  string name = 2;

  int64 target_amount_cents = 3;
  int64 saved_amount_cents = 4;

  string target_date = 5; // YYYY-MM-DD
  optional string category_id = 6;

  google.protobuf.Timestamp created_at = 7;
  google.protobuf.Timestamp updated_at = 8;
  google.protobuf.Timestamp deleted_at = 9;
}

service GoalService {
  rpc ListGoals(ListGoalsRequest) returns (ListGoalsResponse);
  rpc UpsertGoal(UpsertGoalRequest) returns (UpsertGoalResponse);
  rpc DeleteGoal(DeleteGoalRequest) returns (google.protobuf.Empty);
}

message ListGoalsRequest {
  google.protobuf.Timestamp updated_since = 1;
  PageRequest page = 2;
}

message ListGoalsResponse {
  repeated Goal goals = 1;
  PageResponse page = 2;
  google.protobuf.Timestamp synced_at = 3;
}

message UpsertGoalRequest {
  Goal goal = 1;
}

message UpsertGoalResponse {
  Goal goal = 1;
  bool conflict_resolved = 2;
}

message DeleteGoalRequest {
  string id = 1;
  google.protobuf.Timestamp deleted_at = 2;
}
```

Contract semantics follow existing modules:

- Full sync (`updated_since` absent): list active rows (`deleted_at IS NULL`) with pagination.
- Delta sync (`updated_since` present): return all changed rows after cursor, including soft-deleted rows.
- Upsert: return `conflict_resolved=true` and server-current row when server version wins.
- Delete: soft-delete with LWW timestamp behavior.

### Sync determinism and timestamp authority

- Canonical ordering for full sync: `ORDER BY created_at DESC, id DESC`.
- Canonical ordering for delta sync: `ORDER BY updated_at ASC, id ASC`.
- Full sync pagination uses numeric offset tokens (same convention as other services), with server defaults `page_size=20` and max `100`.
- Delta sync is unpaginated: when `updated_since` is present, server ignores `request.page` and returns full delta with `response.page.next_page_token = ""`.
- LWW winner selection uses the request timestamp (`EXCLUDED.updated_at`) as the candidate version during conflict checks.
- Persisted `updated_at` for accepted updates is server-stamped by DB trigger (`NOW()`), consistent with existing modules.
- If `created_at` or `updated_at` is missing, handler sets fallback `time.Now().UTC()`.
- On conflict, server returns current persisted row and `conflict_resolved=true`; client must overwrite local row.
- `created_at` is immutable after first insert; on conflict updates, existing `created_at` is preserved.

### Delete semantics

- If `deleted_at` is missing in request, handler uses `time.Now().UTC()`.
- If a row does not exist, delete returns success (idempotent no-op).
- If incoming `deleted_at` is stale (`<= current updated_at`), delete is a no-op success under LWW.
- If request carries an invalid UUID or invalid timestamp payload, handler returns `InvalidArgument`.

## Flutter Design

### Feature module

Add `frontend/lib/src/features/goals/`:

- `domain/goal.dart`
- `data/goal_local_store.dart`
- `data/goal_remote_service.dart`
- `data/goal_repository.dart`
- `data/goal_sync_handler.dart`
- `ui/goal_view_model.dart`

### Domain model and derived math

`GoalModel` persists only canonical fields. Derived values are computed getters.

#### 1) Progress percentage

```text
progress_percentage = (saved_amount_cents / target_amount_cents) * 100
```

- Defensive guard: if `target_amount_cents <= 0`, return `0` (should not happen after validation).

#### 2) Months remaining

Use calendar month difference (ignore day-of-month):

```text
raw = (target.year - now.year) * 12 + (target.month - now.month)
months_remaining = max(1, raw)
```

- Target in current month -> `1`.
- Target in past month(s) -> `1`.
- "Current month" is evaluated using the device local timezone (`DateTime.now()` local).

#### 3) Monthly required cents

```text
remaining = target_amount_cents - saved_amount_cents
if remaining <= 0 => 0
else monthly_required_cents = ceil(remaining / months_remaining)
```

Integer implementation should avoid floating precision drift:

```text
(remaining + months_remaining - 1) ~/ months_remaining
```

#### 4) Overdue flag

Goal is overdue when:

- target month is before current month, and
- `saved_amount_cents < target_amount_cents`.

Current-month goals are urgent (`months_remaining=1`) but not overdue.

#### 5) Dashboard aggregation

ViewModel/service-level function:

- filter active goals (`deleted_at == null`)
- sum each `monthly_required_cents`
- expose as `totalMonthlyRequiredCents`

This is the monthly liquidity requirement for not falling behind.

### Sync integration

- `GoalSyncHandler.entityType = 'goal'`.
- `syncOrder` must be after categories to reduce FK-related push failures.
- To avoid renumbering existing handlers, goals can be appended after current handlers (still satisfies "after categories").

Outbox operations:

- upsert payload: full goal map with `updated_at`
- delete payload: `{ "deleted_at": "...iso8601..." }`

`GoalRepository` write contract:

- `upsertGoal(goal)` must persist locally first and enqueue `upsert` outbox entry in the same logical operation.
- `deleteGoal(id)` must soft-delete locally and enqueue `delete` outbox entry with `deleted_at`.

`GoalSyncHandler` contract:

- `pull(updatedSince)` returns normalized SQLite-ready maps plus authoritative `synced_at`.
- `pushUpsert(payload)` returns `conflictResolved` + optional server row for overwrite.
- `pushDelete(id, deletedAt)` is idempotent.

## Backend Go Design

Add `backend/internal/goal/`:

- `model.go`
- `repository.go`
- `handler.go`
- `validation.go`
- `validation_test.go`

### Validation rules

- `name` required and trimmed non-empty.
- `target_amount_cents > 0`.
- `saved_amount_cents >= 0`.
- `saved_amount_cents <= target_amount_cents`.
- `target_date` must parse as `YYYY-MM-DD`.

No explicit `category_id` pre-validation query is added. The DB FK remains authoritative.

### Repository behavior

- `List`: full (paginated active rows) and delta (all changed rows) modes.
- `Upsert`: `INSERT ... ON CONFLICT (id) DO UPDATE ... WHERE goals.updated_at < EXCLUDED.updated_at`.
- `SoftDelete`: set `deleted_at` and `updated_at` with LWW guard.
- `List` ordering is deterministic (`created_at,id` for full; `updated_at,id` for delta).

### Handler behavior

- Extract `user_id` from auth context.
- Parse UUID/date fields.
- Map proto <-> domain.
- Return `conflict_resolved` contract.
- Enforce page defaults (`20`) and max (`100`) for full sync requests.

### Server wiring

Register in `backend/cmd/server/main.go`:

- instantiate `goal.NewRepository(pool)`
- instantiate `goal.NewHandler(repo)`
- `pb.RegisterGoalServiceServer(...)`

## Error Handling

- Validation failures return `InvalidArgument`.
- FK violations from DB are returned as write failures (no pre-check query). Sync outbox marks failure and retries in later cycles.
- LWW conflicts are not treated as errors; they return `conflict_resolved=true` and server row for local overwrite.
- Delete is idempotent under soft-delete semantics.

## Testing Strategy

### Flutter unit tests

- `monthsRemaining` matrix (future/current/past month).
- `monthlyRequiredCents` with ceil behavior.
- completed goals return `0` monthly requirement.
- overdue flag behavior.
- dashboard total aggregation over active goals only.

### Flutter data/sync tests

- local store upsert/soft-delete behavior.
- repository enqueues correct outbox payloads.
- sync handler conflict resolution path stores server row locally.

### Go tests

- validation table tests for all numeric/date/name constraints.
- repository LWW behavior for upsert and soft delete.
- handler proto mapping with optional `category_id` and timestamps.
- repository list determinism tests:
  - full sync ordering + stable pagination (`created_at DESC, id DESC`).
  - delta ordering + tie-breaker (`updated_at ASC, id ASC`).
  - delta ignores page request and returns complete changed set.
- delete semantics tests:
  - missing row is idempotent success.
  - stale `deleted_at` is no-op success.

## Rollout Plan

1. Add proto file + run proto generation.
2. Add backend migration `004_goals.sql`.
3. Add frontend migration `004.sql` and bump DB version.
4. Implement backend `internal/goal` + server registration.
5. Implement frontend `features/goals` data/domain/ui layers.
6. Register `GoalSyncHandler` in app bootstrap.
7. Add and run tests.

## Acceptance Criteria

- Goals can be created/updated/deleted offline and sync correctly with LWW.
- Goal projections are computed client-side with agreed formulas and edge-case behavior.
- Dashboard exposes the total monthly required savings for active goals.
- Overdue goals show both immediate requirement and overdue state.
- All money values remain persisted as integer cents.
