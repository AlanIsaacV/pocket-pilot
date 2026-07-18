# Statistics Tab — Historical Category Analytics

## Context

The dashboard today shows only current-state metrics (net worth, liquidity, buying power, month-to-date spend by category/nature/tag). There is no temporal dimension: the user cannot see how spending in a category has evolved, how the current month compares to the historical average, or use historical data to set realistic budgets.

This spec defines the first iteration of a new **"Estadísticas"** tab inside `DashboardScreen`, focused on **historical spending per category**. Explicitly out of scope for this iteration: historical net-worth/liquidity series, income-vs-expense cash flow, arbitrary period comparison, and forecasting. Those are tracked as follow-up sub-projects.

The feature closes the loop with the existing Budgets feature (`architecture/budgets.md`) by surfacing the observed average as a suggested budget limit.

## Goals

1. Let the user see per-category spending/income evolution over 3, 6, or 12 months.
2. Provide a historical average, current-month value, and trend indicator per category.
3. From a category's detail view, let the user either see the existing budget line on the chart or create a new budget seeded with historical data.
4. Let the user drill into the transactions of a specific month from the chart.

## Non-Goals

- Historical time-series of aggregate metrics (net worth, liquidity, buying power).
- Cash-flow views (income vs expenses, per account or global).
- Arbitrary period comparison (A vs B custom ranges).
- Predictions / forecasting.
- Cross-currency rollups (uses the existing single-currency filter model).
- Export or share of charts.

## Architecture

### Integration Point

Follows `DashboardScreen`'s existing layout model. A `TabBar` is added between the shared currency filter and the content body. Two tabs:

- **Resumen** — current widgets refactored into `DashboardSummaryTab`.
- **Estadísticas** — new `StatisticsTab`.

The shared `DashboardFilterViewModel` (already wired into the screen) provides `currencyCode` to both tabs. The time window (3/6/12 months) is local state on `StatisticsViewModel` — not persisted to disk.

### File Structure

New feature follows the project's 3-layer Clean Architecture pattern (Domain / Data / UI):

```
frontend/lib/src/features/statistics/
├── data/
│   ├── statistics_local_store.dart       # Raw SQL aggregation queries (read-only)
│   └── statistics_repository.dart        # Orchestrates queries + budget integration
├── domain/
│   ├── category_series_dto.dart
│   ├── monthly_point_dto.dart
│   ├── category_history_dto.dart
│   └── trend.dart                        # enum { up, down, flat }
└── ui/
    ├── statistics_view_model.dart        # ChangeNotifier for list + detail
    ├── statistics_tab.dart               # List view (tab body)
    ├── category_history_screen.dart      # Detail screen (push-navigated)
    └── widgets/
        ├── category_list_row.dart
        ├── category_monthly_bar_chart.dart
        ├── time_window_chips.dart
        └── stat_delta_row.dart
```

### Dependency Injection

`DashboardRouteScope` grows to provide `StatisticsViewModel` via the existing `MultiProvider`. `StatisticsRepository` depends on:
- `DatabaseHelper` (shared singleton)
- `BudgetLocalStore` (reused — cross-feature read-only dependency)

No remote service, no outbox, no sync handler — Statistics is read-only, derived from already-synced data.

### Routes

| Path | Screen | Notes |
|------|--------|-------|
| `/dashboard` | `DashboardScreen` | Defaults to `Resumen` tab. |
| `/dashboard/statistics/category/:categoryId` | `CategoryHistoryScreen` | Push-navigated. Accepts `CategorySeriesDTO` as `extra` to paint the header immediately while data loads. |

## Domain Layer (DTOs)

### `Trend` (enum)

`up` / `down` / `flat`. `flat` applies when the relative delta between the first-half total and second-half total of the selected window is below `kTrendFlatThresholdRatio` (a single named constant in `features/statistics/domain/`, default `0.05`). The same constant is reused for the neutral-delta coloring on the detail stat row, so both UI elements agree.

If only one half has data (e.g., a category with just one month of transactions in the window), `trend = flat`.

### `CategorySeriesDTO`

```dart
class CategorySeriesDTO {
  final String categoryId;
  final String name;
  final String color;           // hex string
  final String icon;
  final String kind;            // 'expense' | 'income'
  final String currencyCode;
  final int totalCents;         // total over the window
  final int avgMonthlyCents;    // totalCents / N (N = window months, fixed)
  final int currentMonthCents;  // amount for the in-progress month
  final Trend trend;
}
```

