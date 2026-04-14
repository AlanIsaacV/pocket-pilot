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

`CreditCardOracle.estimateNetMonthlyObligation()` returns both `netByCurrency` (used by metrics for safe-to-spend) and `netByAccountId` (used by the credit card section). The oracle estimates charges for the current statement cycle, accounts for installments (MSI), and deducts payments made so far.

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
