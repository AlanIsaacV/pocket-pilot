# Cashflow Tab — Income vs. Expense Waterfall

Read-only view accessible from the Estadísticas hub at `/dashboard/statistics/cashflow`. Shows total inflows, total outflows, net for the selected range, and a waterfall chart decomposing those totals by **Category** or by **Nature** (toggle). Transfers count as inflow (`transfer_in`) and outflow (`transfer_out`) in the row's own currency and appear as a synthetic "Transferencias" bucket in the breakdown.

Entry point: `StatisticsTab` (hub) → "Flujo" row. Filter state (range, currency, multi-select accounts) comes from the shared `DashboardFilterViewModel` — see `statistics_tab.md` for the unified filter contract and the nested `ShellRoute` that keeps the scope alive across sub-navigations.

## Feature Structure (`features/cashflow/`)

```
features/cashflow/
├── data/
│   ├── cashflow_local_store.dart    # Three SQL aggregates (totals, per-category, per-nature); all accept accountIds
│   └── cashflow_repository.dart     # Top-N + "Otros" fold; 1:1 nature mapping
├── domain/
│   └── cashflow_snapshot.dart       # CashflowSnapshot + CashflowBreakdownEntry + BreakdownMode
└── ui/
    ├── cashflow_view_model.dart     # ChangeNotifier; listens to DashboardFilterViewModel + local BreakdownMode
    ├── cashflow_tab.dart            # Full-screen view (Stack with DashboardFilterSheet overlay)
    ├── cashflow_route_scope.dart    # Only owns repo + VM; reuses DashboardFilterViewModel from parent shell
    └── widgets/
        ├── cashflow_summary_cards.dart   # Entra / Sale / Neto
        └── cashflow_waterfall_chart.dart # fl_chart BarChart with fromY/toY
```

No remote service, no outbox, no sync handler. Derived from already-synced transactions + categories.

## Data Flow

```
CashflowLocalStore (SQL, accepts accountIds)
  → CashflowRepository (top-N + "Otros" fold, nature mapping)
    → CashflowViewModel (listens to DashboardFilterViewModel: range + currency + accountIds; local BreakdownMode)
      → CashflowTab (cards + toggle + waterfall + breakdown list + sheet overlay)
```

`CashflowViewModel.refresh()` resolves the filter via `_filterVM.resolvedDateRange` and calls `CashflowRepository.getSnapshot(from, to, accountIds)`. It listens to the filter VM (any change → refresh) and to a local `BreakdownMode` (toggle — no refresh, the snapshot carries both lists). `loadOnAppear` is called by the route scope. `isLoading` is only set when `snapshot == null` so chip/toggle interactions don't flash the spinner.

## SQL Contract

All three queries share:
- `currency_code = :currencyCode`.
- `t.date >= :windowStart AND t.date < :windowEnd` — `windowStart = from`, `windowEnd = to + 1 day` (from `StatisticsWindow.fromRange`), so rows dated exactly on `to` are included.
- `deleted_at IS NULL` on both `transactions` and `categories` (where joined).
- Optional `AND t.account_id IN (?, ?, ?)` appended dynamically when `accountIds` is non-empty.

`amount_cents` in `transactions` stores the **absolute magnitude** (positive); sign is inferred from `type`. SUMs are always positive.

### `getTotals` — grand totals per raw type

Widens `type IN ('expense', 'income', 'transfer_in', 'transfer_out')` and returns a map with those four keys (missing keys default to 0). The repository then combines `income + transfer_in → totalIn` and `expense + transfer_out → totalOut`. Same-currency transfers cancel, cross-currency transfers show up in each currency's view, and fees/spread land in `net` as a real delta.

### `getCategoryTotals`

Keeps `type IN ('expense', 'income')`. Transfers have no category and are surfaced as a synthetic entry by the repository. One row per category with activity; `kind` column aliases `categories.type`. Ordered by `total_cents DESC`.

### `getNatureTotals`

