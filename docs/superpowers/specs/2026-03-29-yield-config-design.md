# YieldConfig Design

## Summary

This design adds a new syncable entity, `yield_configs`, to track investments or cash-like products that generate interest over time.

Pocket Pilot keeps its offline-first model:

- `yield_configs` are written locally first and synced via outbox.
- Yield-generated transactions are created locally by the Flutter app.
- Deterministic UUIDv5 IDs prevent duplicates across retries and devices.
- The Go backend remains passive for generation and applies Last Write Wins (LWW) with `updated_at`.

## Scope and Constraints

### In scope

- New `yield_configs` schema in PostgreSQL and SQLite.
- Extend existing `transactions` schema with nullable `yield_id` linkage.
- New gRPC `YieldConfigService` (list/upsert/delete sync contract).
- Local yield generator in Flutter with 30-day horizon catch-up loop.
- Deterministic UUIDv5 generation for yield occurrences.
- Backend transaction mapping updates to carry `yield_id` end-to-end.

### Out of scope

- Yield UI screens and forms.
- Compounded-interest engines (v1 uses simple interest formula only).
- Auto-generated principal-return transaction at maturity.
- Any shift from `sqflite` to Drift in this slice.

## Confirmed Product Decisions

| Decision | Choice |
|---|---|
| Local persistence strategy | Keep existing `sqflite` DAOs/repositories (no Drift migration) |
| `auto_renew` behavior | Renew same term and continue `active` |
| `AT_MATURITY` renew support | Add `term_days` to persist renewal term |
| Principal return at maturity | Do not generate principal transaction in v1 |
| Enum casing storage | Normalize to lowercase in persistence/wire mapping |
| `transaction.yield_id` validation in backend | Passive bridge behavior (no strict business validation) |
| `interest_cents == 0` | Do not create transaction; still advance schedule cursor |

## Architecture

### High-level flow

1. User creates/updates/deletes `yield_config` locally.
2. Repository writes SQLite and enqueues `sync_outbox` entry (`entity_type=yield_config`).
3. On app startup/resume, orchestrator runs `sync -> generate -> sync`.
4. Generator scans active yield configs with `next_date <= today + 30 days`.
5. Generator creates deterministic transactions locally (`INSERT OR IGNORE`) and advances `next_date`.
6. Outbox push sends generated transactions plus updated yield configs.
7. Backend upserts rows with LWW and returns conflict state when server version is newer.

### Unit boundaries

- `yield_configs` storage unit (local store + repository + sync handler).
- Yield generation unit (math + cursor advancement + deterministic IDs).
- Existing sync orchestration unit (reuse, do not fork flow).
- Backend `yieldconfig` service unit (CRUD/sync + LWW).
- Existing transaction service unit extended only for `yield_id` mapping.

Each unit remains independently testable and does not require UI runtime to validate behavior.

## Data Model Design

### PostgreSQL

Create migration `backend/migrations/003_yield_configs.sql`:

```sql
CREATE TABLE yield_configs (
    id               uuid PRIMARY KEY      DEFAULT gen_random_uuid(),
    user_id          uuid         NOT NULL,
    account_id       uuid         NOT NULL REFERENCES accounts (id),
    name             text         NOT NULL,

    amount_cents     bigint       NOT NULL,
    apy_rate         numeric(7,4) NOT NULL,

    payout_frequency text         NOT NULL, -- daily, weekly, monthly, at_maturity
    next_date        date         NOT NULL,
    maturity_date    date,
    term_days        integer,

    auto_renew       boolean      NOT NULL DEFAULT false,
    status           text         NOT NULL, -- active, paused, completed

    created_at       timestamptz  NOT NULL DEFAULT now(),
    updated_at       timestamptz  NOT NULL DEFAULT now(),
    deleted_at       timestamptz
);

CREATE INDEX idx_yield_configs_user_updated_at
    ON yield_configs (user_id, updated_at);

CREATE INDEX idx_yield_configs_user_next_date_active
    ON yield_configs (user_id, next_date)
    WHERE deleted_at IS NULL AND status = 'active';

ALTER TABLE transactions
    ADD COLUMN yield_id uuid REFERENCES yield_configs (id);

CREATE INDEX idx_transactions_yield_id
    ON transactions (yield_id)
    WHERE yield_id IS NOT NULL;

CREATE TRIGGER set_updated_at_yield_configs
    BEFORE UPDATE
    ON yield_configs
    FOR EACH ROW
EXECUTE FUNCTION trigger_set_updated_at();
```

Server-side validation rules:

- `status in ('active','paused','completed')`
- `payout_frequency in ('daily','weekly','monthly','at_maturity')`
- `amount_cents > 0`
- `apy_rate >= 0`
- `at_maturity` requires `term_days > 0`
- `at_maturity` requires `maturity_date IS NOT NULL`
- `at_maturity` requires `next_date = maturity_date`
- `auto_renew=true` with finite maturity requires `term_days > 0`

