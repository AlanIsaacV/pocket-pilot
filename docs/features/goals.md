# Goals & Liquidity Architecture

## Overview

Goals represent financial targets the user wants to reach by a specific date. Each goal has a target amount, currency, and deadline. Progress tracking is designed to work automatically via **total liquidity** rather than manual savings assignment.

## Schema (Goal)

| Column | PG Type | SQLite Type | Notes |
|--------|---------|-------------|-------|
| `id` | uuid PK | TEXT PK | |
| `user_id` | uuid NOT NULL | — | Only in PG (multi-tenant) |
| `name` | text NOT NULL | TEXT NOT NULL | |
| `target_amount_cents` | bigint NOT NULL | INTEGER NOT NULL | |
| `target_date` | date NOT NULL | DATE NOT NULL | YYYY-MM-DD |
| `currency_code` | text NOT NULL | TEXT NOT NULL | ISO 4217 (e.g. MXN, USD) |
| `created_at` | timestamptz | DATETIME | |
| `updated_at` | timestamptz | DATETIME | LWW conflict resolution key |
| `deleted_at` | timestamptz | DATETIME | Soft delete |

## Proto Contract

```protobuf
message Goal {
  string id = 1;
  string name = 2;
  int64 target_amount_cents = 3;
  string currency_code = 4;
  string target_date = 5;
  google.protobuf.Timestamp created_at = 6;
  google.protobuf.Timestamp updated_at = 7;
  google.protobuf.Timestamp deleted_at = 8;
}
```

Service: `GoalService` with `ListGoals`, `UpsertGoal`, `DeleteGoal` RPCs.

## Computed Properties (GoalModel)

All computed properties live in `frontend/lib/src/features/goals/domain/goal.dart`. They accept an optional `liquidityAssignedCents` (defaults to `0`, which preserves the "no liquidity known" behavior for callers that don't wire it yet).

| Property | Behavior |
|----------|----------|
| `progressPercentageAt(now, {liquidityAssignedCents})` | `liquidityAssignedCents / targetAmountCents * 100` (0 when target is 0). |
| `monthlyRequiredCentsAt(now, {liquidityAssignedCents})` | `ceil(max(0, targetAmountCents - liquidityAssignedCents) / monthsRemaining)`. |
| `isOverdueAt(now, {liquidityAssignedCents})` | `targetDate < now` AND `liquidityAssignedCents < targetAmountCents`. |
| `monthsRemainingAt(now)` | Calendar diff from now to targetDate (min 1). |

The no-arg getters (`progressPercentage`, `monthlyRequiredCents`, `isOverdue`) pass `liquidityAssignedCents = 0` and therefore report "worst case / unfunded" figures. `GoalsListTab` and `GoalViewModel` always pass real liquidity; other call sites (dashboard) deliberately don't.

## Liquidity Model

**Total liquidity per currency** = sum of `bank` + `cash` account balances (cleared, non-deleted transactions) grouped by `currency_code`. Computed by `GoalLocalStore.getLiquidByCurrency()`. The SQL predicate mirrors `DashboardLocalStore.getBalancesPerAccount` so goal progress stays aligned with `DashboardMetrics.liquidAssetsCents`.

### FIFO allocation across multiple goals

When several goals share a currency, the total pool is distributed **FIFO by `targetDate` ascending** (tiebreaker: `createdAt` ascending for stability). Each goal reserves up to its `targetAmountCents`; the remainder passes to the next goal. Deleted goals are skipped. Goals whose currency has no entry in the liquidity map receive 0.

Rationale: the soonest deadline gets funded first, matching typical financial urgency. The allocation is deterministic, fully client-side, and requires no persistence or "manual assignment" UI.

Implemented in `GoalMath.allocateLiquidity(goals, liquidByCurrency) → Map<goalId, liquidityAssignedCents>`. `GoalViewModel._reloadLocal` caches the result so `GoalsListTab` can look it up with `vm.liquidityForGoal(goal.id)` in O(1).

### Dashboard integration (intentionally unchanged)

`DashboardRepository.calculateAllMetrics` still calls `GoalMath.totalMonthlyRequiredCents(goalsForCurrency, now: now)` **without** passing `liquidByCurrency`, so `goalMonthly` reflects the unfunded case. This is deliberate: `safeToSpend = liquid - goalMonthly - cardPayment` already treats `liquid` as an additive, and reducing `goalMonthly` by accumulated liquidity would double-count the same pesos (inflating safeToSpend). If the product later introduces explicit per-goal "assignment" or separate savings accounts, revisit this.

### Completion state in UI

`GoalsListTab._GoalCard` selects one of three statuses:
- **Completada** (primary green) — when `liquidityAssignedCents >= targetAmountCents`.
- **Atrasada** (error red) — when `isOverdueAt(...)` returns true (i.e., past date and not covered).
- **En curso** (tertiary) — otherwise.

## File Map

### Backend (Go)
- `backend/internal/goal/model.go` — Goal struct
- `backend/internal/goal/handler.go` — gRPC handler (toProto/fromProto, CRUD RPCs)
- `backend/internal/goal/repository.go` — PostgreSQL queries
- `backend/internal/goal/validation.go` — Business rules

### Frontend (Dart)
- `frontend/lib/src/features/goals/domain/goal.dart` — GoalModel + GoalMath (`allocateLiquidity`, liquidity-aware `totalMonthlyRequiredCents`)
- `frontend/lib/src/features/goals/data/goal_local_store.dart` — SQLite DAO + `getLiquidByCurrency()`
- `frontend/lib/src/features/goals/data/goal_repository.dart` — Local-first + outbox + liquidity pass-through
- `frontend/lib/src/features/goals/data/goal_remote_service.dart` — gRPC client
- `frontend/lib/src/features/goals/data/goal_sync_handler.dart` — Delta sync handler
- `frontend/lib/src/features/goals/ui/goal_view_model.dart` — UI state (ChangeNotifier)
- `frontend/lib/src/features/goals/ui/goal_form_screen.dart` — Create/edit form
- `frontend/lib/src/features/goals/ui/goals_list_tab.dart` — List tab in AccountsScreen

### Proto
- `proto/pocket_pilot/v1/goal_service.proto`

### Migrations
- `backend/migrations/004_goals.sql` (PostgreSQL)
- `frontend/assets/migrations/004.sql` (SQLite)

### Tests
- `backend/internal/goal/validation_test.go`
- `frontend/test/goal_model_math_test.dart`
