# Dashboard Financial Metrics — Data & Business Logic

## Context

The dashboard screen (`ui/screens/dashboard/dashboard_screen.dart`) exists as a placeholder with hardcoded values. This spec defines the data layer (SQLite queries) and business logic (currency conversion + financial formulas) to power the 4 core metrics: Net Worth, Liquid Assets, Safe-to-Spend, and Buying Power.

## Architecture

Follows the project's established pattern: **LocalStore (DAO) + Repository (orchestrator + business logic)**. No separate "Service" class — business logic lives in `DashboardRepository.calculateMetrics()`, consistent with `BudgetRepository.getBudgetStatuses()`.

The dashboard is **read-only** — no writes, no outbox, no remote service, no sync handler.

### File Structure

```
frontend/lib/src/features/dashboard/
├── data/
│   ├── dashboard_local_store.dart    # 3 raw SQL queries
│   └── dashboard_repository.dart     # Orchestrator + currency conversion + formulas
└── domain/
    ├── account_balance_dto.dart
    ├── category_spend_dto.dart
    ├── goal_target_dto.dart
    └── dashboard_metrics.dart
```

## Domain Layer (DTOs)

### AccountBalanceDTO

Fields: `accountId` (String), `accountType` (String), `currencyCode` (String), `balanceCents` (int), `creditLimitCents` (int?).

Factory `fromMap()` with `_asInt()` helper for SQLite numeric type safety (pattern from `GoalModel`).

### CategorySpendDTO

Fields: `categoryId` (String?), `currencyCode` (String), `spentCents` (int).

`categoryId` nullable because transactions can have null category (initial balances).

### GoalTargetDTO

Fields: `currencyCode` (String), `totalTargetCents` (int).

Grouped by currency to support multi-currency goals.

### DashboardMetrics

Fields: `netWorthCents` (int), `liquidAssetsCents` (int), `safeToSpendCents` (int), `buyingPowerCents` (int), `baseCurrency` (String), `missingCurrencies` (Set\<String\>).

- Named constructor `DashboardMetrics.empty({required baseCurrency})` for zero state.
- `missingCurrencies`: currencies encountered without an exchange rate. Allows UI to show a warning.

All DTOs: `const` constructors, `fromMap()` factory, no `toMap()` (read-only).

### Account Type Classification

| Account Type | Net Worth | Liquid Assets | Revolving Credit | Notes |
|---|---|---|---|---|
| `bank` | Yes | Yes | No | Primary liquid asset |
| `cash` | Yes | Yes | No | Primary liquid asset |
| `credit_card` | Yes (negative) | No | Yes (if limit set) | Debt reduces NW, available credit adds to Buying Power |
| `loan` | Yes (negative) | No | No | Long-term debt, no revolving credit |
| `investment` | Yes | No | No | Illiquid asset |
| `crypto` | Yes | No | No | Illiquid asset |
| `other` | Yes | No | No | Uncategorized |
| `contact` | Excluded | Excluded | Excluded | Debt tracking accounts |

Note: If a credit card has a positive balance (overpayment), available credit = limit + positive balance, which exceeds the limit. This is mathematically correct.

## Data Layer

### DashboardLocalStore

Constructor: `DashboardLocalStore({required DatabaseHelper db})`

#### 1. `getBalancesPerAccount() -> Future<List<AccountBalanceDTO>>`

```sql
SELECT
  a.id AS account_id,
  a.type AS account_type,
  a.currency_code,
  a.credit_limit_cents,
  COALESCE(SUM(
    CASE
      WHEN t.type IN ('income', 'transfer_in') THEN t.amount_cents
      WHEN t.type IN ('expense', 'transfer_out') THEN -t.amount_cents
      ELSE 0
    END
  ), 0) AS balance_cents
FROM accounts a
LEFT JOIN transactions t
  ON t.account_id = a.id
  AND t.deleted_at IS NULL
  AND t.status = 'cleared'
WHERE a.deleted_at IS NULL
  AND a.type != 'contact'
GROUP BY a.id, a.currency_code
```

- **LEFT JOIN**: accounts with zero transactions appear with `balance_cents = 0`
- **`a.type != 'contact'`**: contact accounts excluded (debt tracking, not user assets)
- **`t.status = 'cleared'`**: only cleared transactions affect balances
- **`a.currency_code`**: read currency from account (not transaction) for zero-txn accounts

