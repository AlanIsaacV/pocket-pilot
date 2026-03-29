# Transaction Templates and Scheduled Transactions Design

## Summary

This design adds two related capabilities to Pocket Pilot:

1. **Transaction templates** for quick manual entry (for example, "Despensa").
2. **Scheduled transaction templates** that automatically generate future transactions offline (for example, recurring subscriptions or rent).

The implementation keeps the current architecture intact: Flutter client generates recurring transactions locally (offline-first), synchronization remains LWW by `updated_at`, and the Go backend stays passive for generation.

## Scope and Constraints

### In scope

- New syncable entity: `transaction_template`.
- Automatic local generation of recurring transactions from templates.
- Deterministic UUIDv5 generation to prevent duplicates across offline devices.
- Support for transfers in templates by extending template schema with `to_account_id`.
- Add `template_id` linkage on generated transactions.
- Complete `tags` persistence for transactions end-to-end.

### Out of scope

- New UI screens and flows for managing templates (covered in implementation planning, not this spec).
- Rule engines beyond fixed frequencies (`DAILY`, `WEEKLY`, `MONTHLY`, `YEARLY`).
- Auto-promoting existing `PENDING` generated transactions to `CLEARED` later.

## Confirmed Product Decisions

| Decision | Choice |
|---|---|
| Local persistence strategy | Keep existing `sqflite` pattern (no Drift introduction in this iteration) |
| Existing transaction tags gap | Fix tags end-to-end as part of this work |
| Existing generated transaction status | If deterministic ID already exists, keep original status (no overwrite) |
| Recurrent template amount | `amount_cents` is required for recurrent templates |
| Category missing/deleted | Skip generation (never coerce to `NULL`) |
| Transfer templates | Supported by extending template schema with `to_account_id` |

## Architecture

### High-level flow

1. User creates or updates a template locally.
2. Template change is saved to SQLite and enqueued in `sync_outbox` as `transaction_template`.
3. On app start and app resume, generator scans eligible scheduled templates (`next_date <= today + 30d`).
4. Generator creates transactions locally with deterministic IDs and enqueues them to outbox.
5. Sync engine pushes templates and generated transactions to backend.
6. Backend applies LWW upserts; collisions on deterministic IDs do not create duplicates.

### Unit boundaries

- **Template storage unit**: CRUD + local validation + outbox for `transaction_templates`.
- **Recurring generator unit**: pure scheduling + deterministic ID derivation + occurrence insertion.
- **Sync transport unit**: pull/push templates through dedicated sync handler.
- **Backend template service unit**: passive CRUD + LWW for templates.

Each unit remains independently testable and replaceable without affecting other units.

Unit interface contracts:

- **Template storage unit**
  - `upsertLocal(template) -> void` (writes SQLite + outbox entry `transaction_template/upsert`)
  - `softDeleteLocal(id, deletedAt) -> void` (writes SQLite + outbox entry `transaction_template/delete`)
  - `listSchedulable(horizonDate) -> List<Template>`
- **Recurring generator unit**
  - `run(nowUtcDate) -> GenerationReport`
  - side effects: per-template SQLite transaction for inserted transactions + template advancement + outbox entries
- **Sync transport unit**
  - `pull(updatedSince) -> SyncPullResult`
  - `pushUpsert(payload) -> SyncPushResult`
  - `pushDelete(entityId, deletedAt) -> void`
- **Backend template service unit**
  - `ListTransactionTemplates` (full/delta semantics)
  - `UpsertTransactionTemplate` (validation + LWW)
  - `DeleteTransactionTemplate` (soft delete + LWW + idempotent missing-row success)

## Data Model Design

### PostgreSQL changes

Create backend migration file `backend/migrations/002_transaction_templates.sql`:

1. Create table `transaction_templates`.
2. Add `template_id` to `transactions`.
3. Add `to_account_id` to support transfer templates.

Proposed shape:

```sql
CREATE TABLE transaction_templates (
    id               uuid PRIMARY KEY      DEFAULT gen_random_uuid(),
    user_id          uuid         NOT NULL,
    name             text         NOT NULL,

    account_id       uuid         NOT NULL REFERENCES accounts(id),
    to_account_id    uuid                  REFERENCES accounts(id), -- transfer templates only
    category_id      uuid                  REFERENCES categories(id),
    type             text         NOT NULL, -- income, expense, transfer_out
    amount_cents     bigint,
    currency_code    text         NOT NULL,
    tags             text[],
    description      text         NOT NULL DEFAULT '',

    frequency        text,
    next_date        date,
    end_date         date,

    created_at       timestamptz  NOT NULL DEFAULT now(),
    updated_at       timestamptz  NOT NULL DEFAULT now(),
    deleted_at       timestamptz
);

ALTER TABLE transactions
ADD COLUMN template_id uuid REFERENCES transaction_templates(id);

CREATE INDEX idx_transaction_templates_user_next_date
    ON transaction_templates(user_id, next_date)
    WHERE deleted_at IS NULL AND frequency IS NOT NULL AND next_date IS NOT NULL;

CREATE INDEX idx_transactions_template_id
    ON transactions(template_id)
    WHERE template_id IS NOT NULL;
```

Validation rules are applied at app/service layer (not strict DB check constraints in v1 to keep migration low-risk):

- Manual template: `frequency IS NULL AND next_date IS NULL`.
- Scheduled template: `frequency IS NOT NULL AND next_date IS NOT NULL AND amount_cents IS NOT NULL`.
- Transfer template: `type = 'transfer_out'` requires `to_account_id IS NOT NULL` and `to_account_id <> account_id`.
- If manual template (`frequency IS NULL`), require `end_date IS NULL`.

Validation matrix (authoritative):

| Field | Manual income/expense | Scheduled income/expense | Scheduled transfer_out |
|---|---|---|---|
| `frequency` | must be `NULL` | required | required |
| `next_date` | must be `NULL` | required | required |
| `end_date` | must be `NULL` | optional (`>= next_date` if set) | optional (`>= next_date` if set) |
| `amount_cents` | optional | required | required |
| `to_account_id` | must be `NULL` | must be `NULL` | required and `!= account_id` |
| `category_id` | optional active ref | optional active ref | must be `NULL` |

### SQLite changes

Create frontend migration file `frontend/assets/migrations/002.sql`:

- Add local `transaction_templates` table (no `user_id`) with explicit column semantics:

```sql
CREATE TABLE transaction_templates (
    id            TEXT PRIMARY KEY,
    name          TEXT NOT NULL,

    account_id    TEXT NOT NULL REFERENCES accounts(id),
    to_account_id TEXT REFERENCES accounts(id),
    category_id   TEXT REFERENCES categories(id),
    type          TEXT NOT NULL,
    amount_cents  BIGINT,
    currency_code TEXT NOT NULL,
    tags          TEXT, -- JSON array string
    description   TEXT NOT NULL DEFAULT '',

    frequency     TEXT,
    next_date     DATE,
    end_date      DATE,

    created_at    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    deleted_at    DATETIME
);

CREATE INDEX idx_transaction_templates_next_date
  ON transaction_templates(next_date)
  WHERE deleted_at IS NULL AND frequency IS NOT NULL AND next_date IS NOT NULL;

CREATE INDEX idx_transaction_templates_updated_at
  ON transaction_templates(updated_at);

ALTER TABLE transactions ADD COLUMN template_id TEXT REFERENCES transaction_templates(id);

CREATE INDEX idx_transactions_template_id
  ON transactions(template_id)
  WHERE template_id IS NOT NULL;
```

- Bump `DatabaseHelper._version` from `1` to `2`.

Also define and standardize tags storage for local transactions:

- `transactions.tags` remains `TEXT` column.
- Store tags as JSON array string (for example `"[\"rent\",\"fixed\"]"`).
- Parse/serialize in domain model and remote mapping consistently.

Tags end-to-end remediation required in this same implementation slice:

