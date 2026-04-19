# Statistics Tab — Hub for Historical Analytics

The **Estadísticas** tab is a **hub** (index) for read-only analytical views. Each entry links to a dedicated full-screen visualization. Filters (temporal range, currency, multi-select accounts) are owned by a single `DashboardFilterViewModel` shared with the Dashboard tab and every Statistics sub-route via a nested `ShellRoute`. No per-feature filter VM anymore.

Current views:
- **Categorías** (`/dashboard/statistics/categories`) — per-category spending/income aggregates. Drill into a category for a monthly bar chart + budget CTA.
- **Flujo** (`/dashboard/statistics/cashflow`) — cashflow in/out/net for the range with waterfall chart; toggle between Categoría and Naturaleza breakdowns. See `docs/context/architecture/cashflow_tab.md`.

Original Categorías spec: `docs/superpowers/specs/2026-04-17-statistics-tab-design.md`.

## Integration Point

`DashboardScreen` hosts a `TabBar` with two tabs:
- **Resumen** → `DashboardSummaryTab`.
- **Estadísticas** → `StatisticsTab` (the hub).

The persistent filter UI (`DashboardFilterSheet`, a `DraggableScrollableSheet`) is mounted as a `Stack` overlay inside each tab body **and** each sub-screen, so the sheet is always available at the bottom of the screen regardless of where the user is inside the dashboard subtree. AppBar only keeps the `NotificationBell` (the old `tune_outlined` filter button was removed).

## Routing and Scoping

The dashboard subtree is wrapped in a nested `ShellRoute` so `DashboardRouteScope` mounts once and stays alive across sub-navigations:

```
ShellRoute (HomeScreen shell — NavigationBar)
  └─ ShellRoute builder: DashboardRouteScope
       ├─ /dashboard                                    → DashboardScreen
       ├─ /dashboard/statistics/categories              → StatisticsCategoriesRouteScope + CategoriesTab
       ├─ /dashboard/statistics/cashflow                → CashflowRouteScope + CashflowTab
       └─ /dashboard/statistics/category/:categoryId    → CategoryHistoryScreen (no local scope)
```

