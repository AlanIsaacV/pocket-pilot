# Cashflow Tab — Income vs. Expense Waterfall

Read-only view accessible from the Estadísticas hub at `/dashboard/statistics/cashflow`. Shows total inflows, total outflows, net for the current window, and a waterfall chart decomposing those totals by **Category** or by **Nature** (toggle). Transfers count as inflow (`transfer_in`) and outflow (`transfer_out`) in the row's own currency and appear as a synthetic "Transferencias" bucket in the breakdown.

Entry point: `StatisticsTab` (hub) → "Flujo" row. See `statistics_tab.md` for hub navigation and shared filter contract.

## Feature Structure (`features/cashflow/`)

```
features/cashflow/
├── data/
│   ├── cashflow_local_store.dart    # Three SQL aggregates: totals, per-category, per-nature
│   └── cashflow_repository.dart     # Orchestrator: top-N + "Otros" fold; maps nature rows 1:1
├── domain/
│   └── cashflow_snapshot.dart       # CashflowSnapshot + CashflowBreakdownEntry + BreakdownMode
└── ui/
    ├── cashflow_view_model.dart     # ChangeNotifier; reactive to Dashboard + Stats filters
    ├── cashflow_tab.dart            # Full-screen view
    ├── cashflow_route_scope.dart    # Providers for the /statistics/cashflow route
    └── widgets/
        ├── cashflow_summary_cards.dart   # Entra / Sale / Neto
        └── cashflow_waterfall_chart.dart # fl_chart BarChart with fromY/toY
```

No remote service, no outbox, no sync handler. Derived from already-synced transactions + categories.

## Data Flow

```
CashflowLocalStore (SQL)
  → CashflowRepository (top-N + "Otros" fold, nature mapping)
    → CashflowViewModel (listens to DashboardFilterViewModel + StatisticsFilterViewModel + local BreakdownMode)
      → CashflowTab (cards + toggle + waterfall + breakdown list)
```

## SQL Contract

All three queries share:
- `currency_code = :currencyCode`
- `date BETWEEN :windowStart AND :windowEnd` (same `StatisticsWindow.fromNow` math used by Statistics).
- `deleted_at IS NULL` on both `transactions` and `categories` (where joined).

`amount_cents` in `transactions` stores the **absolute magnitude** (positive); the sign is inferred from `type`. SUMs are therefore always positive.

### `getTotals` — grand totals per raw type
Widens `type IN ('expense', 'income', 'transfer_in', 'transfer_out')` and returns a map with those four keys (missing keys default to 0). The repository then combines `income + transfer_in → totalIn` and `expense + transfer_out → totalOut`. This makes per-currency cashflow faithful to what hit the balance: same-currency transfers cancel, cross-currency transfers show up in each currency's view, and fees/spread land in `net` as a real delta.

### `getCategoryTotals`
Keeps `type IN ('expense', 'income')` — transfers have no category and are surfaced as a synthetic entry by the repository (see below). One row per category with activity. `kind` column aliases `categories.type`. Ordered by `total_cents DESC`.

### `getNatureTotals`
Keeps `type IN ('expense', 'income')`. Grouped by `(nature, type)`. Skips rows where `nature` is NULL/empty (legacy data without classification) so the chart isn't polluted with an "Sin definir" wedge — those rows **still contribute to grand totals** via `getTotals`.

## Repository Logic

### Top-N + "Otros" fold per kind (category mode only)

`CashflowRepository.defaultTopN = 6`. The fold runs **independently per kind**:
- Take the top N income entries; the rest fold into a single `Otros (income)` entry.
- Same for expense.

"Otros" is only appended if the tail is non-empty. Nature mode has no fold — the 7 financial natures are already few enough.

### Synthetic "Transferencias" entry

When `transfer_in > 0` or `transfer_out > 0` for the current currency/window, the repository appends a synthetic `CashflowBreakdownEntry` labeled `"Transferencias"` to both `byCategory` and `byNature`, one per non-zero kind. The entry carries `isTransfer: true` so the UI can differentiate it visually if needed. This preserves the invariant that `sum(byCategory per kind) == totalInCents / totalOutCents`, avoiding drift between cards and the breakdown list.

### Sign and display

`CashflowBreakdownEntry.amountCents` is always positive (magnitude). `CashflowSnapshot.netCents = totalInCents - totalOutCents` can be negative. UI components append signs based on `kind`.

### Reactivity

`CashflowViewModel` listens to:
- `DashboardFilterViewModel` — refresh on `currencyCode` change.
- `StatisticsFilterViewModel` — refresh on `window` change.
- Local `_mode: BreakdownMode.category | .nature` — no refresh (the snapshot already carries both lists; the UI just swaps the source).

`loadOnAppear` is called by the route scope. A simple loading flag is set only when `snapshot == null` so chip/toggle interactions don't flash the spinner.

## UI

Layout (vertical scroll, scaffold with AppBar "Flujo"):
1. Centered `TimeWindowChips` (bound to `StatisticsFilterViewModel`).
2. `CashflowSummaryCards` — three equal-flex cards: Entra (+), Sale (−), Neto (color by sign).
3. `SegmentedButton<BreakdownMode>` — Categoría ↔ Naturaleza.
4. `CashflowWaterfallChart` — fl_chart `BarChart` with `BarChartRodData.fromY`/`toY`:
   - Income entries step **up** from 0 to totalIn (primary color).
   - Expense entries step **down** from totalIn to net (error color).
   - Final "Neto" bar from 0 to net (primary if ≥0, error if negative).
   - X-axis labels truncated to 8 chars with ellipsis.
   - Tooltip shows full label + signed amount.
5. Breakdown list under the chart — income section then expense section, rows showing color dot, label, % of kind total, signed magnitude.

States:
- Null snapshot (no currency picked) → "Selecciona una moneda para ver el flujo".
- `snapshot.isEmpty` (period with zero inflows AND zero outflows) → `_EmptyPeriod` placeholder inside the scroll (cards + chips still visible).
- Error → Reintentar button.

## Routing and Scoping

| Aspect | Value |
|---|---|
| Route | `/dashboard/statistics/cashflow?window=6&currency=MXN` |
| Scope | `CashflowRouteScope` provides fresh `DashboardFilterViewModel` (seeded from `?currency=`), `StatisticsFilterViewModel` (seeded from `?window=`), `CashflowRepository`, `CashflowViewModel`. |
| Hub wiring | `StatisticsTab._open` reads the hub's current window + currency and threads them as query params on `context.push`. |

Seeding currency and window via query params matches the pre-existing `/dashboard/statistics/category/:categoryId?currency=MXN` pattern and avoids elevating provider scope to `ShellRoute`.

## Testing

- `test/cashflow_repository_test.dart` — covers totals passthrough, empty snapshot, top-N fold, separate income/expense buckets, nature 1:1 mapping, `entriesFor` selector, plus transfer cases: totals include transfers, synthetic "Transferencias" entry per kind, same-currency cancellation, fee/spread net delta, and breakdown-sums-equal-totals invariant.
- Window math and sign conventions covered by the Statistics test suite (`statistics_window_math_test.dart`, `statistics_repository_test.dart`).
- SQL is validated manually against real data when smoke-testing the UI; no DB-level test per project convention.

## Deferred Follow-Ups

1. Per-account cashflow.
2. Time-series cashflow (line/bar per month) as a second chart inside the same screen.
3. Click-through from a breakdown row to the underlying transactions (use `TransactionLocalStore.queryRowsFiltered` with the relevant filter).
4. Custom windows (beyond 3/6/12m) once the shared filter is upgraded.
