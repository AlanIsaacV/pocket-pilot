# Balance Adjustments & Nature Classification

## Problem

Both initial balance and balance adjustment transactions were created with `categoryId: null` and `nature: ''`, making them indistinguishable in analytics and the transaction list (both showed as "Sin categoría").

## Solution

Balance adjustments now use `nature: 'adjustment'` while initial balances remain `nature: ''`. Both keep `categoryId: null`.

| Aspect | Initial Balance | Balance Adjustment |
|--------|----------------|-------------------|
| `categoryId` | `null` | `null` |
| `nature` | `''` (empty) | `'adjustment'` |
| `description` | `'Monto inicial'` | `'Ajuste manual de saldo'` |
| Created by | `AccountsViewModel.createAccount()` | `AccountAdjustmentService.adjustAccountBalance()` |
| Multiple per account | No (one per type) | Yes |

## Full-Stack Changes

### Proto
`FinancialNature` enum in `common.proto`:
- `NATURE_ADJUSTMENT = 7`

### Backend
- **Migration** `002_add_adjustment_nature.sql`: `ALTER TYPE nature_type ADD VALUE 'adjustment'`
- **Go handlers** (transaction, category, transactiontemplate): `financialNatureToString` and `stringToFinancialNature` include `adjustment` ↔ `NATURE_ADJUSTMENT`

### Frontend
- **Dart model converters** (TransactionModel, CategoryModel, TransactionTemplateModel): `_financialNatureToString` and `stringToFinancialNature` include `'adjustment'` ↔ `NATURE_ADJUSTMENT`
- **AccountAdjustmentService**: `createTransaction()` call includes `nature: 'adjustment'`

## UI Treatment

### Transaction List (`_TransactionTile`)
Adjustments are detected by `nature == 'adjustment' && categoryId == null`:
- **Color**: `cs.onSurfaceVariant` (grey, same as `transfer_out`)
- **Icon background**: `cs.secondary` at 10% opacity (same as transfers)
- **Icon**: `Icons.sync_alt_rounded`
- **Label**: "Ajuste de saldo" (instead of "Sin categoría")

### Dashboard Nature Section
Appears under "Gastos por naturaleza" with label "Ajuste" and `catSapphire` color.

## Shared Utility

`core/constants/nature_labels.dart` exports `natureDisplayLabel(String nature)`:
```dart
'required'   → 'Necesario'
'obligation' → 'Obligacion'
'lifestyle'  → 'Estilo de vida'
'active'     → 'Activo'
'passive'    → 'Pasivo'
'windfall'   → 'Extraordinario'
'adjustment' → 'Ajuste'
''           → 'Sin definir'
```

Used by: `transaction_form_screen.dart`, `transaction_template_form_screen.dart`, `dashboard_screen.dart` (`_NatureSpendBreakdown`).

## Navigation & Editing

### Transaction Tap Routing (`_handleTransactionTap`)

Adjustments must open in the **transaction editor**, never in the account editor. The routing logic checks `nature == 'adjustment'` *before* the initial-balance heuristic to short-circuit the entire flow:

```
tap → isTransfer? → transfer editor
    → nature == 'adjustment'? → transaction editor  ← guard
    → isInitialBalance? → account editor
    → otherwise → transaction editor
```

### Initial-Balance Detection (`isInitialBalanceTransaction` / `queryInitialBalanceRow`)

Both initial balances and adjustments share `categoryId = null` + `linkedTransactionId = null` + potentially the same `type`. Without filtering, the `queryInitialBalanceRow` SQL (which returns the oldest matching row) can return an adjustment instead of the real initial balance.

**Guards in place (three layers):**
1. `_handleTransactionTap`: skips the initial-balance check entirely when `nature == 'adjustment'`
2. `isInitialBalanceTransaction` (view model): early-returns `false` when `nature == 'adjustment'`
3. `queryInitialBalanceRow` (SQL): `COALESCE(nature, '') != 'adjustment'` excludes adjustments from the candidate set

### Transaction Form (`TransactionFormScreen`)

Adjustments and initial balances have `categoryId = null`. The form allows saving without a category via `_isCategoryOptional`:
- `nature == 'adjustment'` → true
- Edit mode with original `categoryId == null` → true (covers initial balances)

When `_isCategoryOptional` is true, the category picker section is hidden.

## CreditCardOracle Integration

The oracle's `_isPayment()` method excludes income adjustments (`nature == 'adjustment'`). Positive income adjustments represent prior-period balance corrections, not actual payments for the current cycle. Expense adjustments are still counted as charges (they represent unregistered purchases). This requires the `nature` field on `CreditCardMovementDTO`.

## Backward Compatibility

Existing adjustment transactions retain `nature: ''` — only new adjustments get `'adjustment'`. No data migration is required. Old adjustments appear as "Sin definir" in the nature breakdown and "Sin categoría" in the transaction list.