### `MonthlyPointDTO`

```dart
class MonthlyPointDTO {
  final String yearMonth;   // 'YYYY-MM'
  final int amountCents;
}
```

### `CategoryHistoryDTO`

```dart
class CategoryHistoryDTO {
  final CategorySeriesDTO summary;
  final List<MonthlyPointDTO> points;   // length == N, zero-filled for missing months
  final BudgetStatus? budget;           // null if no budget for this category/currency
}
```

Re-uses the existing `BudgetStatus` DTO from `features/budgets/domain/`.

## Data Layer

### Window Calculation

The `StatisticsViewModel` computes window bounds from the selected `N ∈ {3, 6, 12}`:

- `windowEnd` = first day of next month (exclusive).
- `windowStart` = first day of the month `N-1` months before `now` (inclusive).

This ensures the oldest month in the chart is a complete month. `now` is injected (not `DateTime.now()` in queries) to make the repository testable.

### Netting Semantics

To stay consistent with `BudgetLocalStore.computeSpentCents`, all amount aggregations **net income against expenses**:

```
signedAmount = (type = 'expense') ? amount_cents
             : (type = 'income')  ? -amount_cents
             : 0    -- transfers excluded
```

Effect by category kind:
- Expense category: a refund recorded as `income` on that category reduces the category total (matches Budgets).
- Income category: an `expense` on an income category (rare, e.g. chargeback) reduces the total.

`transfer_in` / `transfer_out` are always excluded.

### MSI (monthly installments) — deferred

Unlike `BudgetLocalStore.computeSpentCents`, Statistics **does not** prorate `installments_count > 1` transactions across months in this iteration. An MSI transaction is attributed entirely to its purchase-month bar. This keeps the SQL simple and matches the typical user mental model of "cuando lo compré". MSI proration is listed as a deferred follow-up.

### Query 1 — Category summary list

`StatisticsLocalStore.getCategorySeries(currencyCode, windowStart, windowEnd, currentYm, windowMid) → List<Map>`:

```sql
SELECT
  c.id AS category_id,
  c.name, c.color, c.icon, c.kind,
  COALESCE(SUM(CASE WHEN t.type = 'expense' THEN  t.amount_cents
                    WHEN t.type = 'income'  THEN -t.amount_cents
                    ELSE 0 END), 0)                              AS total_cents,
  COALESCE(SUM(CASE WHEN strftime('%Y-%m', t.date) = :currentYm THEN
                         CASE WHEN t.type = 'expense' THEN  t.amount_cents
                              WHEN t.type = 'income'  THEN -t.amount_cents
                              ELSE 0 END
                    END), 0)                                     AS current_month_cents,
  COALESCE(SUM(CASE WHEN t.date <  :windowMid THEN
                         CASE WHEN t.type = 'expense' THEN  t.amount_cents
                              WHEN t.type = 'income'  THEN -t.amount_cents
                              ELSE 0 END
                    END), 0)                                     AS first_half_cents,
  COALESCE(SUM(CASE WHEN t.date >= :windowMid THEN
                         CASE WHEN t.type = 'expense' THEN  t.amount_cents
                              WHEN t.type = 'income'  THEN -t.amount_cents
                              ELSE 0 END
                    END), 0)                                     AS second_half_cents
FROM categories c
LEFT JOIN transactions t
  ON t.category_id    = c.id
  AND t.currency_code = :currency
  AND t.date         >= :windowStart
  AND t.date         <  :windowEnd
  AND t.deleted_at   IS NULL
  AND t.type         IN ('expense', 'income')
WHERE c.deleted_at IS NULL
GROUP BY c.id
HAVING ABS(total_cents) > 0
ORDER BY ABS(total_cents) DESC;
```

Notes:
- `HAVING ABS(total_cents) > 0` hides inactive categories while still handling edge cases where income-only refunds net an expense category to zero (those are hidden — acceptable).
- For display in the list:
  - Expense categories: `total_cents` is already positive (expenses add, refunds subtract).
  - Income categories: `total_cents` will be **negative** because income subtracts in the netting. The repository flips the sign to positive for income categories before exposing `totalCents`, `currentMonthCents`, and half-window totals — so the domain DTO always exposes a positive magnitude regardless of `kind`.
