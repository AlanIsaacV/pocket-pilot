# Yield Configs and Interest Generation

This document describes the `yield_configs` feature implemented in the 2026-03-29 iteration: schema, contracts, local generation flow, and sync integration.

## Scope

Implemented capabilities:

- New syncable entity: `yield_configs`.
- New transaction linkage: `transactions.yield_id`.
- Local (client-side) interest generation with deterministic UUIDv5.
- Maturity lifecycle support with optional auto-renew using `term_days`.
- Backend passive CRUD/sync service with LWW (`updated_at`).

Out of scope in this iteration:

- Yield management UI screens (settings section / forms).
- Principal-return transaction generation on maturity.
- Drift migration (project remains `sqflite`).

## Data Model

### Backend (PostgreSQL)

Migration: `backend/migrations/003_yield_configs.sql`.

- New table: `yield_configs`
  - identity/ownership: `id`, `user_id`
  - reference: `account_id`
  - product: `name`, `amount_cents`, `apy_rate`
  - schedule: `payout_frequency`, `next_date`, optional `maturity_date`, optional `term_days`
  - lifecycle: `auto_renew`, `status`, `created_at`, `updated_at`, `deleted_at`
- `transactions` adds nullable FK `yield_id`.
- Added indexes:
  - `idx_yield_configs_user_updated_at`
  - `idx_yield_configs_user_next_date_active`
  - `idx_transactions_yield_id`

### Frontend (SQLite)

Migration: `frontend/assets/migrations/003.sql`.

- Mirror table `yield_configs` (without `user_id`).
- `transactions` adds nullable `yield_id` (`TEXT` FK).
- Added `set_updated_at_yield_configs` trigger.
- App DB version updated to `3` in `frontend/lib/src/core/db/database_helper.dart`.

## gRPC Contracts

### YieldConfigService

Proto: `proto/pocket_pilot/v1/yield_config_service.proto`.

RPCs:

- `ListYieldConfigs`
- `UpsertYieldConfig`
- `DeleteYieldConfig`

Message `YieldConfig` includes:

- base fields (`id`, `account_id`, `name`, `amount_cents`, `apy_rate`)
- schedule fields (`payout_frequency`, `next_date`, `maturity_date`, `term_days`)
- lifecycle fields (`auto_renew`, `status`, timestamps)

### Transaction Extension

Proto updated in `proto/pocket_pilot/v1/transaction_service.proto`:

- `optional string yield_id = 16;`

## Backend Modules

New package: `backend/internal/yieldconfig/`.

- `model.go`: domain model and normalization helpers.
- `validation.go`: domain validation (`status`, `payout_frequency`, `at_maturity` invariants, `amount_cents`, `apy_rate`).
- `repository.go`: list/upsert/delete with LWW semantics.
- `handler.go`: gRPC mapping, date parsing (`YYYY-MM-DD`), lowercasing normalization, pagination behavior.

Server wiring:

- `backend/cmd/server/main.go` registers `YieldConfigService`.

Transaction linkage mapping updates:

- `backend/internal/transaction/repository.go` persists/scans `yield_id`.
- `backend/internal/transaction/handler.go` maps optional proto `yield_id`.

## Frontend Modules

New feature package: `frontend/lib/src/features/yield_configs/`.

- `domain/yield_config.dart`: model + local/server/proto mapping with lowercase normalization.
- `domain/yield_schedule_date_math.dart`: date advancement and `days_elapsed` helpers.
- `domain/yield_interest_math.dart`: simple interest cents formula.
- `data/yield_config_local_store.dart`: SQLite access.
- `data/yield_config_repository.dart`: local-first CRUD + outbox (`entity_type='yield_config'`).
- `data/yield_config_remote_service.dart`: gRPC adapter.
- `data/yield_config_sync_handler.dart`: pull/push/delete integration in sync engine.
- `data/yield_transaction_generator.dart`: local deterministic generation loop.