### SQLite

Create migration `frontend/assets/migrations/003.sql`:

```sql
CREATE TABLE yield_configs (
    id               TEXT PRIMARY KEY,
    account_id       TEXT     NOT NULL REFERENCES accounts (id),
    name             TEXT     NOT NULL,

    amount_cents     BIGINT   NOT NULL,
    apy_rate         NUMERIC(7,4) NOT NULL,

    payout_frequency TEXT     NOT NULL,
    next_date        DATE     NOT NULL,
    maturity_date    DATE,
    term_days        INTEGER,

    auto_renew       INTEGER  NOT NULL DEFAULT 0,
    status           TEXT     NOT NULL,

    created_at       DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at       DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    deleted_at       DATETIME
);

CREATE INDEX idx_yield_configs_next_date_active
    ON yield_configs (next_date)
    WHERE deleted_at IS NULL AND status = 'active';

CREATE INDEX idx_yield_configs_updated_at
    ON yield_configs (updated_at);

CREATE TRIGGER set_updated_at_yield_configs
    AFTER UPDATE
    ON yield_configs
    FOR EACH ROW
    WHEN new.updated_at = old.updated_at
BEGIN
    UPDATE yield_configs
    SET updated_at = CURRENT_TIMESTAMP
    WHERE id = new.id;
END;

ALTER TABLE transactions
    ADD COLUMN yield_id TEXT REFERENCES yield_configs (id);

CREATE INDEX idx_transactions_yield_id
    ON transactions (yield_id)
    WHERE yield_id IS NOT NULL;
```

Also bump `DatabaseHelper._version` from `2` to `3`.

## gRPC Contract Design

### New service: `yield_config_service.proto`

Add `proto/pocket_pilot/v1/yield_config_service.proto` with:

- `ListYieldConfigs`
- `UpsertYieldConfig`
- `DeleteYieldConfig`

RPC message shapes:

```proto
service YieldConfigService {
  rpc ListYieldConfigs(ListYieldConfigsRequest) returns (ListYieldConfigsResponse);
  rpc UpsertYieldConfig(UpsertYieldConfigRequest) returns (UpsertYieldConfigResponse);
  rpc DeleteYieldConfig(DeleteYieldConfigRequest) returns (google.protobuf.Empty);
}

message ListYieldConfigsRequest {
  google.protobuf.Timestamp updated_since = 1;
  PageRequest page = 2;
}

message ListYieldConfigsResponse {
  repeated YieldConfig configs = 1;
  PageResponse page = 2;
  google.protobuf.Timestamp synced_at = 3;
}

message UpsertYieldConfigRequest {
  YieldConfig config = 1;
}

message UpsertYieldConfigResponse {
  YieldConfig config = 1;
  bool conflict_resolved = 2;
}

message DeleteYieldConfigRequest {
  string id = 1;
  google.protobuf.Timestamp deleted_at = 2;
}
```

Entity message:

```proto
message YieldConfig {
  string id = 1;
  string account_id = 2;
  string name = 3;

  int64 amount_cents = 4;
  double apy_rate = 5;

  string payout_frequency = 6;        // normalized lowercase on server
  string next_date = 7;               // YYYY-MM-DD
  optional string maturity_date = 8;  // YYYY-MM-DD
  bool auto_renew = 9;
  string status = 10;                 // normalized lowercase on server

  google.protobuf.Timestamp created_at = 11;
  google.protobuf.Timestamp updated_at = 12;
  google.protobuf.Timestamp deleted_at = 13;
  optional int32 term_days = 14;
}
```

### Existing transaction contract

Extend `Transaction` in `transaction_service.proto` with:

```proto
optional string yield_id = 16;
```

Sync semantics are unchanged: full/delta pull rules and LWW conflict resolution stay aligned with existing services.

`YieldConfigService` sync semantics (explicit):

- Full sync (`updated_since` absent): return all non-deleted rows (`deleted_at IS NULL`) with pagination, including `status in ('active','paused','completed')`.
- Delta sync (`updated_since` present): return all changed rows after cursor, including soft-deleted rows.
- Delta paging rule: when `updated_since` is present, server must ignore `request.page` and return full delta set with `response.page.next_page_token = ""`.
- Upsert: LWW response includes `conflict_resolved` and server-current row when conflict happens.
- Delete: soft delete with LWW; missing row is treated as idempotent success.
- Stale delete handling: if incoming `deleted_at` is older than server row `updated_at`, delete is a no-op and succeeds. Reconciliation happens through the next delta pull (same cycle in `sync -> generate -> sync`), where client receives the newer server row.

## Flutter Design

### Feature module