Keeps `type IN ('expense', 'income')`. Grouped by `(nature, type)`. Skips rows where `nature` is NULL/empty — those still contribute to grand totals via `getTotals`.

## Repository Logic

### Top-N + "Otros" fold per kind (category mode only)

`CashflowRepository.defaultTopN = 6`. Fold runs **independently per kind**: top N income, rest → `Otros (income)`; same for expense. Nature mode has no fold.

### Synthetic "Transferencias" entry

When `transfer_in > 0` or `transfer_out > 0`, the repository appends a synthetic `CashflowBreakdownEntry` labeled `"Transferencias"` (with `isTransfer: true`) to both `byCategory` and `byNature`, one per non-zero kind. Preserves the invariant `sum(byCategory per kind) == totalInCents / totalOutCents`.

### Sign and display

`CashflowBreakdownEntry.amountCents` is always positive. `CashflowSnapshot.netCents = totalInCents - totalOutCents` can be negative. UI components append signs based on `kind`. `CashflowSnapshot.windowMonths` is derived from `StatisticsWindow.fromRange(from, to).months` (kept for display compatibility).

## UI

Layout (vertical scroll, `Scaffold` with AppBar "Flujo", body wrapped in `Stack` with `DashboardFilterSheet` overlay, `padding.bottom: 160`):
1. `CashflowSummaryCards` — three equal-flex cards: Entra (+), Sale (−), Neto (color by sign).
2. `SegmentedButton<BreakdownMode>` — Categoría ↔ Naturaleza.
3. `CashflowWaterfallChart` — fl_chart `BarChart` with `BarChartRodData.fromY`/`toY`:
   - Income entries step **up** from 0 to totalIn (primary color).
   - Expense entries step **down** from totalIn to net (error color).
   - Final "Neto" bar from 0 to net (primary if ≥0, error if negative).
   - X-axis labels truncated to 8 chars with ellipsis.
   - Tooltip shows full label + signed amount.
4. Breakdown list — income section then expense section, rows showing color dot, label, % of kind total, signed magnitude.

States:
- Null snapshot (no currency picked) → "Selecciona una moneda para ver el flujo".
- `snapshot.isEmpty` (range with zero inflows AND zero outflows) → `_EmptyPeriod` placeholder inside the scroll (cards + chart suppressed; sheet still available).
- Error → `Reintentar` button.

## Routing and Scoping

| Aspect | Value |
|---|---|
| Route | `/dashboard/statistics/cashflow` |
| Scope | `CashflowRouteScope` provides only `CashflowRepository` + `CashflowViewModel`. `DashboardFilterViewModel` is inherited via `context.read` from the parent `DashboardRouteScope` mounted in the nested `ShellRoute` that wraps the dashboard subtree. |
| Hub wiring | `StatisticsTab` pushes `/dashboard/statistics/cashflow` with no query params; filter state persists via shared provider. |

No more `?window=` / `?currency=` query params — shared scope replaces the old threading pattern.

## Testing

- `test/cashflow_repository_test.dart` — totals passthrough, empty snapshot, top-N fold, separate income/expense buckets, nature 1:1 mapping, `entriesFor` selector, transfer cases (totals include transfers, synthetic "Transferencias" entry per kind, same-currency cancellation, fee/spread net delta, breakdown-sums-equal-totals invariant). Signatures use `from` / `to` strings.
- Window math covered by `statistics_window_math_test.dart`.
- SQL validated manually against real data when smoke-testing the UI; no DB-level test per project convention.

## Deferred Follow-Ups

1. Per-account cashflow view (top-N breakdown by account).
2. Time-series cashflow (line/bar per month) as a second chart inside the same screen.
3. Click-through from a breakdown row to the underlying transactions (use `TransactionLocalStore.queryRowsFiltered` with the relevant filter).
4. ~~Custom windows (beyond 3/6/12m).~~ **Done — the unified filter supports Quick / Period / Custom.**