#### 2. `getMonthlySpendByCategory(String startDate, String endDate) -> Future<List<CategorySpendDTO>>`

```sql
SELECT
  t.category_id,
  t.currency_code,
  COALESCE(SUM(
    CASE
      WHEN t.type = 'expense' THEN t.amount_cents
      WHEN t.type = 'income' THEN -t.amount_cents
      ELSE 0
    END
  ), 0) AS spent_cents
FROM transactions t
WHERE t.deleted_at IS NULL
  AND t.status = 'cleared'
  AND t.type IN ('expense', 'income')
  AND t.date >= ?
  AND t.date <= ?
GROUP BY t.category_id, t.currency_code
```

- Transfers excluded (not spending)
- Income = negative spend (refunds)
- Date params as `YYYY-MM-DD` strings (project convention)
- **Not consumed by `calculateMetrics()`** — this query serves a future "spending breakdown" widget on the dashboard, not the 4 core metrics

#### 3. `getTotalTargetInGoals() -> Future<List<GoalTargetDTO>>`

```sql
SELECT
  currency_code,
  COALESCE(SUM(target_amount_cents), 0) AS total_target_cents
FROM goals
WHERE deleted_at IS NULL
GROUP BY currency_code
```

### DashboardRepository

Constructor: `DashboardRepository({required DashboardLocalStore local})`

**Passthrough methods** (for ViewModel to access raw data):
- `getBalancesPerAccount()` -> delegates to local store
- `getMonthlySpendByCategory(startDate, endDate)` -> delegates to local store
- `getTotalTargetInGoals()` -> delegates to local store

**Core method: `calculateMetrics({required String baseCurrency, required Map<String, double> exchangeRates}) -> Future<DashboardMetrics>`**

Logic:
1. Fetch `balances` and `goalTargets` from local store
2. Iterate balances, converting each to `baseCurrency`:
   - **Net Worth** += all converted balances
   - **Liquid Assets** += converted balances where `accountType IN ('bank', 'cash')`
   - **Revolving Credit** += `max(0, convertedLimit + convertedBalance)` for `credit_card` accounts with non-null `creditLimitCents`
3. Convert goal targets to baseCurrency, sum as `totalGoalTargetCents`
4. **Safe-to-Spend** = Liquid Assets - totalGoalTargetCents
5. **Buying Power** = Safe-to-Spend + Revolving Credit

**Currency conversion helper: `_getRate(fromCurrency, toCurrency, rates) -> double`**
- Same currency -> 1.0
- Lookup `rates[fromCurrency]` -> multiplier to convert TO baseCurrency
- Fallback -> 1.0 (unconverted). Add currency to `missingCurrencies` set so UI can warn

## Exchange Rate Contract

`exchangeRates` map: keys = source currency codes, values = multiplier to convert TO `baseCurrency`.

Example (`baseCurrency = 'MXN'`):
```dart
{'USD': 17.5, 'EUR': 19.0}  // MXN key not needed (same-currency = 1.0)
```

Formula: `convertedCents = (originalCents * rate).round()`

## Edge Cases

| Case | Handling |
|---|---|
| Account with no transactions | LEFT JOIN + COALESCE -> balance = 0 |
| Credit card with null credit limit | Skipped for revolving credit, still counts in Net Worth |
| Goals in multiple currencies | Grouped by currency, each converted independently |
| Missing exchange rate | Fallback to 1.0, currency added to `missingCurrencies` set |
| Credit card overpayment (positive balance) | Available credit = limit + positive balance (exceeds limit, correct behavior) |
| No goals exist | totalGoalTargetCents = 0, Safe-to-Spend = Liquid Assets |
| Negative Safe-to-Spend | Allowed (goals > liquidity) |
| Negative Buying Power | Allowed (deeply negative Safe-to-Spend) |

## Verification

1. **SQL correctness**: Run `getBalancesPerAccount()` with test data including accounts with/without transactions, credit cards with debt, and verify LEFT JOIN returns all accounts
2. **Currency conversion**: Test with multi-currency balances and verify `calculateMetrics` applies rates correctly
3. **Credit card math**: Account with `credit_limit_cents = 500000` and `balance_cents = -200000` should yield `available = 300000`
4. **Goals deduction**: Two goals in different currencies should both be converted and subtracted from Liquid Assets
5. **Flutter analyze**: Run `dart analyze` to catch type issues