Add `frontend/lib/src/features/yield_configs/` with existing project shape:

- `domain/yield_config.dart`
- `data/yield_config_local_store.dart`
- `data/yield_config_remote_service.dart`
- `data/yield_config_repository.dart`
- `data/yield_config_sync_handler.dart`
- `data/yield_transaction_generator.dart`

Normalization rule on client writes (normative):

- Before writing to SQLite and before outbox enqueue, repository must normalize `status` and `payout_frequency` to lowercase.
- Generator and local-store filters must operate on normalized lowercase values only.
- Pull path from server must also normalize defensively before local upsert.

### Generator execution

Reuse app orchestration pattern already used for templates:

- startup trigger and resume trigger
- cycle: `sync -> generate -> sync`
- coalescing behavior unchanged

The yield generator can be composed as a separate runner invoked inside the same generation phase to avoid coupling template and yield logic.

Deterministic namespace (normative):

- Define `kDeterministicYieldNamespace = '9b7dc9b8-9e4f-4e0b-a178-6f6b1b39b4f1'` in `frontend/lib/src/core/ids/deterministic_namespace.dart`.
- All yield UUIDv5 IDs in runtime and tests must use exactly this constant.
- Backend does not generate yield transaction IDs, but any backend fixtures/tests that reproduce IDs must use the same namespace.

### Yield generation algorithm

For each active yield config where `next_date <= today + 30 days`:

Frequency behavior table:

| Frequency | Required fields | `days_elapsed` anchor | Cursor advance |
|---|---|---|---|
| `daily` | none extra | `previous = cursor - 1 day` | `cursor + 1 day` |
| `weekly` | none extra | `previous = cursor - 7 days` | `cursor + 7 days` |
| `monthly` | none extra | `previous = addMonthsClamped(cursor, -1)` | `addMonthsClamped(cursor, +1)` |
| `at_maturity` | `term_days > 0`, `maturity_date`, `next_date = maturity_date` | `previous = cursor - term_days days` | `cursor + term_days days` |

`days_elapsed` is always `difference_in_days(previous, cursor)` and is derived from `cursor` only (no hidden local state), which guarantees deterministic reruns and deterministic catch-up after app restarts.

Field invariants used by generator:

- `status` must be `active`; other statuses are ignored.
- `at_maturity` always keeps `next_date` aligned to maturity boundary (`next_date == maturity_date`) when active.

Pre-loop schedule parsing policy:

- If `payout_frequency` is unknown or `next_date` cannot be parsed as `YYYY-MM-DD`, generator must not mutate the row and must stop processing that config for this run (log/metrics only).
- If `at_maturity` invariants are broken (`term_days <= 0`, missing `maturity_date`, or `next_date != maturity_date`), generator must not mutate the row and must stop processing that config for this run (log/metrics only).

1. Set `cursor = next_date`.
2. Loop while `cursor <= horizon`.
3. If `maturity_date != null` and `cursor > maturity_date`:
   - if `auto_renew=true` and `term_days>0`: set `maturity_date += term_days`, keep `status='active'`, continue.
   - else set `status='completed'` and stop loop.
4. Compute `days_elapsed`:
   - use the frequency table above.
5. Compute simple interest:

   `interest_cents = (amount_cents * (apy_rate / 100) * (days_elapsed / 365.0)).round()`

6. If `interest_cents > 0`, generate deterministic transaction ID:

   `uuid_v5(kDeterministicYieldNamespace, "${yieldConfig.id}-${cursor}")`

7. Build transaction row:
   - `type='income'`
   - `account_id=yield_config.account_id`
   - `category_id=null`
   - `yield_id=yield_config.id`
   - `amount_cents=interest_cents`
   - `status='cleared'` when `cursor <= today`, else `pending`
8. Insert `INSERT OR IGNORE`; enqueue outbox upsert only when insert succeeded.
9. Compute `next_cursor` using the frequency table.
10. `at_maturity` special transition:
    - if `auto_renew=true`: set `maturity_date = next_cursor` and keep `status='active'`.
    - if `auto_renew=false`: set `status='completed'`, set `next_date = cursor`, set `maturity_date = cursor`, and stop loop.
11. Set `cursor = next_cursor` (unless loop stopped by completion).
12. Persist updated config (`next_date`, `maturity_date`, `status`, `updated_at`) and enqueue config upsert if any cursor/lifecycle change happened.

Exit-path post-conditions (normative):

- Active + non-`at_maturity`: `next_date = cursor` (next pending payout boundary).
- Active + `at_maturity`: `next_date = maturity_date` and both equal next renewal boundary.
- Completed by maturity (`auto_renew=false`): `status='completed'`, `next_date = maturity_date = last processed payout date`.
- Malformed schedule fields: no mutation of `status`, `next_date`, or `maturity_date`.

Date-driven examples (normative):