- Deleted categories are excluded in this iteration. Surfacing deleted categories with historical transactions (per the "archived-account accessibility" pattern in `architecture/accounts.md`) is deferred.

Repository post-processing:
- Sign flip for `kind == 'income'` as noted above.
- `avgMonthlyCents = totalCents ~/ N` (integer division; display-only rounding).
- `trend`: compare `first_half_cents` vs `second_half_cents` (after sign flip). Threshold is a single named constant `kTrendFlatThresholdRatio = 0.05` exposed in the domain layer to avoid magic-number duplication.

### Query 2 — Monthly series for one category

`StatisticsLocalStore.getMonthlySeries(categoryId, currencyCode, windowStart, windowEnd) → List<Map>`:

```sql
SELECT
  strftime('%Y-%m', t.date) AS ym,
  SUM(t.amount_cents)       AS amount_cents
FROM transactions t
WHERE t.category_id  = :categoryId
  AND t.currency_code = :currency
  AND t.date         >= :windowStart
  AND t.date         <  :windowEnd
  AND t.deleted_at   IS NULL
  AND t.type         IN ('expense', 'income')
GROUP BY ym
ORDER BY ym;
```

`StatisticsRepository.getHistory()` zero-fills missing months in Dart so the bar chart renders an empty bar instead of a gap.

### Query 3 — Transactions for a specific month

**Reuses** `TransactionLocalStore.queryRowsFiltered(TransactionFilter)` (already exists). The repository builds a `TransactionFilter` with:

```dart
TransactionFilter(
  dateFrom: monthStart,         // 'YYYY-MM-DD' — first day of selected month
  dateTo:   monthEnd,            // 'YYYY-MM-DD' — last day of selected month (inclusive, per existing filter semantics using BETWEEN)
  categoryIds: [categoryId],
  currencyCode: currencyCode,
);
```

Note: the filter's `BETWEEN` is inclusive, so `dateTo` must be the last day of the month, not the first day of the next month. Returns a list that the repository maps to `TransactionModel` (reusing the existing mapping helper used by `TransactionRepository`). No new helper method is added to `TransactionLocalStore`.

### Query 4 — Budget for category

Cross-feature read. `BudgetLocalStore` currently exposes `queryRows()` (all budgets) and `computeSpentCents(categoryId, period)`; it does **not** have a per-category lookup.

**Deliverable (Budgets feature):** add `BudgetLocalStore.findByCategory(categoryId)` returning `Map<String,dynamic>?`. One-off read scoped by the existing `UNIQUE(category_id)` invariant. This is a minimal, additive change to Budgets with no migration impact.

`StatisticsRepository` then calls `findByCategory` → `BudgetModel.fromMap` → if present, calls `computeSpentCents(categoryId, period)` and assembles a `BudgetStatus`. The assembled `BudgetStatus` reuses the existing DTO from `features/budgets/domain/`. Currency filtering is applied in Dart: if `budget.currencyCode != currentCurrency`, treat as no-budget (do not show the line on the chart) — this preserves the visual-only currency semantics of Budgets.

Failures in this sub-flow are swallowed and logged; the detail view must still render with `budget = null`.

### Timezone / date format

Verified: `TransactionFilter` documents dates as `YYYY-MM-DD` strings matching the SQLite `date` column format, and `DashboardLocalStore.getMonthlySpendByCategory` already uses `strftime('%Y-%m', t.date)` on this column. Statistics uses the same format. `windowStart`, `windowEnd`, and `:windowMid` are passed as `YYYY-MM-DD` strings so lexicographic comparisons in SQL are correct.

## UI — Statistics Tab (List)

### Layout (top to bottom)

1. **Currency tabs** — existing, shared from `DashboardScreen`.
2. **Content TabBar** — `Resumen` / `Estadísticas`.
3. **Time window chips** — `SegmentedButton` with values `3m / 6m / 12m`. Persists in ViewModel only.
4. **Gastos section** — header + list of `CategoryListRow` for `kind == 'expense'`.
5. **Ingresos section** — header + list of `CategoryListRow` for `kind == 'income'`. Section is omitted if no income categories have data in the window.

