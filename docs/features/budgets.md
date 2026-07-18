# Budgets — Architecture & Data Model

## Concept
A Budget is a **spending limit** for a specific expense category over a period (monthly or yearly). It does NOT hold money or affect liquidity — it's purely a velocity cap. The **spent amount is calculated dynamically** from transactions at query time, never persisted.

## Schema

### PostgreSQL (`backend/migrations/001_initial_schema.sql`)
```sql
CREATE TABLE budgets (
    id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id            uuid   NOT NULL,
    category_id        uuid   NOT NULL REFERENCES categories (id),
    limit_amount_cents BIGINT NOT NULL,
    currency_code      TEXT   NOT NULL,
    period             TEXT   NOT NULL,  -- 'MONTHLY' or 'YEARLY'
    ...audit fields...
    UNIQUE(user_id, category_id)  -- one budget per category per user
);
```

### SQLite (`frontend/assets/migrations/001.sql`)
Same structure minus `user_id`. `UNIQUE(category_id)` enforced locally.

## Proto Contract (`proto/pocket_pilot/v1/budget_service.proto`)
- `Budget` message: audit fields (1-3), id (4), category_id (5), limit_amount_cents (6), currency_code (7), period (8)
- `BudgetService`: ListBudgets, UpsertBudget, DeleteBudget (standard CRUD pattern)

## Currency
`currency_code` is visual-only in MVP — no cross-currency conversion is performed. The user is responsible for logging transactions in the same currency as the budget. The field uses the same currency preferences system as accounts and goals (selector with "Configurar monedas" shortcut to `/settings/currency`).

## Backend (`backend/internal/budget/`)
Standard module following goal pattern: model.go, repository.go (LWW upsert), validation.go, handler.go. Registered in `cmd/server/main.go`.

## Frontend

### Data Layer (`frontend/lib/src/features/budgets/data/`)
- `BudgetLocalStore` — CRUD + `computeSpentCents(categoryId, period)` raw SQL query
- `BudgetRepository` — local-first + outbox, exposes `getBudgetStatuses()`
- `BudgetRemoteService` — gRPC client
- `BudgetSyncHandler` — syncOrder=8

### Dynamic Spend Calculation (`computeSpentCents`)
```sql
SELECT COALESCE(SUM(
  CASE WHEN type = 'expense' THEN amount_cents
       WHEN type = 'income'  THEN -amount_cents
       ELSE 0 END
), 0) as spent
FROM transactions
WHERE category_id = ? AND date >= ? AND date <= ? AND deleted_at IS NULL
```
- Period boundaries: MONTHLY = first/last day of current month, YEARLY = Jan 1 / Dec 31
- Netting: expenses add, income subtracts (handles refunds)

### Domain (`frontend/lib/src/features/budgets/domain/`)
- `BudgetModel` — with fromProto/fromMap/toMap/toServerMap/toProto/normalized
- `BudgetStatus` — computed DTO: spentAmountCents, remainingAmountCents, progressPercentage

### UI (`frontend/lib/src/features/budgets/ui/`)
- `BudgetViewModel` — local-first load, 5s throttle sync, exposes `List<BudgetStatus>`
- `BudgetsListTab` — third tab in AccountsScreen, cards with category icon/color, progress bar, "En curso"/"Excedido" badges
- `BudgetFormScreen` — category picker (navigates to `CategoryPickerScreen`), limit amount, currency selector, period segmented button
- Provided via `AccountsRouteScope` (MultiProvider with AccountsViewModel, GoalViewModel, BudgetViewModel)

### Routes
| Path | Screen |
|------|--------|
| `/accounts` (tab 2) | BudgetsListTab |
| `/accounts/budgets/new` | BudgetFormScreen |
| `/accounts/budgets/new/category` | CategoryPickerScreen |
| `/accounts/budgets/:id/edit` | BudgetFormScreen |
| `/accounts/budgets/:id/edit/category` | CategoryPickerScreen |

## Sync
- Entity type: `budget`, syncOrder: 8
- LWW conflict resolution via `updated_at`
- FK dependency: categories (synced earlier)
