# Transaction Templates and Scheduled Generation

This document describes how recurring templates and scheduled transaction generation work in Pocket Pilot, including backend contracts, local generation logic, sync orchestration, and tags/template linkage.

## Scope

Implemented in the 2026-03-29 iteration:

- New syncable entity: `transaction_templates`.
- New linkage on transactions: `transactions.template_id`.
- Local recurring generation with deterministic UUIDv5 IDs.
- Transfer-template support with dual-leg generation/reconciliation.
- App-level orchestration for `sync -> generate -> sync` cycles.
- Tags + template linkage remediation in transaction model/data/forms.

## Data Model

### Backend (PostgreSQL)

- Migration: `backend/migrations/002_transaction_templates.sql`.
- New table: `transaction_templates` with fields:
  - identity/ownership: `id`, `user_id`
  - references: `account_id`, optional `to_account_id`, optional `category_id`
  - transaction shape: `type`, optional `amount_cents`, `currency_code`, `tags`, `description`
  - schedule: optional `frequency`, optional `next_date`, optional `end_date`
  - LWW lifecycle: `created_at`, `updated_at`, optional `deleted_at`
- `transactions` adds optional FK `template_id`.
- Partial indexes:
  - schedulable templates by `(user_id, next_date)`
  - transaction template linkage by `transactions(template_id)` when not null

### Frontend (SQLite)

- Migration: `frontend/assets/migrations/002.sql`.
- Mirror table: `transaction_templates`.
- `transactions` adds optional `template_id` (`TEXT` FK).
- Local tags storage in transactions/templates remains JSON string in `TEXT`.

## Backend Services and Validation

### TransactionTemplateService

- Proto: `proto/pocket_pilot/v1/transaction_template_service.proto`.
- Go module: `backend/internal/transactiontemplate/`.
- RPCs:
  - `ListTransactionTemplates`
  - `UpsertTransactionTemplate`
  - `DeleteTransactionTemplate`

### Validation Rules

Source: `backend/internal/transactiontemplate/validation.go`.

- Supported types: `income`, `expense`, `transfer_out`.
- Manual template (`frequency == nil`): `next_date` and `end_date` must be null.
- Scheduled template (`frequency != nil`): requires valid frequency, `next_date`, and `amount_cents`.
- `end_date` must be `>= next_date` when present.
- Transfer templates:
  - require `to_account_id`
  - `to_account_id` must differ from `account_id`
  - `category_id` must be null

### Transaction `template_id` Server Handling

Sources:

- `backend/internal/transaction/repository.go`
- `backend/internal/transaction/handler.go`

Behavior:

- Transaction proto mapping supports optional `template_id`.
- Upsert persists `template_id`.
- Server validates template reference belongs to same user.
- If template is soft-deleted, references are only allowed for historical transaction dates (`transaction.date <= template.deleted_at::date`).

## Frontend Feature Structure

New feature module: `frontend/lib/src/features/transaction_templates/`.

- `domain/transaction_template.dart`
- `data/transaction_template_local_store.dart`
- `data/transaction_template_repository.dart`
- `data/transaction_template_remote_service.dart`
- `data/transaction_template_sync_handler.dart`
- `data/scheduled_transaction_generator.dart`

Sync order (current):

1. `account`
2. `category`
3. `tag`
4. `transaction_template`
5. `transaction`
6. `user_preference`

## Scheduled Generation Algorithm (Client)

Main implementation: `frontend/lib/src/features/transaction_templates/data/scheduled_transaction_generator.dart`.

### Determinism and Horizon

- Namespace constant: `frontend/lib/src/core/ids/deterministic_namespace.dart`.
- Date helper: `frontend/lib/src/features/transaction_templates/domain/schedule_date_math.dart`.
- Horizon: 30 days ahead from `nowUtc` (date-only behavior).

### Per-template Processing

For each schedulable template (`next_date <= horizon`):

1. Start at cursor = `next_date`.
2. Stop if cursor passes `end_date` (template `next_date` cleared).
3. Validate references and shape:
   - account exists and active
   - category exists and active (when present)
   - transfer `to_account_id` exists/active/different
   - transfer currency consistency with both accounts
4. Reference-integrity error: skip and break template loop (no cursor advance).
5. Data-shape error: skip and advance cursor to avoid blocking.
6. Insert occurrences with `INSERT OR IGNORE` semantics.
7. Enqueue outbox upsert only for newly inserted rows.
8. Advance cursor by frequency when iteration is successful or shape-invalid.
9. Upsert template (to persist advanced/cleared `next_date`) only when cursor changed or schedule ended.

### Deterministic IDs

- Standard template occurrence:
  - `uuidv5(namespace, "{template_id}-{date}")`
- Transfer template occurrence:
  - out leg: `uuidv5(namespace, "{template_id}-{date}-out")`
  - in leg: `uuidv5(namespace, "{template_id}-{date}-in")`

### Transfer Pair Behavior

- Generates two rows: `transfer_out` and `transfer_in`.
- Links rows through reciprocal `linked_transaction_id`.
- If one deterministic leg exists and the other is missing, generator inserts only the missing leg.
- If both exist, generator does not mutate existing rows.
- If existing link is inconsistent, generator skips pair mutation.

### Status Assignment

- For newly inserted occurrences only:
  - `cleared` when `date <= today`
  - `pending` when `date > today`
- Existing deterministic rows are not overwritten.

## Sync Orchestration