### `CategoryListRow`

Single row: category icon (colored), name, current-month amount (right), and a second line with `prom. $X` and a trend chip (`↑` / `↓` / `=`). Tap pushes to detail with `summary` as `extra`.

### States

- **Loading**: 4-5 skeleton shimmer rows.
- **Empty** (no categories with data in window): centered icon + text "Aún no hay suficiente historial" + secondary CTA to `/transactions`.
- **Error**: `ErrorView` with retry button (pattern consistent with existing ViewModels — confirm exact widget at implementation).
- **Refresh**: `RefreshIndicator` re-runs Query 1.

### Reactivity

- Currency change (upstream `DashboardFilterViewModel`): listener on `StatisticsViewModel` re-runs Query 1.
- Window change (`setWindow(months)`): re-runs Query 1.
- On return from detail (e.g., after creating a budget): no auto-refresh needed, since budget state does not affect the list.

## UI — Category History Screen (Detail)

Push-navigated. Receives `categoryId` as path param and `CategorySeriesDTO` as optional `extra`.

### Layout (scroll)

1. **AppBar** — back, category icon + name, overflow menu with "Ir a transacciones filtradas" (navigates to `/transactions` with pre-applied `categoryId` filter, leveraging the existing transaction filter feature).
2. **Time window chips** — same as the list tab.
3. **Stat row** (`stat_delta_row.dart`) — two columns: "Promedio" and "Este mes" with delta %. Delta color:
   - For expense categories: green if negative (spent less), red if positive (spent more).
   - For income categories: inverted.
   - Neutral if `|delta%| < 5%`.
4. **Bar chart** (`CategoryMonthlyBarChart` using `fl_chart`):
   - X labels: month abbreviation in Spanish (`ene`, `feb`, ...). Append year (`dic '25`) when the window crosses years.
   - Y axis: short currency format (`$4.5k`).
   - Tap on bar: selects that month, updates the "Transacciones de [mes]" section below, shows tooltip with full amount and month.
   - Current month bar rendered in primary color; past months in surface tint.
   - Budget line: if `budget != null && budget.period == MONTHLY`, draw a dashed `HorizontalLine` via `fl_chart`'s `extraLinesData` at `limitAmountCents`.
   - Empty data: if all points are zero, show a centered placeholder "Sin datos en esta ventana" instead of the chart.
5. **Budget card** (conditional):
   - `budget != null` (monthly): shows limit, spent, `LinearProgressIndicator`, badge "En curso"/"Excedido", button "Editar presupuesto" → `/accounts/budgets/:id/edit`.
   - `budget != null` (yearly period): shows limit with a note "Presupuesto anual — línea no mostrada". Same edit button.
   - `budget == null`: outline card with text `"Crea un presupuesto basado en tu promedio: $X"`. Button "Crear presupuesto" navigates to `/accounts/budgets/new?categoryId=X&suggested=<avgCents>&currency=<code>`.
6. **Transacciones del mes seleccionado** — default = current month (last bar). Reuses the transactions-list row widget (name to be confirmed at implementation). Shows up to 10; if more, append a "Ver todas" button that navigates to `/transactions` with `categoryId + dateRange` filters.

### Cross-feature deliverables (Budgets)

This spec owns two additive changes in the Budgets feature. They are small and in-scope for the same PR:

1. **`BudgetLocalStore.findByCategory(categoryId)`** — per-category lookup described in *Query 4* above.
2. **`BudgetFormScreen` pre-fill via route params.** Extend the existing route `/accounts/budgets/new` to accept optional `go_router` query params: `categoryId`, `suggested` (int cents), `currency` (code). When present, the form pre-fills the respective fields; when absent, behavior is unchanged. Validation (limit > 0, currency in user's enabled currencies) runs as today; invalid suggested values fall back to empty. This is deliberately routed via query params (not route `extra`) so the deep-link remains shareable and survives process death.

Both changes are strictly additive, have no migration or sync impact, and preserve existing behavior when the new inputs are absent.

### Chart library

New dependency: `fl_chart` (latest stable). Verify exact version and licensing at implementation.

## Error Handling

- **DB errors** in `StatisticsLocalStore`: propagated. `StatisticsRepository` catches and converts to `Result.failure(message)`. ViewModel exposes `error`; UI shows error state with retry.
- **Budget lookup failure**: swallowed + logged. `budget` remains `null`; the "Crear presupuesto" card is shown as a silent fallback.
- **Navigation to budget with query params** when the form does not yet honor them: form ignores unknown params; user fills manually. Non-breaking.
- **Empty data in chart**: placeholder replaces the chart widget to avoid a confusing flat baseline.

## Edge Cases

- **Window crossing year boundary**: `strftime('%Y-%m', ...)` already distinguishes (`'2025-12'` ≠ `'2026-01'`). Chart labels add year suffix when crossing.
- **Category reclassified** (expense ↔ income at some point in history): the series uses the category's current `kind` only. Transactions recorded under the old classification still aggregate under the category. Acceptable for MVP.
- **Deleted categories with historical transactions**: excluded from the list in this iteration. Deferred.
- **Single-month data**: `trend = flat`.
- **Rounding in average**: `avgMonthlyCents = totalCents ~/ N`. Display-only; accepted error. The UI labels this number "prom. últimos Nm" (N adapts to the selected window) so the user knows it's averaged over a fixed N, not only over months with data.
- **Multi-currency user**: follows the `DashboardFilterViewModel.currencyCode` selection; switching currency re-runs queries.
- **Budget in a different currency than the current filter**: Budgets are visual-only per currency. If the current `DashboardFilterViewModel.currencyCode` does not match the budget's `currency_code`, the budget is treated as absent in the chart (no line, no status card, show the "Crear presupuesto" suggestion). This preserves Budgets' existing visual-only semantics.
- **MSI transactions** (`installments_count > 1`): attributed entirely to purchase month; not prorated. Out of scope for MVP; listed as deferred follow-up.
- **Refunds on expense categories**: net negatively against the category total (matches Budgets).

## Testing

### Unit tests (`test/features/statistics/`)

- `statistics_local_store_test.dart`
  - Query 1: correct summation, excludes transfers, respects `deleted_at`, respects window bounds and currency.
  - Query 2: groups by `YYYY-MM` and returns only months with data (zero-fill is the repository's job).
  - Query 3: no new helper is added to `TransactionLocalStore`; integration-level coverage lives in `statistics_repository_test.dart` (composes `TransactionFilter` correctly for the selected month and category).
- `statistics_repository_test.dart`
  - `avgMonthlyCents = total / N` (fixed N, not `months_with_data`).
  - Trend boundaries: `up` / `down` / `flat` around `kTrendFlatThresholdRatio`.
  - Zero-fill of missing months in `MonthlyPointDTO` list.
  - Budget integration with a mocked `BudgetLocalStore`: present, absent, and error cases.
- `statistics_view_model_test.dart`
  - Window change triggers reload.
  - Currency change (upstream) triggers reload.
  - Empty state emitted when no data.
  - Error state emitted on repository failure.

### Widget tests

- `CategoryListRow` renders current-month amount, average line, and trend chip.
- `CategoryMonthlyBarChart` renders N bars and a budget line when `budget != null`.
- `StatisticsTab` smoke tests: with data, empty state, and error state.
- `CategoryHistoryScreen` smoke test with stubbed `CategoryHistoryDTO`.

### Manual verification

- Switch currency in Dashboard and confirm Estadísticas updates accordingly.
- Toggle window (3/6/12) and confirm chart + list refresh.
- Tap a bar and confirm the transactions section updates.
- Tap "Crear presupuesto" and confirm the form pre-fills category + suggested limit + currency.

## Sub-Projects (Deferred Follow-Ups)

Each is a standalone design cycle after this one ships:

1. **Historical metrics series** (net worth, liquidity, buying power) — requires either periodic snapshots or derived-from-transactions recomputation.
2. **Cash flow** (income vs expenses, per account and global) — new queries + new visualization.
3. **Period comparison (A vs B)** — custom range selector + side-by-side view.
4. **Forecasting** — model choice (p75, regression, moving average) + UX decisions.
5. **Surface deleted categories with historical data** — relax `c.deleted_at IS NULL` and mirror the archived-account accessibility pattern from `architecture/accounts.md`.
6. **MSI proration for statistics** — optionally split `installments_count > 1` transactions into per-month installments to match how Budgets already attributes them. Requires deciding whether to expose a toggle (actual date vs prorated).