Deterministic namespace constant:

- `frontend/lib/src/core/ids/deterministic_namespace.dart` adds `kDeterministicYieldNamespace`.

## Local Generation Rules

Generator implementation: `frontend/lib/src/features/yield_configs/data/yield_transaction_generator.dart`.

High-level behavior:

1. Load active local configs (`status='active'`, non-deleted) up to horizon (`today + 30d`).
2. For each config, loop from `next_date` while `cursor <= horizon`.
3. Compute `days_elapsed` by frequency and calculate:

   `interest_cents = round(amount_cents * (apy_rate / 100) * (days_elapsed / 365.0))`

4. Build deterministic transaction ID:

   `uuidv5(kDeterministicYieldNamespace, "{yield_id}-{cursor_date}")`

5. Insert `income` transaction with:
   - `category_id = null`
   - `yield_id = config.id`
   - status `cleared` if `date <= today`, otherwise `pending`
6. Use insert-ignore + outbox enqueue only for newly inserted rows.
7. Advance schedule cursor and persist config updates through repository (which enqueues `yield_config/upsert`).

Key lifecycle rules:

- `interest_cents == 0`: no transaction row, cursor still advances.
- `auto_renew=false` at maturity: config becomes `completed`.
- `auto_renew=true` with `at_maturity`: renew boundary using `term_days`.

## Sync Integration

Sync handler order (current global order):

1. `account`
2. `category`
3. `tag`
4. `transaction_template`
5. `yield_config`
6. `transaction`
7. `user_preference`

Orchestration:

- Existing `ScheduledGenerationOrchestrator` keeps the cycle `sync -> generate -> sync`.
- New `CompositeScheduledGeneratorRunner` executes generators in sequence:
  1. template generator
  2. yield generator

## Tests

New frontend tests:

- `frontend/test/yield_schedule_date_math_test.dart`
- `frontend/test/yield_interest_math_test.dart`
- `frontend/test/yield_transaction_generator_test.dart`
- `frontend/test/composite_scheduled_generator_runner_test.dart`

New backend tests:

- `backend/internal/yieldconfig/validation_test.go`

## UI layer — routes & entry points

UI files live in `features/yield_configs/ui/`. `YieldConfigViewModel` is a `ChangeNotifier`
(`configs`, `isLoading`, `isSyncing`, `errorMessage`), local-first with a 5s throttle before remote
sync. `YieldConfigRouteScope` (`ChangeNotifierProvider`) wraps the list; `YieldConfigFormRouteScope`
(`MultiProvider`) provides `AccountLocalStore`, `YieldConfigRepository`, `SyncService`.
`YieldConfigsScreen` lists status badge (active/paused/completed) + APY + payout frequency;
`YieldConfigFormScreen` is a scrollable form using `FormAppBarActions`.

### Routes (outside `ShellRoute`)

| Path | Scope | Screen |
|------|-------|--------|
| `/yields` | `YieldConfigRouteScope` | `YieldConfigsScreen` |
| `/yields/new` | `YieldConfigFormRouteScope` | `YieldConfigFormScreen` |
| `/yields/:yieldId/edit` | `YieldConfigFormRouteScope` | `YieldConfigFormScreen` |

### Entry points

1. **Settings → Preferencias → Rendimientos** — opens `/yields`.
2. **FAB menu on `TransactionsScreen`** — "Nuevo rendimiento".
3. **FAB on `YieldConfigsScreen`** — `/yields/new`.

### Form validation rules

`name` required; `account` required; `amount` (capital) required `> 0` (decimal→cents); `apy_rate`
required `> 0`; `next_date` required; `payout_frequency` required (default `monthly`, values
daily/weekly/monthly/at_maturity). When `at_maturity`: `term_days > 0` and `maturity_date` are also
required. `auto_renew` boolean (default false); `status` active/paused/completed (default `active`,
stored lowercase).
