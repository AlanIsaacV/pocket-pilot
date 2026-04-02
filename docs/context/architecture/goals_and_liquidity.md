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

All computed properties live in `frontend/lib/src/features/goals/domain/goal.dart`.

| Property | Current Behavior | Future (with liquidity) |
|----------|-----------------|------------------------|
| `progressPercentage` | Time-based: `monthsElapsed / totalMonths * 100` | `liquidezAcumulada / targetAmountCents * 100` |
| `monthlyRequiredCents` | `ceil(targetAmountCents / monthsRemaining)` | `ceil((targetAmountCents - liquidezAsignada) / monthsRemaining)` |
| `isOverdue` | `targetDate < now` (month comparison) | `targetDate < now AND liquidez < targetAmountCents` |
| `monthsRemaining` | Calendar diff from now to targetDate (min 1) | No change |

## Liquidity Concept (Not Yet Implemented)

**Total liquidity** = sum of available balances across all user accounts. This is the "liquid cash" the user has at any point in time.

### Why liquidity instead of manual savings?

In practice, users don't park money in a single account per goal. They have multiple accounts with mixed purposes. Tracking "which peso belongs to which goal" is manual overhead that doesn't reflect reality. Instead:

- The system calculates the **total monthly quota** across all goals (`GoalMath.totalMonthlyRequiredCents`)
- If total liquidity >= accumulated monthly quotas, goals are on track
- If liquidity falls short, the user should adjust: extend deadlines, reduce targets, or increase income

### Integration points when liquidity is available

Search for `TODO(liquidity)` in the codebase. Key files:

1. **`frontend/lib/src/features/goals/domain/goal.dart`**
   - `progressPercentageAt()` — switch from time-based to liquidity-based
   - `monthlyRequiredCentsAt()` — subtract liquidity from remaining amount
   - `isOverdueAt()` — don't mark overdue if liquidity covers the target

2. **`frontend/lib/src/features/goals/ui/goals_list_tab.dart`**
   - Progress bar currently shows time progress; update to show liquidity coverage
   - Add "Completada" badge when liquidity >= target

3. **Liquidity provider** — needs to be created:
   - Calculate sum of all account balances (requires `AccountsViewModel` or a new `LiquidityService`)
   - Inject into `GoalViewModel` or pass as parameter to computed properties

## File Map

### Backend (Go)
- `backend/internal/goal/model.go` — Goal struct
- `backend/internal/goal/handler.go` — gRPC handler (toProto/fromProto, CRUD RPCs)
- `backend/internal/goal/repository.go` — PostgreSQL queries
- `backend/internal/goal/validation.go` — Business rules

### Frontend (Dart)
- `frontend/lib/src/features/goals/domain/goal.dart` — GoalModel + GoalMath
- `frontend/lib/src/features/goals/data/goal_local_store.dart` — SQLite DAO
- `frontend/lib/src/features/goals/data/goal_repository.dart` — Local-first + outbox
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
