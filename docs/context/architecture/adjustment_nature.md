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

## Backward Compatibility

Existing adjustment transactions retain `nature: ''` — only new adjustments get `'adjustment'`. No data migration is required. Old adjustments appear as "Sin definir" in the nature breakdown and "Sin categoría" in the transaction list.