- Flutter domain model: `TransactionModel` must include `List<String> tags` with JSON parse/encode in `fromMap`/`toMap`.
- Flutter gRPC mapping: `TransactionRemoteService.upsertTransaction` must populate `transaction.tags` from local model; `TransactionModel.fromProto` already maps proto tags and must remain consistent.
- Flutter sync conflict path: `TransactionSyncHandler` must persist server-returned tags into local row.
- Go transaction service/repository: scan/write `tags` consistently in upsert/list mapping (no dropping tags on conflict return path).

## gRPC Contract Design

### New proto service

Add `proto/pocket_pilot/v1/transaction_template_service.proto`:

- `TransactionTemplateService`
  - `ListTransactionTemplates`
  - `UpsertTransactionTemplate`
  - `DeleteTransactionTemplate`

Proto appendix (concrete schema target):

```proto
syntax = "proto3";

package pocket_pilot.v1;

import "pocket_pilot/v1/common.proto";
import "google/protobuf/empty.proto";
import "google/protobuf/timestamp.proto";

option go_package = "github.com/AlanIsaacV/pocket-pilot/backend/internal/gen/proto/pocket_pilot/v1;pocketpilotv1";

message TransactionTemplate {
  string id = 1;
  string name = 2;

  string account_id = 3;
  optional string category_id = 4;
  string type = 5;
  optional int64 amount_cents = 6;
  string currency_code = 7;
  repeated string tags = 8;
  string description = 9;

  optional string frequency = 10;
  optional string next_date = 11;
  optional string end_date = 12;

  google.protobuf.Timestamp created_at = 13;
  google.protobuf.Timestamp updated_at = 14;
  google.protobuf.Timestamp deleted_at = 15;
  optional string to_account_id = 16;
}

service TransactionTemplateService {
  rpc ListTransactionTemplates(ListTransactionTemplatesRequest) returns (ListTransactionTemplatesResponse);
  rpc UpsertTransactionTemplate(UpsertTransactionTemplateRequest) returns (UpsertTransactionTemplateResponse);
  rpc DeleteTransactionTemplate(DeleteTransactionTemplateRequest) returns (google.protobuf.Empty);
}

message ListTransactionTemplatesRequest {
  google.protobuf.Timestamp updated_since = 1;
  PageRequest page = 2;
}

message ListTransactionTemplatesResponse {
  repeated TransactionTemplate templates = 1;
  PageResponse page = 2;
  google.protobuf.Timestamp synced_at = 3;
}

message UpsertTransactionTemplateRequest {
  TransactionTemplate template = 1;
}

message UpsertTransactionTemplateResponse {
  TransactionTemplate template = 1;
  bool conflict_resolved = 2;
}

message DeleteTransactionTemplateRequest {
  string id = 1;
  google.protobuf.Timestamp deleted_at = 2;
}
```

RPC contract details:

| RPC | Request | Response | Delete semantics |
|---|---|---|---|
| `ListTransactionTemplates` | `updated_since`, `page` | `repeated templates`, `page`, `synced_at` | N/A |
| `UpsertTransactionTemplate` | full `TransactionTemplate` payload | accepted template + `conflict_resolved` | N/A |
| `DeleteTransactionTemplate` | `id`, `deleted_at` | `google.protobuf.Empty` | soft delete with LWW (`updated_at/deleted_at` compare) |

Delete idempotency requirements:

- If template is already deleted with `updated_at >= deleted_at`, server no-ops and returns success.
- If incoming delete wins by LWW, server sets `deleted_at=deleted_at` and `updated_at=deleted_at`.
- Delete never hard-removes rows.
- If target row does not exist, server returns success as idempotent no-op (no tombstone creation in v1).

`TransactionTemplate` message fields:

- `id`, `name`
- `account_id`, `optional to_account_id`, `optional category_id`
- `type`, `optional amount_cents`, `currency_code`, `repeated tags`, `description`
- `optional frequency`, `optional next_date`, `optional end_date` (ISO `YYYY-MM-DD`)
- `created_at`, `updated_at`, `deleted_at`

### Existing transaction proto extension

Extend `Transaction` message in `transaction_service.proto`:

- Add `optional string template_id = 15;`.
- Reserve field number `16` for future template metadata extension in `Transaction`.

`template_id` contract on transaction upsert:

- Field is optional.
- If present, backend must verify the template belongs to the authenticated user.
- Referencing a soft-deleted template is allowed only when transaction is not deleted and `transaction.date <= template.deleted_at::date` (historical occurrence); otherwise reject.
- Backend must reject cross-user template references.

### Sync semantics

Template service follows same sync contract style as existing entities:

- `updated_since` delta pull.
- `synced_at` in list response.
- LWW conflict response with `conflict_resolved` flag on upsert.

Pagination and ordering semantics (must match existing services):

- Full sync (`updated_since` absent):
  - return only active rows (`deleted_at IS NULL`),
  - ordered by `created_at DESC`,
  - paginate using `PageRequest` (`page_size` default 20 max 100; `page_token` is decimal offset string).
- Delta sync (`updated_since` present):
  - return all rows changed after cursor, including soft-deleted,
  - ordered by `updated_at ASC`,
  - server ignores incoming `page` values,
  - server returns complete delta set with `page.next_page_token = ""`.

Canonical wire values:

- `TransactionTemplate.type`: `income`, `expense`, `transfer_out`.
- `TransactionTemplate.frequency`: `DAILY`, `WEEKLY`, `MONTHLY`, `YEARLY`.
- Generated `Transaction.status`: `cleared`, `pending`.

## Flutter Design

### New feature module

Add `frontend/lib/src/features/transaction_templates/` with:

- `domain/transaction_template.dart`
- `data/transaction_template_local_store.dart`
- `data/transaction_template_remote_service.dart`
- `data/transaction_template_repository.dart`
- `data/transaction_template_sync_handler.dart`

Pattern mirrors accounts/categories/tags/transactions.

### Generator unit

Add `scheduled_transaction_generator.dart` as an isolated service (no UI dependency).

UUID namespace source:

- Define one app-wide constant namespace UUID in a dedicated file (for example `core/ids/deterministic_namespace.dart`).
- Use this constant in generator runtime and tests; never derive namespace dynamically.

Responsibilities:

- Scan eligible templates.
- Generate occurrences until horizon.
- Persist occurrences and template advancement atomically.
- Enqueue outbox entries for generated transactions and updated templates.

Atomicity boundary:

- Use one SQLite transaction per template processing run.
- Inside that transaction: occurrence inserts/repairs + template `next_date` update + corresponding outbox enqueues.
- If any write/enqueue step fails, rollback the full template transaction and leave template state unchanged for retry in next run.

Dependencies:

- `DatabaseHelper` (for transactional writes).
- `SyncOutbox` (for outbox entries).
- Template local store/repository helpers.

### Runtime triggers

- Run once after app bootstrap completes.
- Run on `AppLifecycleState.resumed`.
- Guard with in-memory mutex to avoid overlapping runs.

Orchestration order (strict):

1. Run sync pull for dependencies up to `transaction_template` (`account`, `category`, `tag`, `transaction_template`).
2. Run scheduled generator once.
3. Run sync push for all entities (including generated `transaction` and advanced `transaction_template` entries).

If a lifecycle resume event fires during an active cycle, coalesce into one queued rerun after the current cycle completes.

### Date and timezone semantics

- Canonical schedule timezone is UTC for deterministic cross-device behavior.
- Generator computes `today` as UTC calendar date (`YYYY-MM-DD`), not device-local date.
- All comparisons (`next_date <= horizon`, `date <= today`) are date-only comparisons.
- `horizon` is `today + 30` calendar days in UTC.
- Date strings stored in SQLite for generated rows remain `YYYY-MM-DD` to preserve deterministic ID input and avoid DST timestamp drift.

### Active reference definition

In generator and backend validation, a reference is considered active when:

- row exists,
- belongs to authenticated user scope (server-side), and
- `deleted_at IS NULL`.

### Generation algorithm

For each active scheduled template where `next_date <= today + 30d`:

1. Validate template eligibility.
2. Loop while `cursor_date <= horizon`.
3. If `end_date != null` and `cursor_date > end_date`, stop and clear `next_date`.
4. Validate references:
   - `account_id` exists and active.
   - `category_id` exists and active when present (if missing/deleted: skip occurrence).
   - For transfer templates: `to_account_id` exists, active, and differs from `account_id`.
   - If skip reason is reference-integrity, log reason and **break template loop without cursor advance**.
5. Build deterministic IDs:
   - Normal templates: `uuidv5(NAMESPACE, "${template.id}-${date}")`.
   - Transfer templates: two IDs from same seed with suffixes:
     - out leg: `uuidv5(NAMESPACE, "${template.id}-${date}-out")`
     - in leg: `uuidv5(NAMESPACE, "${template.id}-${date}-in")`
6. Determine status only for newly inserted occurrences:
   - `cleared` if `date <= today`
   - `pending` if `date > today`
7. Insert transaction(s) with `INSERT OR IGNORE`.
8. Enqueue outbox `transaction/upsert` for every inserted row.
9. Advance cursor by frequency.
10. After loop, update template `next_date` and `updated_at`, enqueue template upsert **only if cursor advanced or template was ended/cleared**.

### Transfer occurrence generation

For `transfer_out` template occurrence:

- Generate two transaction rows in one DB transaction:
  - Out leg: `type='transfer_out'`, `account_id=account_id`, `linked_transaction_id=in_id`
  - In leg: `type='transfer_in'`, `account_id=to_account_id`, `linked_transaction_id=out_id`
- Both rows share:
  - same date
  - same amount/currency in v1
  - same `template_id`
  - same tags and description

Cross-currency rule for transfer templates in v1:

- Source and destination accounts must have the same `currency_code` as template `currency_code`.
- If currencies differ, generator skips occurrence with reason `transfer_currency_mismatch`.
- No FX conversion is attempted in v1.

Recovery rule for partially present transfer pairs:

- If one leg exists and the paired leg does not, generator inserts only the missing leg using deterministic paired ID and linked reference.
- If both legs exist, generator does not mutate either leg.
- Required invariant: when both legs exist, `out.linked_transaction_id == in.id` and `in.linked_transaction_id == out.id`.
- If either existing leg has mismatched linkage to a different transaction, generator logs `transfer_pair_inconsistent` and skips pair mutation for safety (no destructive repair in v1).

### Date advancement rules

- `DAILY`: +1 day.
- `WEEKLY`: +7 days.
- `MONTHLY`: preserve day-of-month when possible; clamp to valid last day.
- `YEARLY`: preserve month/day when possible; clamp Feb 29 -> Feb 28 on non-leap years.

Use pure helper for deterministic test coverage.

### Sync integration

Add `TransactionTemplateSyncHandler` and include in `main.dart` sync handler list.

Revised order:

1. account
2. category
3. tag
4. transaction_template
5. transaction
6. user_preference

Rationale: templates depend on account/category; generated transactions may depend on templates.

Outbox replay dependency rule:

- Any transaction payload with non-null `template_id` must be pushed after its corresponding template upsert.
- When server rejects transaction upsert with `FAILED_PRECONDITION`, classify error cause:
  - `missing_template_fk` (transient): keep pending for retry.
  - `template_deleted_not_historical` (terminal): mark failed terminal and stop retrying this entry.
  - `cross_user_template` (terminal): mark failed terminal and stop retrying this entry.
- Terminal failures must be visible in sync status diagnostics and must not block processing of later outbox entries.

## Go Backend Design

### New module

Add `backend/internal/transactiontemplate/`:

- `repository.go`
- `handler.go`

Repository follows same LWW pattern as existing entities:

- `List(ctx, userID, updatedSince, limit, offset)`
- `Upsert(ctx, template)` with `WHERE existing.updated_at < EXCLUDED.updated_at`
- `SoftDelete(ctx, id, userID, deletedAt)`
- `GetByID` for conflict return path.

### Server wiring

- Register `TransactionTemplateServiceServer` in `backend/cmd/server/main.go`.

### Server-side validation and ownership rules

Backend validates on every template upsert (defense in depth; client validation is not sufficient):