Main implementation: `frontend/lib/src/core/sync/scheduled_generation_orchestrator.dart`.

- Cycle:
  1. `sync()` baseline
  2. `generator.run(nowUtc: ...)`
  3. `sync()` to push generated rows/template cursor updates
- Coalescing:
  - overlapping `runCycle()` calls queue a single extra cycle.

Wiring:

- Startup bootstrap in `frontend/lib/main.dart`.
- App resume trigger in `frontend/lib/src/ui/app.dart` (30-second throttle).

## Tags + Template Linkage Remediation

### Transaction Domain and Mapping

Source: `frontend/lib/src/features/transactions/domain/transaction.dart`.

- Added `templateId` and `tags` fields.
- `toMap()` persists tags as JSON string for SQLite.
- `toServerMap()` sends tags as list for gRPC repeated field.
- `fromProto()` and `fromMap()` now parse tags/template linkage.

### Data/Sync/Remote Layers

Sources:

- `frontend/lib/src/features/transactions/data/transaction_repository.dart`
- `frontend/lib/src/features/transactions/data/transaction_remote_service.dart`
- `frontend/lib/src/features/transactions/data/transaction_sync_handler.dart`

Behavior:

- Create/update paths propagate tags consistently.
- Transfer create/update propagate same tags to both legs.
- Remote upsert maps `template_id` and tags (list or JSON-string decoding).
- Conflict save path preserves server `deleted_at`.

### Form Behavior

Sources:

- `frontend/lib/src/features/transactions/ui/transaction_form_screen.dart`
- `frontend/lib/src/features/transactions/ui/transfer_form_screen.dart`

Behavior:

- Edit forms preload selected tags by matching tag names.
- If a tag is not present in local tag catalog, UI uses a temporary tag model so it remains editable/visible.
- Save paths pass selected tag names to repository.

## Tests

Key tests added/updated:

- `frontend/test/schedule_date_math_test.dart`
- `frontend/test/scheduled_transaction_generator_test.dart`
- `frontend/test/scheduled_generation_orchestrator_test.dart`
- `frontend/test/transaction_model_tags_test.dart`
- `frontend/test/transaction_repository_tags_test.dart`
- `backend/internal/transactiontemplate/validation_test.go`

## UI layer — routes & entry points

UI files live in `features/transaction_templates/ui/`. `TransactionTemplateViewModel` is a
`ChangeNotifier` (`templates`, `isLoading`, `isSyncing`, `errorMessage`), local-first with a 5s
throttle before remote sync. The list UI is `TransactionTemplatesListBody`
(`transaction_templates_list_body.dart`, renamed from `transaction_templates_list_tab.dart` in
widget-unification phase 5) — an embeddable, Scaffold-less widget mounted as the "Plantillas" tab
of `TransactionsScreen`, reading its `TransactionTemplateViewModel` from `TransactionsRouteScope`.
`TransactionTemplateFormRouteScope` (`MultiProvider`) wraps the form and provides
`AccountLocalStore`, `CategoryLocalStore`, `TagLocalStore`, `TagRepository`,
`CurrencyPreferencesLocalStore`, `TransactionTemplateRepository`, `SyncService`.

### Routes (nested under `/transactions`, outside `ShellRoute`)

| Path | Scope | Screen |
|------|-------|--------|
| `/transactions/templates/new` | `TransactionTemplateFormRouteScope` | `TransactionTemplateFormScreen` |
| `/transactions/templates/new/category` | `TransactionTemplateFormRouteScope` | `CategoryPickerScreen` |
| `/transactions/templates/:templateId/edit` | `TransactionTemplateFormRouteScope` | `TransactionTemplateFormScreen` |
| `/transactions/templates/:templateId/edit/category` | `TransactionTemplateFormRouteScope` | `CategoryPickerScreen` |

There is no standalone list route: `/templates` was removed when navigation moved under
`/transactions` (commit 42f51db), and the by-then-unreachable `TransactionTemplatesScreen` wrapper
was deleted in widget-unification phase 5 along with the then-orphaned
`TransactionTemplateRouteScope` (it only wrapped that screen; the tab's view model comes from
`TransactionsRouteScope`).

### Entry points for template creation

1. **AppBar of `TransactionFormScreen`** — `bookmark_add_outlined` → `_onSaveAsTemplate()` pushes
   `/transactions/templates/new` with a prefill map `{type, accountId, categoryId, amountCents, currencyCode, description, tags}`.
2. **AppBar of `TransferFormScreen`** — same, prefill `{type:'transfer_out', accountId, toAccountId, …}`.
3. **FAB menu on `TransactionsScreen`** — "Nueva plantilla".
4. **"Plantillas" tab on `TransactionsScreen`** (`/transactions`) — mounts
   `TransactionTemplatesListBody`; row tap opens `/transactions/templates/:templateId/edit`.

### Form field rules (mirror domain validation)

`name` required; `type` income/expense/transfer_out; `account` required; `toAccount` required only
for `transfer_out` (excludes from-account); `category` optional for income/expense, hidden for
transfer_out (opens `CategoryPickerScreen`); `amount` optional for manual, required when
`frequency != null`; `currency` via the shared `showCurrencyPicker()`
(`ui/widgets/currency_picker.dart` — this form's flow was the canonical donor);
`frequency` none/DAILY/WEEKLY/MONTHLY/YEARLY
(sets `nextDate` required); `nextDate`/`endDate` date pickers (`endDate` optional, clearable).
