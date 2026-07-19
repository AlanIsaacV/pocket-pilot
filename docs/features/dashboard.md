# Dashboard Sections

## Screen Layout (top to bottom)

1. **Net Worth card** — `DashboardMetrics.netWorthCents` (sum of all accounts). Currency selection lives in the unified filter sheet (see below), not in inline tabs.
2. **Metrics grid** — Three cards:
   - Liquidez real: `liquidAssetsCents` (bank + cash only)
   - Liquidez libre: `safeToSpendCents` = `liquid - goalMonthly - cardPayment`. `goalMonthly` is the **monthly required contribution** across all active goals, computed via `GoalMath.totalMonthlyRequiredCents(goals, now)` — **not** the total target. The full target is a long-term savings objective, not a current-month outflow.
   - Poder de compra: `buyingPowerCents` = `liquid + revolving`. Represents gross purchase capacity: cash/bank balances plus remaining credit-card capacity (`creditLimit + balance`, where credit-card balances are negative). **Does not** subtract goals or card payments — those already reduce `safeToSpend` and shouldn't double-count here.
3. **Tarjetas de credito** — Per-card estimated monthly payment. Only shown when credit cards exist.
4. **Cuentas** — All accounts with balance. Tappable → navigates to `/accounts/:accountId/edit`.
5. **Gasto del mes** — Spend grouped by category. Excludes `categoryId == null` transactions.
6. **Gastos por naturaleza** — Spend grouped by `transactions.nature` field.
7. **Gastos por etiqueta** — Spend grouped by individual tag (flattened via `json_each`).

The whole list is wrapped in a `Stack` with `DashboardFilterSheet` overlayed at the bottom (see below). `ListView.padding.bottom = 160` prevents the collapsed sheet from covering the last section.

## Unified Filter Sheet

A persistent `DraggableScrollableSheet` (`DashboardFilterSheet`) lives at the bottom of the Dashboard, the Estadísticas hub, and every Statistics sub-screen. It owns the single source of truth for range / currency / multi-select accounts via `DashboardFilterViewModel`.

- **Temporal picker** (`TemporalPageView`, 3 pages with dot indicator): Quick (7D/30D/6M/1Y) / Period (Semana | Mes | Año with ←/→ navigation) / Custom (range via the shared `pickDate()`).
- **Currency** (`ChoiceChip` row, visible when >1 currency exists).
- **Cuentas** (`FilterChip` row, multi-select) — loaded directly from `AccountLocalStore.getAccounts()` (excluding `type=='contact'`), **not** from `DashboardViewModel.accountBalances`. The balances list is re-filtered when `accountIds` changes, which would make other accounts "disappear" after one is selected. Loading from the store keeps the full list visible so multi-select works.

The AppBar has no filter icon. `DashboardScreen` only shows `NotificationBell` and the `TabBar` (Resumen / Estadísticas). Dashboard and all Statistics sub-routes share the same `DashboardFilterViewModel` via a nested `ShellRoute` — see `statistics_tab.md` for routing details.

The filter covers **both** the summary sections and the statistics queries: date range + account filter + currency propagate through `DashboardRepository` (via `accountIds` + `dateFrom`/`dateTo` args) and `StatisticsRepository`/`CashflowRepository` (via `accountIds` + `from`/`to` args).

## Data Flow

```
DashboardLocalStore (SQL queries)
  → DashboardRepository (delegates + CreditCardOracle for card payments)
    → DashboardViewModel (state + currency-filtered getters)
      → DashboardScreen (widgets)
```

## Key DTOs (all in `features/dashboard/domain/`)

| DTO | Source | Fields |
|-----|--------|--------|
| `DashboardMetrics` | `calculateAllMetrics()` | currencyCode, netWorthCents, liquidAssetsCents, safeToSpendCents, buyingPowerCents |
| `AccountBalanceDTO` | `getBalancesPerAccount()` | accountId, accountName, accountType, currencyCode, balanceCents, creditLimitCents |
| `CreditCardPaymentDTO` | `getCreditCardPayments()` | accountId, accountName, currencyCode, estimatedPaymentCents |
| `CategorySpendDTO` | `getMonthlySpendByCategory()` | categoryId, categoryName, categoryColor, currencyCode, spentCents |
| `NatureSpendDTO` | `getMonthlySpendByNature()` | nature, currencyCode, spentCents |
| `TagSpendDTO` | `getMonthlySpendByTag()` | tagName, currencyCode, spentCents |

## Goals Aggregation for Dashboard

`DashboardLocalStore.getActiveGoals()` returns `List<GoalModel>` (not an aggregate). `DashboardRepository.calculateAllMetrics` groups goals by currency and calls `GoalMath.totalMonthlyRequiredCents(goalsForCurrency, now: now)` per currency. This keeps the monthly-cuota math in one place (`GoalModel.monthlyRequiredCentsAt`) and lets the dashboard reuse it without duplicating ceil-division logic.

## Credit Card Payment Calculation

`CreditCardOracle.estimateNetMonthlyObligation()` returns both `netByCurrency` (used by metrics for safe-to-spend) and `netByAccountId` (used by the credit card section).

### Cycle Mode (statement_day + payment_due_day defined)

The oracle estimates the **currently accumulating** billing cycle — charges since the last statement date through the next statement date.

For `targetMonth = April`, `statementDay = 24`, `paymentDueDay = 14`:
- `closeCurr` = Apr 24 (statement date of target month)
- `closePrev` = Mar 24 (previous statement date)
- **Charge window**: (Mar 24, min(now, Apr 24)] — one-shot charges + MSI installments
- **Payment window**: [Apr 14, min(now, Apr 24)] — only payments after the previous due date count (earlier payments are assumed to cover the prior bill)

Key rules:
- **`chargeCutoff = min(now, closeCurr)`**: mid-cycle projections only count charges up to today
- **`_isCharge(m)`**: `expense` or `transfer_out` (includes expense adjustments)
- **`_isPayment(m)`**: `income` or `transfer_in`, **excluding** `nature == 'adjustment'` (positive adjustments are prior-period corrections, not current payments)
- **MSI**: `_firstCloseOnOrAfter(txDate, statementDay)` determines which statement cycle each installment lands in; `_installmentAmount()` assigns the residual to the first installment

### Fallback Calendar Mode (no statement/payment days)

Uses previous calendar month for charges, current month for payments. Same `_isCharge`/`_isPayment` rules.

### Data Flow

`CreditCardMovementDTO` includes `nature` (from `t.nature` in `getCreditCardMovementsForProjection` SQL) to support the adjustment filtering.

## Tag Query

Uses SQLite `json_each(t.tags)` to flatten the JSON array stored in `transactions.tags`, then groups by individual tag value. Requires SQLite with JSON1 extension (standard on iOS 16+ and Android API 26+).

## Nature Color Palette

Fixed colors per nature value defined in `_NatureSpendBreakdown._natureColors`:
- required → catRed
- obligation → catPeach
- lifestyle → catMauve
- active → catGreen
- passive → catTeal
- windfall → catYellow
- adjustment → catSapphire

## Account Card Navigation

`_AccountCard` uses `InkWell` with `context.push('/accounts/${balance.accountId}/edit')`. Since the dashboard only has `AccountBalanceDTO` (not full `AccountModel`), the route passes no `extra`. `AccountFormScreen` supports a `accountId` parameter for load-by-ID mode, creating a temporary `AccountLocalStore` from `DatabaseHelper` to fetch the account.
