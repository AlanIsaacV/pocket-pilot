# Statistics Tab — Historical Category Analytics

Read-only feature that lets the user inspect per-category spending/income over a configurable window (3/6/12 months), drill into any category for a monthly bar chart, and seed a new budget from the observed average. Lives as the second tab of `DashboardScreen` (alongside `Resumen`).

Spec: `docs/superpowers/specs/2026-04-17-statistics-tab-design.md`. Plan: `docs/superpowers/plans/2026-04-17-statistics-tab.md`.

## Integration Point

`DashboardScreen` hosts a `TabBar` with two tabs:
- **Resumen** → `DashboardSummaryTab` (extracted from the old body).
- **Estadísticas** → `StatisticsTab`.

The outer AppBar (title + `NotificationBell` + `_FilterButton`) stays the same across both tabs. `DashboardFilterViewModel.currencyCode` is shared and drives both tabs.

`DashboardRouteScope` now provides `StatisticsRepository` + `StatisticsViewModel` in addition to the existing dashboard VMs.

## Routes

| Path | Screen | Notes |
|------|--------|-------|
| `/dashboard` | `DashboardScreen` | Defaults to the Resumen tab. |
| `/dashboard/statistics/category/:categoryId?currency=MXN` | `CategoryHistoryScreen` | Push-navigated. Accepts `CategorySeriesDTO` as `extra` to paint the header while data loads. The `currency` query param is forwarded from the parent dashboard filter (same pattern as `/accounts/budgets/new`) so the detail survives the route's isolated `DashboardRouteScope`. `CategoryHistoryScreen._load()` resolves currency as `initialCurrencyCode ?? initialSummary.currencyCode ?? filterVM.currencyCode`. |

## Feature Structure (`features/statistics/`)

```
features/statistics/
├── data/
│   ├── statistics_local_store.dart   # Raw SQL aggregates (read-only)
│   └── statistics_repository.dart    # Orchestrator: sign-flip + trend + zero-fill + budget
├── domain/
│   ├── trend.dart                    # enum Trend + kTrendFlatThresholdRatio (0.05) + computeTrend
│   ├── window_math.dart              # StatisticsWindow.fromNow (pure, testable)
│   ├── category_series_dto.dart      # per-category aggregate
│   ├── monthly_point_dto.dart        # {yearMonth, amountCents}
│   └── category_history_dto.dart     # {summary, points, budget?}
└── ui/
    ├── statistics_view_model.dart    # ChangeNotifier, reactive to DashboardFilterViewModel
    ├── statistics_tab.dart           # List body (Gastos + Ingresos sections)
    ├── category_history_screen.dart  # Detail screen (push)
    └── widgets/
        ├── time_window_chips.dart    # SegmentedButton 3m/6m/12m
        ├── category_list_row.dart
        ├── stat_delta_row.dart
        └── category_monthly_bar_chart.dart  # fl_chart BarChart
```

No remote service, no outbox, no sync handler. The feature is derived entirely from already-synced transactions, categories, and budgets.

## Data Flow

```
StatisticsLocalStore (SQL)
  → StatisticsRepository (sign-flip, trend, avg, zero-fill, budget lookup)
    → StatisticsViewModel (currency reactivity, window state)
      → StatisticsTab (list) / CategoryHistoryScreen (detail)
```

## Netting Semantics

Matches `BudgetLocalStore.computeSpentCents`: expenses add, income subtracts, transfers are excluded.

```
signed = (type='expense') ?  amount
       : (type='income')  ? -amount
       : 0
```

Effect:
- Expense category: a refund (income row on that category) reduces the total.
- Income category: totals come back negative from SQL; the repository **sign-flips for `kind='income'`** so the domain DTOs always expose a positive magnitude regardless of kind.

**MSI proration NOT applied** (unlike Budgets): an `installments_count > 1` transaction is attributed entirely to its purchase-month bar. Tracked as a deferred follow-up.

## Window Math (`StatisticsWindow.fromNow`)

Pure helper; `now` is injected for testability.

- `windowEnd` = first day of the month AFTER `now` (exclusive upper bound).
- `windowStart` = first day of the month `N-1` months before `now` (inclusive).
- `windowMid` = first day of month at offset `N~/2` from `windowStart` (trend split; asymmetric for odd N but still useful).
- `currentYm` = `'YYYY-MM'` of `now`.
- `monthsInWindow` = `N` contiguous `'YYYY-MM'` strings (used by zero-fill).

All dates are `'YYYY-MM-DD'` strings to compare lexicographically against the SQLite `date` column — same contract as `TransactionFilter`.

## SQL

### Query 1 — Category summary (`getCategorySeries`)

Embeds four aggregates in one query to avoid N+1 round-trips:
- `total_cents` over the full window.
- `current_month_cents` (filtered by `strftime('%Y-%m', t.date) = :currentYm`).
- `first_half_cents` (date `< windowMid`) and `second_half_cents` (date `>= windowMid`) — vestigial; not consumed after trend semantics switched to current-vs-avg, but kept for future "window half trend" use.

`LEFT JOIN transactions` so categories with no activity are still visible to the `HAVING ABS(total_cents) > 0` filter. `ORDER BY ABS(total_cents) DESC`. Deleted categories excluded (`c.deleted_at IS NULL`) — deferred to surface later.

**Column alias**: SQL selects `c.type AS kind` so the SQLite column (`categories.type`) maps to the semantic domain field `kind` (avoids collision with `transactions.type` / `accounts.type`).

### Query 2 — Monthly series (`getMonthlySeries`)