- Monthly end-of-month: `cursor=2026-03-31` -> `previous=2026-02-28` -> `days_elapsed=31`.
- Monthly non-leap year: `cursor=2027-03-31` -> `previous=2027-02-28` -> `days_elapsed=31`.
- `at_maturity`: `term_days=90`, payout at `cursor=2026-06-30` -> next cursor `2026-09-28`; if `auto_renew=true`, new `maturity_date=2026-09-28`.

Behavioral guarantees:

- Idempotent generation on repeated runs.
- No transaction insertion when `interest_cents == 0`.
- Date-only UTC behavior for deterministic cross-device results.

### Transaction mapping updates

Extend existing transaction model/data/sync pipeline to include nullable `yield_id`:

- `TransactionModel` field + `toMap/fromMap/toServerMap/fromProto`
- local store row maps
- remote service upsert payload mapping
- sync conflict-save mapping

### Sync dependency ordering

`yield_config` pushes must occur before `transaction` pushes, because generated rows carry `yield_id` FK.

Canonical handler order after this feature:

1. `account`
2. `category`
3. `tag`
4. `transaction_template`
5. `yield_config`
6. `transaction`
7. `user_preference`

Outbox dependency rule:

- If a transaction push fails due to missing `yield_id` FK, it is treated as transient and retried in the next cycle after upstream `yield_config` sync.

## Go Backend Design

### New module: `internal/yieldconfig`

Files:

- `model.go`
- `repository.go`
- `handler.go`

Repository methods:

- `GetByID`
- `List` (full sync paginated non-deleted rows, delta sync all changed rows)
- `Upsert` (LWW by `updated_at`)
- `SoftDelete` (LWW soft delete)

Handler responsibilities:

- parse/validate UUID/date-only fields
- normalize `status` and `payout_frequency` to lowercase
- validate `term_days` invariants
- map proto <-> domain
- return `conflict_resolved` contract in upsert

### Transaction service extension

Update `internal/transaction`:

- add nullable `YieldID *uuid.UUID` in model
- extend scan columns and SQL upsert/set clauses
- map proto optional field in `toProto/fromProto`

Policy: backend acts as passive bridge for `transaction.yield_id` business meaning. It persists the field and relies on FK/LWW behavior.

### Server wiring

Register new service in `backend/cmd/server/main.go`:

- instantiate yield config repository and handler
- `pb.RegisterYieldConfigServiceServer(...)`

## Error Handling and Observability

- Error taxonomy is explicit and non-overlapping:
  - `malformed_schedule` (unknown frequency, invalid date parse, broken `at_maturity` invariants): stop config processing, no local mutation, no outbox enqueue.
  - `reference_integrity` (missing/deleted account): stop config processing, no local mutation, no outbox enqueue.
  - `calculable_no_emit` (`interest_cents == 0`): advance cursor normally, persist config update, enqueue config upsert.
- Generator returns report counters (generated, skipped, completed, renewed).
- Structured logs include: `yield_config_id`, `cursor_date`, `action`, `reason`.

Persistence/reconciliation policy for data-shape errors:

- For `malformed_schedule`, no mutation means no invalid payload is enqueued to outbox; this prevents unsyncable/stuck retries.
- For `reference_integrity`, no mutation preserves deterministic retry once dependencies arrive from sync.
- For `calculable_no_emit`, config cursor advances and config upsert is enqueued because row remains backend-valid.

## Testing Strategy

### Flutter unit tests

- interest formula by frequency and rounding behavior
- monthly day-delta correctness on end-of-month/leap-year boundaries
- deterministic UUID stability
- maturity + auto-renew behavior with `term_days`
- zero-interest skip behavior

### Flutter integration tests

- scheduler query (`active`, non-deleted, horizon filtered)
- idempotent repeated generation (no duplicates)
- outbox payload includes `yield_id`
- cursor and status updates persisted correctly

### Go tests

- `yield_configs` repository LWW upsert/delete/list semantics
- handler proto mapping for optional dates and `term_days`
- normalization to lowercase for status/frequency
- transaction repository/handler roundtrip for `yield_id`

## Rollout Plan

1. Proto updates (`yield_config_service.proto` + `transaction.yield_id`) and code generation.
2. DB migrations (`003` backend and frontend).
3. Backend `yieldconfig` service + transaction `yield_id` mapping.
4. Frontend yield data/sync layer.
5. Frontend yield generator integration into existing cycle.
6. Tests and regression pass.

## Acceptance Criteria

- Creating/updating/deleting yield configs works offline and syncs with LWW.
- Generated yield transactions are deterministic and never duplicated across reruns.
- Generated transactions are linked through `transactions.yield_id`.
- Maturity and auto-renew rules behave exactly as confirmed decisions.
- Existing transaction and template flows remain unchanged.