- `type` must be one of canonical string values (`income`, `expense`, `transfer_out`).
- `frequency` must be null or one of (`DAILY`, `WEEKLY`, `MONTHLY`, `YEARLY`).
- If scheduled (`frequency != null`), require `next_date` and `amount_cents`.
- If manual (`frequency == null`), require `next_date == null` and `end_date == null`.
- If `end_date` is present with `next_date`, enforce `end_date >= next_date`.
- `account_id`, optional `category_id`, and optional `to_account_id` must belong to authenticated user and not be soft-deleted.
- For transfer templates, require `to_account_id` and enforce `to_account_id != account_id`.
- For non-transfer templates, `to_account_id` must be null.
- For non-transfer templates, `account.currency_code` must equal template `currency_code`.
- For transfer templates, both account currencies must equal template `currency_code`.

Template conflict precedence (LWW) for upsert/delete races:

- If incoming `updated_at` is newer than stored row `updated_at`, incoming operation wins.
- If incoming `updated_at` is older or equal, stored row wins (no-op for incoming write).
- Tombstones are regular versions under LWW (`deleted_at` row with its own `updated_at`); a newer upsert can resurrect a deleted template.
- Older upsert cannot resurrect a newer tombstone.

### Existing transaction module updates

Update `backend/internal/transaction/` model, query scan columns, and proto mapping:

- Persist and return `template_id`.
- Keep existing LWW behavior unchanged.

Backend remains passive for schedule execution.

## Error Handling and Conflict Strategy

### Deterministic dedup guarantees

- Primary dedup: deterministic IDs.
- Local dedup: `INSERT OR IGNORE` on PK.
- Remote dedup: Postgres `UPSERT` + LWW.

### Important behavioral rule

If a deterministic transaction ID already exists, generator does not overwrite it. This preserves user-approved rule that original status remains unchanged.

### Skip reasons (logged)

- `missing_or_deleted_account`
- `missing_or_deleted_category`
- `missing_to_account`
- `same_from_to_account`
- `transfer_currency_mismatch`
- `missing_amount_for_recurrent`
- `invalid_frequency`
- `invalid_date_format`
- `transfer_pair_inconsistent`

Structured log fields (minimum):

- `run_id`, `template_id`, `template_type`, `cursor_date`, `action` (`generated|skipped|advanced|reconciled`), `reason`, `created_count`, `skipped_count`.

Metrics counters (minimum):

- `scheduled_generator_runs_total`
- `scheduled_generator_transactions_created_total`
- `scheduled_generator_transactions_skipped_total{reason=...}`
- `scheduled_generator_transfer_reconciliations_total`

Skip handling policy:

- Permanent data-shape errors advance cursor and continue:
  - `missing_amount_for_recurrent`
  - `invalid_frequency`
  - `invalid_date_format`
- Reference-integrity skips do **not** advance cursor and must **break template loop for this run** to avoid infinite loops and avoid dropping expected future entries while upstream sync catches up:
  - `missing_or_deleted_account`
  - `missing_or_deleted_category`
  - `missing_to_account`
  - `same_from_to_account`
  - `transfer_currency_mismatch`
- For reference-integrity skips, generator leaves template row unchanged and emits logs/metrics only (no metadata marker persisted).
- To avoid churn, generator applies local cooldown for identical `(template_id, cursor_date, reason)` skip events:
  - skip can be re-logged at most once per app resume cycle, and
  - at most once every 6 hours during long-running foreground sessions.
- Operational behavior for permanently invalid references: generator keeps retrying on future runs until template is fixed/deleted by user or by synced upstream change; this is intentional to avoid silent schedule loss.

### Template lifecycle behavior

- Updating a template affects only future, not-yet-generated occurrences (`date >= next_date` after save).
- Already generated transactions remain untouched (including status and amount), preserving edit history and deterministic idempotency.
- Deleting a template (`deleted_at`) stops future generation immediately; already generated transactions are not auto-deleted.
- Changing a template from scheduled to manual (`frequency=NULL`, `next_date=NULL`) stops future generation.
- Re-activating a template by setting frequency and next_date resumes generation from provided `next_date`.

## Testing Strategy

### Flutter unit tests