Grouped by `strftime('%Y-%m', t.date)`. Returns only months with activity; the repository zero-fills the rest using `StatisticsWindow.monthsInWindow` so bars render as empty, not missing.

### Query 3 — Transactions for a selected month

No new helper — reuses `TransactionLocalStore.queryRowsFiltered(TransactionFilter)` composed with `categoryIds`, `currencyCode`, and a `[monthStart, monthEnd]` date range (BETWEEN is inclusive, so `dateTo` is the last day of the month, not the first of the next).

### Query 4 — Budget for category

Cross-feature read via new `BudgetLocalStore.findByCategory(categoryId)` (returns `Map<String,dynamic>?` scoped by the existing `UNIQUE(category_id)` invariant). If the row's `currency_code` differs from the active filter, the repository resolves `budget = null` (preserves Budgets' visual-only currency semantics). Lookup failures are swallowed and logged — the chart must still render.

## Trend Semantics

`computeTrend(currentCents, avgCents)`:
- `flat` if `avgCents == 0` OR the rounded percent delta is below `kTrendFlatThresholdRatio = 0.05`.
- Otherwise `up` (current > avg) or `down`.

Compares the current month against the window average — the **same** metric `StatDeltaRow._deltaColor` uses in the detail screen — so the list-row arrow and the detail `±N%` badge never disagree. Delta coloring flips by `kind`: for expense categories, up = worse (red); for income, up = better (primary).

## UI — Statistics Tab (List)

Order: `TimeWindowChips` → `Gastos` section (expense rows, sorted by total desc) → `Ingresos` section (income rows; omitted if empty). Loading shows a spinner; empty state shows "Aún no hay suficiente historial" + CTA to `/transactions`; error state shows `Reintentar`. `RefreshIndicator` re-runs Query 1.

Row (`CategoryListRow`): category icon (colored) + name + current-month amount (right), with a second line `prom. últimos Nm: $X` and a trend chip. Tap pushes `/dashboard/statistics/category/:categoryId` with `CategorySeriesDTO` as `extra`.

## UI — Category History Screen (Detail)

Layout (scroll):
1. AppBar with category name + overflow action "Ver transacciones" (navigates to `/transactions` with `categoryId` in `extra`).
2. `TimeWindowChips` (same control as the list tab, local to the screen).
3. `StatDeltaRow` — Promedio + Este mes + `±N%` badge.
4. `CategoryMonthlyBarChart` — `fl_chart` bar chart:
   - X labels: month abbreviation in Spanish (`ene`, `feb`, …). Year suffix (`dic '25`) added when the window crosses years.
   - Current-month bar in `cs.primary`; past months in `cs.surfaceContainerHigh`.
   - If `budget != null && budget.period == 'MONTHLY'`: dashed `HorizontalLine` via `extraLinesData` at `limitAmountCents`.
   - Empty data: if all points are zero, render a placeholder instead of a chart.
   - Tap a bar → selects that month (`_selectedBarIndex`) and shows a tooltip (`BarTouchTooltipData`).
5. `_BudgetCard` (conditional):
   - `budget == null` → outline card with "Crea un presupuesto basado en tu promedio" and `Crear presupuesto` button → navigates to `/accounts/budgets/new?categoryId=X&suggested=avgCents&currency=C`.
   - `budget != null && MONTHLY` → LinearProgressIndicator + Editar button.
   - `budget != null && YEARLY` → label "Presupuesto anual — línea no mostrada" + Editar.

## Cross-Feature Deliverables (Budgets)

Both strictly additive (no migration, no sync impact):

1. **`BudgetLocalStore.findByCategory(categoryId)`** — per-category lookup used by Query 4.
2. **`BudgetFormScreen` accepts `initialCategoryId` / `initialLimitCents` / `initialCurrencyCode`**; the `/accounts/budgets/new` route reads `categoryId`, `suggested` (cents), and `currency` as `go_router` query params and forwards them. Query params (not route `extra`) so the deep link is shareable and survives process death. Behavior is unchanged when the params are absent.

## Dependencies

- New: `fl_chart ^0.69.0`.
- Reused: `BudgetLocalStore` (cross-feature read), `TransactionLocalStore.queryRowsFiltered`, `BudgetStatus` DTO, `DashboardFilterViewModel`, `DatabaseHelper`.

## Testing

- `test/statistics_window_math_test.dart` — 4 pure tests (bounds, month sequence, crossing years).
- `test/statistics_repository_test.dart` — 6 tests (avg, sign-flip for income, trend up, zero-fill, budget currency mismatch → null, budget lookup failure → null).
- `test/statistics_view_model_test.dart` — 4 tests (empty currency, window change reload, currency change reload, error surface).
- `test/statistics_category_list_row_test.dart` / `test/statistics_stat_delta_row_test.dart` — widget smoke tests.
- `test/statistics_tab_smoke_test.dart` — 3 smoke tests (data present, empty, error).
- `test/budget_form_prefill_test.dart` — 2 constructor tests for the pre-fill params.

`StatisticsLocalStore` SQL is not unit-tested at the DB level (project pattern: see `dashboard_repository_credit_card_obligation_test.dart`). Coverage happens via repository tests with `_FakeLocalStore` + manual verification.

## Deferred Follow-Ups

Each is a standalone design cycle:
1. Historical metrics series (net worth, liquidity, buying power).
2. Cash flow (income vs expenses, per account and global).
3. Arbitrary period comparison (A vs B).
4. Forecasting.
5. Surface deleted categories with historical data.
6. MSI proration for statistics.