`DashboardRouteScope` provides:
- `DashboardFilterViewModel` — the single source of truth for range/currency/accounts.
- `StatisticsRepository` + `StatisticsViewModel` (the hub doesn't use them, but sub-scopes reuse the repo).
- `DashboardRepository` + `DashboardViewModel`.

The test `router_single_root_shell_test` still passes because only the outermost `ShellRoute` is counted at `router.configuration.routes`.

### Sub-route scopes (simplified)

`StatisticsCategoriesRouteScope` and `CashflowRouteScope` **no longer create their own `DashboardFilterViewModel`** — they read it via `context.read<DashboardFilterViewModel>()` from the parent shell scope. Each sub-scope only owns the feature-local repo + VM (`StatisticsViewModel` / `CashflowViewModel`). No more `?window=` / `?currency=` query-param threading — state persists via shared provider.

## Unified Filter

| Field | Type | Notes |
|---|---|---|
| `activePageIndex` | `int` | 0=Quick, 1=Period, 2=Custom |
| `quickSelection` | `QuickRange { d7, d30, m6, y1 }` | default `m6` |
| `periodGranularity` | `PeriodGranularity { week, month, year }` | default `month` |
| `periodOffset` | `int` | navigation offset (←/→) |
| `customFrom`, `customTo` | `DateTime` | custom range bounds |
| `currencyCode` | `String?` | shared with Dashboard |
| `accountIds` | `Set<String>` | multi-select |

Derived: `resolvedDateRange: (String, String)` returns `(dateFrom, dateTo)` as YYYY-MM-DD. `dateFrom` / `dateTo` are shortcut getters.

## UI — Filter Sheet

`DashboardFilterSheet` is a `DraggableScrollableSheet` (collapsed 0.12, expanded 0.55, snapped). Contents from top to bottom:
1. Drag handle.
2. `TemporalPageView` — a 3-page `PageView` with dot indicator: **Quick** (7D/30D/6M/1Y chips) / **Period** (← [Semana|Mes|Año] → with offset navigation) / **Custom** (date range picker). Lives at `features/dashboard/ui/widgets/temporal_page_view.dart` (intentional duplicate of the transactions version — Transactions and Dashboard filters are kept independent by design).
3. `_ScopeFilters` — header + `Limpiar` when `hasFilters`, `ChoiceChip` row for currency (if >1), `FilterChip` row for accounts (multi-select).

Account + currency data is loaded **directly from `AccountLocalStore.getAccounts()`** (excluding `type=='contact'`) on `initState`, not from `DashboardViewModel.accountBalances`. This is deliberate: the balances list is itself re-filtered when `accountIds` changes, which would make other accounts "disappear" after selecting one, breaking multi-select.

Each screen in the dashboard subtree wraps its body in `Stack(children: [ <body>, DashboardFilterSheet() ])` and adds `padding.bottom: 160` to the scrollable so the collapsed sheet never covers content.

`_ScopeFilters` gracefully tolerates a missing `DashboardViewModel` (catches `ProviderNotFoundException`) so the sheet can be mounted in widget tests without the full dashboard scope.

## Filter State Sharing (one VM, many screens)

| Screen | How it reads filter | How it reacts |
|---|---|---|
| `DashboardSummaryTab` | Consumer of `DashboardViewModel`, which subscribes to filter and re-queries. | Auto refresh. |
| `StatisticsTab` (hub) | Just renders entries. | — |
| `CategoriesTab` | `context.watch<StatisticsViewModel>()`. VM subscribes to filter. | Auto refresh. |
| `CashflowTab` | `context.watch<CashflowViewModel>()`. VM subscribes to filter. | Auto refresh. |
| `CategoryHistoryScreen` | StatefulWidget keeps a listener on `DashboardFilterViewModel`; compares `(from, to, currency, accountIds)` tuple and calls `_load()` when it changes. | Manual, because it's not backed by a shared VM. |

## Feature Structure (`features/statistics/`)

```
features/statistics/
├── data/
│   ├── statistics_local_store.dart     # Raw SQL aggregates; accepts accountIds filter
│   └── statistics_repository.dart      # Sign-flip + trend + zero-fill + budget
├── domain/
│   ├── trend.dart                      # enum Trend + kTrendFlatThresholdRatio (0.05) + computeTrend
│   ├── window_math.dart                # StatisticsWindow.fromRange (range-based)
│   ├── category_series_dto.dart
│   ├── monthly_point_dto.dart
│   └── category_history_dto.dart
└── ui/
    ├── statistics_view_model.dart      # ChangeNotifier, listens to filter (range + accountIds + currency)
    ├── statistics_tab.dart             # The HUB (simple list of navigation entries + sheet overlay)
    ├── categories_tab.dart             # Full-screen Gastos+Ingresos, sheet overlay
    ├── categories_route_scope.dart     # StatisticsCategoriesRouteScope (only repo + VM, no filter VM)
    ├── category_history_screen.dart    # Detail screen with its own filter listener
    └── widgets/
        ├── category_list_row.dart
        ├── stat_delta_row.dart
        └── category_monthly_bar_chart.dart  # fl_chart BarChart
```

**Removed files** (as of 2026-04-19): `statistics_filter_view_model.dart`, `widgets/time_window_chips.dart`.

## Data Flow

```
StatisticsLocalStore (SQL, accepts accountIds)
  → StatisticsRepository (sign-flip, trend, avg, zero-fill, budget lookup)
    → StatisticsViewModel (listens to DashboardFilterViewModel, resolves range)
      → CategoriesTab / CategoryHistoryScreen
```

## Netting Semantics

Unchanged — mirrors `BudgetLocalStore.computeSpentCents`: expenses add, income subtracts, transfers excluded. See diagram in prior revisions of this doc.

**MSI proration NOT applied** (unlike Budgets): a transaction with `installments_count > 1` is attributed entirely to its purchase-month bar. Tracked as deferred follow-up.

## Window Math — `StatisticsWindow.fromRange`

Pure helper, replaces the old `fromNow`. Called with two YYYY-MM-DD strings produced by `DashboardFilterViewModel.resolvedDateRange`:

- `windowStart` = `from` (inclusive lower bound).
- `windowEnd` = `to + 1 day` (exclusive upper bound, so `t.date < windowEnd` includes rows dated exactly on `to`).
- `monthsInWindow` = every contiguous `'YYYY-MM'` from `from.month` to `to.month`.
- `months` = `monthsInWindow.length` (used for `avg = total / months`).
- `currentYm` = `'YYYY-MM'` of `to` (highlights the "current" month — for user-selected periods this is the last month in the range).
- `windowMid` = midpoint date (`from + (to-from)/2`), day-accurate, used for future trend-split SQL aggregates (currently vestigial after trend semantics switched to current-vs-avg).

### Behavior per filter mode

| Mode | User selection | Resolved `(from, to)` | `months` |
|---|---|---|---|
| Quick 7D/30D/6M/1Y | "last N days" | `now - N days` → `now` | 1 / 1 / ~6 / 12–13 (depending on calendar alignment) |
| Period week/month/year, offset 0 | current period | first/last day of current week/month/year | 1 / 1 / 12 |
| Period month, offset -1 | previous month | first/last day of previous month | 1 |
| Period year, offset 0, year=2024 | "2024" | `2024-01-01` → `2024-12-31` | 12 (avg = `total/12`) |
| Custom | explicit range | user's chosen bounds | count of touched months |

All dates compare lexicographically against the SQLite `date` column — same contract as `TransactionFilter`.

## SQL

### Query 1 — Category summary (`getCategorySeries`)

Embeds four aggregates in one query (total, current month, first half, second half). Accepts optional `accountIds` → `AND t.account_id IN (?, ?, ?)` appended dynamically. `LEFT JOIN transactions` so categories with no activity are still considered, `HAVING ABS(total_cents) > 0` filters them out. `ORDER BY ABS(total_cents) DESC`.

Column alias `c.type AS kind` maps the SQLite column to the semantic domain field (avoids collision with `transactions.type` / `accounts.type`).

### Query 2 — Monthly series (`getMonthlySeries`)

Grouped by `strftime('%Y-%m', t.date)`. Returns only months with activity; the repository zero-fills the rest using `StatisticsWindow.monthsInWindow` so bars render as empty, not missing. Also accepts optional `accountIds`.

### Query 3 — Transactions for a selected month

No new helper — reuses `TransactionLocalStore.queryRowsFiltered(TransactionFilter)` composed with `categoryIds`, `currencyCode`, and a `[monthStart, monthEnd]` range.

### Query 4 — Budget for category

Cross-feature read via `BudgetLocalStore.findByCategory(categoryId)`. Currency mismatch → `null` (preserves Budgets' visual-only currency semantics). Lookup failures swallowed and logged.

## Trend Semantics

`computeTrend({currentCents, avgCents})`:
- `flat` if `avgCents == 0` OR rounded pct delta below `kTrendFlatThresholdRatio = 0.05`.
- `up` (current > avg) or `down` otherwise.

Matches `StatDeltaRow._deltaColor` exactly, so the list-row arrow and the detail `±N%` badge never disagree. Delta coloring flips by `kind`: expense → up=worse (red), income → up=better (primary).

## UI — Statistics Hub

Vertical list of `_HubEntry` cards (Categorías, Flujo, "Próximamente" hint). No `TimeWindowChips` anymore. Each card: leading tinted icon + title + subtitle + chevron. Tapping calls `context.push('/dashboard/statistics/<view>')` with no query params; the shared filter state persists automatically.

## UI — Categorías Tab (full-screen)

`Scaffold` with AppBar "Categorías", then a `Stack` containing a `CustomScrollView` (Gastos + Ingresos sections of `CategoryListRow`s sorted by `total` desc) overlaid by the `DashboardFilterSheet`. `RefreshIndicator` re-runs Query 1. Loading spinner, "Aún no hay suficiente historial" empty state, `Reintentar` error state — unchanged.

Row (`CategoryListRow`) uses `vm.months` from `StatisticsViewModel` for the `prom. últimos Nm` label (reflects the resolved range's month count, not a hardcoded N).

## UI — Category History Screen (Detail)

Layout:
1. AppBar with category name + "Ver transacciones" action.
2. `StatDeltaRow` — Promedio + Este mes + `±N%` badge.
3. `CategoryMonthlyBarChart` — fl_chart with month labels in Spanish; current-month bar in `cs.primary`, others in `cs.surfaceContainerHigh`; optional monthly budget line via `extraLinesData`.
4. `_BudgetCard` (conditional) — same three states as before (create CTA / monthly progress / yearly placeholder).
5. `DashboardFilterSheet` overlay.

The screen owns a listener on `DashboardFilterViewModel`. It compares `(from, to, currency, accountIds)` and only calls `_load()` when the tuple changes. `currency` resolution order: `widget.initialCurrencyCode ?? widget.initialSummary?.currencyCode ?? filterVM.currencyCode`.

## Cross-Feature Deliverables (Budgets)

Unchanged:
1. **`BudgetLocalStore.findByCategory(categoryId)`** — per-category lookup used by Query 4.
2. **`BudgetFormScreen` accepts `initialCategoryId` / `initialLimitCents` / `initialCurrencyCode`** — `/accounts/budgets/new` route reads them from query params.

## Dependencies

- Reused: `fl_chart`, `BudgetLocalStore`, `TransactionLocalStore.queryRowsFiltered`, `BudgetStatus` DTO, `DashboardFilterViewModel`, `DatabaseHelper`, `AccountLocalStore`.

## Testing

- `test/statistics_window_math_test.dart` — `fromRange` cases: single month, full year, cross-year, day-precision custom range.
- `test/statistics_repository_test.dart` — netting, sign-flip, trend variants, budget currency mismatch, lookup failure. Calls use `from`/`to`.
- `test/statistics_view_model_test.dart` — empty currency, temporal change reload, currency change reload, error surface. `_FakeRepo` counts raw `calls` (not `callsByMonths`).
- `test/statistics_tab_smoke_test.dart` — renders hub entries.
- `test/statistics_category_list_row_test.dart` / `test/statistics_stat_delta_row_test.dart` — widget smoke tests.

SQL remains untested at the DB level per project convention — coverage goes through repository tests with `_FakeLocalStore`.

## Deferred Follow-Ups

1. Historical metrics series (net worth, liquidity, buying power).
2. ~~Cash flow (income vs expenses, per account and global).~~ **Done — see `cashflow_tab.md`.**
3. Arbitrary period comparison (A vs B).
4. Forecasting.
5. Surface deleted categories with historical data.
6. MSI proration for statistics.
7. ~~Custom date ranges for the shared window.~~ **Done — unified filter supports Quick/Period/Custom.**
