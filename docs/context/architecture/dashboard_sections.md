# Dashboard Sections

## Screen Layout (top to bottom)

1. **Currency tabs** — Only shown when multiple currencies exist. `DashboardFilterViewModel.setCurrencyCode()` filters all sections.
2. **Net Worth card** — `DashboardMetrics.netWorthCents` (sum of all accounts).
3. **Metrics grid** — Three cards:
   - Liquidez real: `liquidAssetsCents` (bank + cash only)
   - Liquidez libre: `safeToSpendCents` (liquid - goals - card payments)
   - Poder de compra: `buyingPowerCents` (safe-to-spend + available revolving credit)
4. **Tarjetas de credito** — Per-card estimated monthly payment. Only shown when credit cards exist.
5. **Cuentas** — All accounts with balance. Tappable → navigates to `/accounts/:accountId/edit`.
6. **Gasto del mes** — Spend grouped by category. Excludes `categoryId == null` transactions.
7. **Gastos por naturaleza** — Spend grouped by `transactions.nature` field.
8. **Gastos por etiqueta** — Spend grouped by individual tag (flattened via `json_each`).

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
