# Credit Card MSI Support — Transaction Traceability and Liquidity Projection

## Context

Pocket Pilot currently treats each credit card purchase as a full-month impact, which overstates monthly cash-flow pressure for purchases financed as installments (MSI). This creates two distortions:

1. Monthly budgets absorb the full amount in the purchase month.
2. Safe-to-spend ignores realistic near-term card payment obligations unless users infer them manually.

This spec introduces `installments_count` for transactions and adds a projection engine (`CreditCardOracle`) to estimate the monthly payment required to avoid interest, using each card's billing cycle when configured.

## Scope

In scope:

- Add `installments_count` to transaction schema (PostgreSQL + SQLite baseline migration `001`)
- Add `installments_count` to transaction gRPC contract and end-to-end mapping
- Add frontend projection component `CreditCardOracle` for monthly card obligation
- Update dashboard safe-to-spend formula to subtract estimated card payment
- Update budget spend query to prorate MSI by monthly installment amount
- Add focused test coverage for oracle math, budget proration, and dashboard integration

Out of scope:

- New tables for installment schedules
- Materialized per-installment child transactions
- Cross-currency conversion for card obligations (aggregation remains per currency)
- UI redesign for transaction form and dashboard cards

## Architectural Design

### Boundaries and responsibilities

1. **Transaction persistence layer (backend + frontend)**
   - Stores and syncs `installments_count` as a first-class transaction attribute.
   - Enforces strict validity: `installments_count >= 1`.
   - Does not compute installment schedules.

2. **Projection layer (`CreditCardOracle`, frontend Dart)**
   - Computes monthly required payment per credit card account and per currency.
   - Owns cycle interpretation, MSI proration, payment netting, and fallback logic.
   - Is deterministic and side-effect free.

3. **Dashboard orchestration (`DashboardRepository`)**
   - Fetches account balances/goals as today.
   - Fetches oracle inputs from local store.
   - Computes safe-to-spend including estimated card payment.

4. **Budget computation (`BudgetLocalStore`)**
   - Keeps SQL-based dynamic spend computation.
   - Applies installment proration in query-time arithmetic.

This keeps financial logic isolated from DAOs and avoids spreading cycle math across unrelated modules.

## Data Contract Changes

### Database schema

Add column in baseline migration files:

- `backend/migrations/001_initial_schema.sql`
- `frontend/assets/migrations/001.sql`

Column:

- `installments_count` integer, `NOT NULL`, `DEFAULT 1`

Notes:

- Baseline-file edit is allowed by project convention in MVP without production data.
- Existing transaction type semantics remain unchanged.

### gRPC contract

File: `proto/pocket_pilot/v1/transaction_service.proto`

Add field to `Transaction` message:

- `int32 installments_count = 17;`

Rationale:

- Audit fields remain in positions 1-3.
- Existing field numbers are preserved.
- New field is additive and explicit.

### Backend mapping

Files:

- `backend/internal/transaction/repository.go`
- `backend/internal/transaction/handler.go`

Changes:

- Extend `Transaction` struct with `InstallmentsCount int32`.
- Include `installments_count` in `scanColumns`, `INSERT`, `ON CONFLICT UPDATE`, and row scans.
- Map proto `<->` domain in `fromProto`/`toProto`.
- Reject `installments_count < 1` during upsert validation path with `InvalidArgument`.

### Frontend mapping

Files:

- `frontend/lib/src/features/transactions/domain/transaction.dart`
- `frontend/lib/src/features/transactions/data/transaction_repository.dart`
- `frontend/lib/src/features/transactions/data/transaction_remote_service.dart`
- `frontend/lib/src/features/transactions/data/transaction_sync_handler.dart`

Changes:

- Add `installmentsCount` to `TransactionModel` with strict invariant `>= 1`.
- Persist in SQLite map payloads and outbox server payload.
- Include in gRPC request/response mapping.
- Ensure create/update flows set explicit `1` only when the field is omitted by caller.
- If caller provides `installments_count < 1`, fail validation (no coercion/normalization).

## CreditCardOracle Design

### Purpose

Compute estimated monthly payment required to avoid interest for each credit card account for a target payment month `M`.

### Suggested placement

- `frontend/lib/src/features/dashboard/domain/credit_card_oracle.dart`

### Inputs

1. Card account metadata:
   - `account_id`
   - `currency_code`
   - `statement_day` (nullable)
   - `payment_due_day` (nullable)
2. Cleared, non-deleted credit-card transactions for relevant accounts:
   - `account_id`, `type`, `amount_cents`, `date`, `installments_count`
3. Target month (`year`, `month`) and reference date (`now`) for netting cutoff.

### Included transaction types for payment estimation

- Charges/obligations: `expense`, `transfer_out`
- Payments/credits: `transfer_in`, `income`

Only `status = 'cleared'` and `deleted_at IS NULL` are included.

### Cycle interpretation

For accounts with both `statement_day` and `payment_due_day`:

1. Build `due_date(M)` by clamping due day to month end.
2. Determine current statement close date `close_curr` (latest close date on or before `due_date(M)`).
3. Determine previous statement close date `close_prev` (one cycle earlier).
4. One-shot charges (`installments_count = 1`) contribute if transaction date is in `(close_prev, close_curr]`.

Definitions used by oracle:

- `close(y,m) = date(y,m, clamp(statement_day, last_day_of_month(y,m)))`
- `month_idx(y,m) = y * 12 + (m - 1)`

For accounts missing either cycle day:

- Fallback to calendar mode for that account:
  - One-shot charges come from previous calendar month relative to `M`.

### MSI installment contribution

For each transaction with `installments_count > 1`:

1. Compute `purchase_close` as the first statement close date `>= transaction.date`.
2. Compute `target_close = close_curr` for payment month `M`.
3. Define cycle offset:
   - `k = month_idx(target_close) - month_idx(purchase_close)`
4. Transaction contributes to payment month `M` if `0 <= k < installments_count`.
3. Installment amount uses integer arithmetic:
   - `base = amount_cents ~/ installments_count`
   - `residual = amount_cents % installments_count`
   - `k=0`: `base + residual`
   - `k>0`: `base`

This guarantees exact cent conservation and applies the agreed rule "residual in first installment".

Fallback mode (missing `statement_day` or `payment_due_day`):

1. One-shot charges use previous calendar month relative to `M`.
2. MSI first due month is `purchase_month + 1`.
3. Fallback offset:
   - `k = month_idx(M) - month_idx(purchase_month + 1)`
4. Contribution rule remains `0 <= k < installments_count` with same residual distribution.

### Gross and net obligation

For each account/month:

- `gross = one_shot_cycle_charges + active_msi_installments`
- `applied_payments = sum(transfer_in + income)` for the same card account in a deterministic netting window:
  - cycle mode window: `[first_day_of_month(M), min(now, due_date(M))]`
  - fallback mode window: `[first_day_of_month(M), min(now, last_day_of_month(M))]`
  - if `now < first_day_of_month(M)`, `applied_payments = 0`
- `net = max(0, gross - applied_payments)`

Oracle returns per-account and per-currency totals for net obligation.

## Dashboard Metrics Redefinition

File: `frontend/lib/src/features/dashboard/data/dashboard_repository.dart`

Current formula:

- `safe_to_spend = liquid_assets - goals`

New formula:

- `safe_to_spend = liquid_assets - goals - estimated_card_payment`

Where:

- `estimated_card_payment` is summed by currency from `CreditCardOracle` for current month.

Buying power remains:

- `buying_power = safe_to_spend + revolving_credit`

No currency mixing is introduced; all dashboard aggregates remain per currency key.

## Budget Spend Proration

File: `frontend/lib/src/features/budgets/data/budget_local_store.dart`

`computeSpentCents(categoryId, period)` continues using raw SQL but changes to period-overlap proration by month index.

Definitions:

- `purchase_idx = year(t.date) * 12 + (month(t.date) - 1)`
- `tx_start_idx = purchase_idx`
- `tx_end_idx = purchase_idx + installments_count - 1`
- `period_start_idx` / `period_end_idx`:
  - MONTHLY: current month to current month
  - YEARLY: January current year to December current year
- `overlap_start = max(tx_start_idx, period_start_idx)`
- `overlap_end = min(tx_end_idx, period_end_idx)`
- `overlap_months = max(0, overlap_end - overlap_start + 1)`

Installment arithmetic (integer cents):

- `base = amount_cents ~/ installments_count`
- `residual = amount_cents % installments_count`
- `period_amount = base * overlap_months + residual_if_first_installment_in_period`
- `residual_if_first_installment_in_period = residual` only when `purchase_idx BETWEEN period_start_idx AND period_end_idx`, else `0`

Signed contribution:

- expense: `+period_amount`
- income: `-period_amount`
- other types: `0`

This rule includes active MSI months even when original purchase date is outside the target period.

Net spend sign remains:

- expense adds
- income subtracts

Transfers remain excluded.

## Data Flow Summary

1. Transactions are stored/synced with `installments_count`.
2. Dashboard local store provides:
   - account balances (existing)
   - goal targets (existing)
   - card cycle and transaction input rows (new read path)
3. `CreditCardOracle` computes monthly net card obligation.
4. `DashboardRepository.calculateAllMetrics()` subtracts that obligation from safe-to-spend.
5. Budget spend query reflects only monthly installment impact instead of full financed amount.

## Error Handling and Guardrails

- Reject invalid `installments_count < 1` at write-time (backend and frontend domain guard).
- Ignore non-cleared or soft-deleted transactions in projections.
- Clamp invalid cycle day overflow to month end for deterministic date math.
- If cycle config missing, fallback to calendar mode (non-blocking).
- Never allow negative estimated obligation after payment netting.

## Verification Strategy

### Unit tests — Oracle

Create tests for:

1. Real cycle charge capture for one-shot transactions.
2. Calendar fallback when statement/due day is absent.
3. MSI month-range activation by cycle offset (`k`) and exact cent conservation.
4. Residual cent allocation in first installment.
5. Net obligation floor at zero after applied payments.
6. Multi-card same-currency and multi-currency aggregation.
7. Cross-boundary example where purchase occurs after statement close and first installment shifts to next payment month.

### Unit tests — Budget SQL behavior

Validate:

1. Full amount for `installments_count = 1`.
2. Prorated installment for `installments_count > 1`.
3. Correct month inclusion/exclusion by financing window.
4. Expense/income sign netting preserved.

### Unit tests — Dashboard integration

Validate:

1. `safe_to_spend` decreases by oracle net obligation.
2. `buying_power` remains `safe_to_spend + revolving`.
3. Existing balances/goals behavior remains unchanged when no credit-card obligations exist.

### Contract checks

Validate proto/domain/sql mapping roundtrip preserves `installments_count` through:

- local store insert/read
- outbox payload
- remote service mapping
- sync conflict merge path

## Acceptance Criteria

1. Transaction schema and proto expose `installments_count` end-to-end.
2. MSI transaction with `installments_count > 1` impacts monthly budget by installment, not full amount.
3. Dashboard safe-to-spend subtracts current-month card net obligation.
4. Card obligation uses real cycle dates when configured and calendar fallback otherwise.
5. Payment netting prevents double-penalizing liquidity after user already paid during the month.
6. All calculations use integer cents only (`amount_cents`), with deterministic rounding behavior.