- Frequency date advancement matrix (daily/weekly/monthly/yearly).
- End-of-month and leap-year behavior.
- Deterministic UUID generation (same input -> same ID, different date -> different ID).
- Status assignment only on insertion.
- No mutation when row already exists.
- Skip on deleted/missing category.
- Transfer dual-leg generation and linking.

### Flutter integration tests (SQLite-level)

- Generator run creates expected rows and outbox entries.
- Running generator twice is idempotent.
- `next_date` progression and `end_date` stop behavior.
- Template sync order respected by `SyncService`.

### Go tests

- Repository LWW upsert behavior for templates.
- Delta pull includes deleted records after `updated_since`.
- Handler mapping for optional fields (`category_id`, `to_account_id`, dates).
- Transaction upsert includes `template_id` correctly.
- Delete idempotency when row does not exist returns success.
- Upsert/delete tie case with equal timestamps keeps stored row unchanged.
- Soft-deleted template reference rule on transaction upsert is enforced.

### Degraded mode and recovery tests

- Template RPC `UNIMPLEMENTED`/`NOT_FOUND`/`FAILED_PRECONDITION` does not abort global sync cycle.
- `transaction_template` handler degraded status is visible while other entities continue syncing.
- `transfer_pair_inconsistent` path logs and preserves existing rows without destructive mutation.

## Rollout Plan

1. Add proto contracts and regenerate stubs.
2. Add backend migration and service module.
3. Add frontend migration and data layer.
4. Add generator service and app lifecycle hooks.
5. Add tests and observability logs.
6. Enable template UI flows in a follow-up implementation slice.

Compatibility notes:

- Older clients ignore templates and continue normal sync.
- New clients require DB migration success before generator runs.

Migration/runtime guardrails:

- If frontend migration `002.sql` fails, app keeps template features disabled for that session and surfaces a non-blocking sync/status warning.
- Generator startup is gated by successful schema version check (`DatabaseHelper` at version 2).
- If backend migration is not yet deployed, template sync handler must fail gracefully without blocking other entity sync handlers.

Unsupported-backend failure handling:

- Treat `UNIMPLEMENTED`, `NOT_FOUND` (method/service), and `FAILED_PRECONDITION` (missing DB objects) from template RPCs as non-fatal for global sync cycle.
- Template sync handler marks template entity sync as degraded and records last error; other entity handlers continue normally.
- Retry policy follows existing outbox retry loop; no crash or global sync abort.

## Implementation Notes for Planning

- Keep changes isolated by unit (schema/proto/backend/template feature/generator/transaction tags).
- Avoid unrelated refactors.
- Keep generated transaction creation paths explicit (`fromTemplate`) to avoid hidden behavior in generic create methods.

## Delivery Phasing

To keep scope executable and testable, implementation planning should split this into ordered phases:

1. Contracts and schema migrations (proto + backend SQL + frontend SQL).
2. Backend template service and transaction `template_id` wiring.
3. Frontend template data/sync layer.
4. Generator core (non-transfer occurrences).
5. Transfer occurrence generation and pair reconciliation.
6. Tags end-to-end remediation for transactions.
7. Observability and full regression test pass.

Planning artifact split requirement:

- Plan A (core): phases 1-5 and 7 for templates + scheduler + transfer reconciliation.
- Plan B (remediation): phase 6 tags end-to-end workstream, integrated before final release cut.
- Release gate requires both plans completed and integration tests passing.

Phase definition of done:

- **Phase 1 DoD:** proto compiles, migrations applied cleanly on fresh and upgraded DBs.
- **Phase 2 DoD:** backend template RPCs pass CRUD/LWW/idempotency tests.
- **Phase 3 DoD:** frontend template local/sync layers push/pull with outbox correctly.
- **Phase 4 DoD:** non-transfer generator is idempotent and passes date-window tests.
- **Phase 5 DoD:** transfer dual-leg generation and reconciliation tests pass.
- **Phase 6 DoD:** tags persist correctly through local map, gRPC push, pull conflict resolution.
- **Phase 7 DoD:** observability fields emitted and regression suite green.
