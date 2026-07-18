# CSV Import UX Improvements

## Context

The CSV import feature (`/settings/csv-import`) works but has friction points during the entity mapping phase. Users must manually map every tag, navigate away to create accounts/categories, and categories are shown in a flat list without hierarchy. These changes reduce friction by auto-creating tags, adding quick-create shortcuts for accounts and categories, displaying category hierarchy, and supporting two new optional CSV columns.

## Changes Overview

1. **Tags**: Auto-create during import, remove mapping section
2. **Accounts**: Quick-create shortcut in bottom sheet + pre-fill manual form
3. **Categories**: Hierarchical bottom sheet + quick-create shortcut + pre-fill manual form
4. **CSV `nature` column**: Optional column for transaction financial nature
5. **CSV `installments_count` column**: Optional column for MSI
6. **Python scripts**: Update CSV output to include new optional columns

---

## 1. Tags: Auto-Create, Remove Mapping Section

### Current behavior
Tags from CSV are extracted as unique names. Users must map each to an existing tag or create via inline button in a bottom sheet.

### New behavior
- Tags section is **removed** from the mapping screen entirely
- During `importBatch()`, before building the insert batch:
  1. For each tag name in the CSV that didn't auto-match an existing tag, call `TagRepository.createTag(id: uuid, name: csvName)`
  2. Add the new tag's ID to `tagIdMap`
- `allMapped` getter no longer considers `unmappedTagCount`
- The `unmappedTagCount` getter and badge can be removed

**Note:** The ViewModel's existing `_tagRepository` field must be **retained** — only `createTagAndMap()` is removed. The repository is now used inside `importBatch()` instead.

### Files to modify
- `csv_mapping_screen.dart` — remove `_buildTagTile()`, `_showTagPicker()`, tag section from `build()`
- `csv_import_view_model.dart` — move tag auto-creation to `importBatch()` (before `buildInsertBatch()`), remove `createTagAndMap()`, update `allMapped` to exclude tags

---

## 2. Accounts: Quick-Create in Bottom Sheet

### Current behavior
Account bottom sheet shows existing accounts + "Crear nueva cuenta" button that navigates to the full account form screen. On return, refreshes accounts.

### New behavior
The bottom sheet gains a **quick-create action** at the top:

```
┌─────────────────────────────────┐
│  Crear "BBVA TC" como cuenta    │  ← Quick create
│  (tipo: bank, MXN)              │
├─────────────────────────────────┤
│  Existing accounts list...      │
├─────────────────────────────────┤
│  + Crear cuenta manualmente     │  ← Navigate to form with name pre-filled
└─────────────────────────────────┘
```

**Quick create behavior:**
- Creates account with:
  - `name`: the CSV account name being mapped
  - `type`: `"bank"`
  - `currency`: inferred from the CSV rows that reference this account name (most frequent currency, or `"MXN"` as fallback)
- Calls `AccountRepository.createAccount()` from ViewModel
- Maps the new account ID immediately
- Closes bottom sheet

**Manual create behavior:**
- Navigates to `/accounts/new` passing `initialName` as a route extra/query parameter
- The account form screen reads this parameter and pre-fills the name field
- On return, `refreshAccounts()` and auto-match as currently

### ViewModel changes

**New constructor dependency:** Add `AccountRepository` as a parameter. Inject via `csv_import_route_scope.dart`.

**New methods:**
```dart
/// Infer currency from CSV rows that use this account name.
/// Iterates _extractionResult.rows, filters by accountName == csvName
/// (and destinationAccountName == csvName for transfers), groups by
/// currencyCode, returns the most frequent. Falls back to "MXN".
String _inferCurrencyForAccount(String csvName) {
  final rows = _extractionResult!.rows.where(
    (r) => r.accountName == csvName || r.destinationAccountName == csvName,
  );
  if (rows.isEmpty) return 'MXN';
  final counts = <String, int>{};
  for (final r in rows) {
    counts[r.currencyCode] = (counts[r.currencyCode] ?? 0) + 1;
  }
  return counts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
}

Future<void> quickCreateAccountAndMap(String csvName) async {
  final currencyCode = _inferCurrencyForAccount(csvName);
  final id = const Uuid().v4();
  await _accountRepository.createAccount(
    id: id, name: csvName, type: 'bank', currencyCode: currencyCode,
  );
  accountIdMap[csvName] = id;
  await refreshAccounts();
}
```

### Routing for manual create with pre-filled name

The current route for `/accounts/new` uses `state.extra as AccountModel?` (edit mode). To pass `initialName` without conflicting:
- Change `AccountFormScreen` to accept an optional `String? initialName` constructor parameter
- In the route builder, when extra is a `String`, treat it as `initialName`; when it's `AccountModel`, treat it as edit mode (existing behavior)
- Navigation: `context.push('/accounts/new', extra: csvName)` — passes the CSV name as a `String`
- In `AccountFormScreen.initState()`: if `initialName != null`, pre-fill `_nameController.text = initialName`

### Files to modify
- `csv_mapping_screen.dart` — redesign `_showAccountPicker()` with quick-create item + pass `initialName` to manual create route
- `csv_import_view_model.dart` — add `_accountRepository` field, `quickCreateAccountAndMap()`, `_inferCurrencyForAccount()`
- `csv_import_route_scope.dart` — inject `AccountRepository` into ViewModel constructor
- `account_form_screen.dart` — add `initialName` parameter, update `initState` to pre-fill name
- `router.dart` — update `/accounts/new` route builder to handle `String` extra as `initialName`

---

## 3. Categories: Hierarchical Bottom Sheet + Quick-Create

### Current behavior
Category bottom sheet shows a flat list of all categories + "Crear nueva categoría" navigating to form.

### New behavior

**Hierarchical display with collapsible groups:**

```
┌─────────────────────────────────┐
│  Crear "Internet" como categoría│  ← Quick create
│  (expense)                      │
├─────────────────────────────────┤
│  🍊 Alimentación            ▶   │  ← Parent (selectable + expandable)
│     🛒 Despensa                 │  ← Child (selectable)
│     🍽️ Restaurante              │
│  🏠 Hogar                   ▶   │
│     📋 Renta / Hipoteca         │
│     🔧 Mantenimiento            │
│     ⚡ Servicios             ▶   │  ← Nested parent
│        💡 Electricidad           │
│        💧 Agua                   │
│        🔥 Gas                    │
│        🌐 Internet               │
│  ...                            │
├─────────────────────────────────┤
│  + Crear categoría manualmente  │  ← Navigate to form with name pre-filled
└─────────────────────────────────┘
```

**Interaction model:**
- **Tap on category row** → select it (close sheet, map the category)
- **Tap on chevron icon (▶/▼)** → expand/collapse children (for parents with children)
- Parents without children behave like regular items (no chevron)
- All categories (parents and children) are selectable
- Indentation: `paddingLeft = depth * 16.0` (where root = 0)
- Groups start collapsed by default
- **Expand/collapse state** lives in `_CsvMappingScreenState` as `Set<String> _expandedCategoryIds` (purely UI state, not in ViewModel)

**Data preparation:**
- The ViewModel builds a tree structure from the flat category list using `parentId` relationships
- Categories without `parentId` are roots; categories with `parentId` are children

**Quick create behavior:**
- Creates category with:
  - `name`: the CSV category name being mapped
  - `type`: inferred from transaction types using that category. If all rows are EXPENSE → `"expense"`, if any row is INCOME → `"income"`, mixed → `"expense"`
  - `defaultNature`: `""`
  - `color`: a default color (e.g., `"#9E9E9E"` grey)
  - `icon`: a default icon (e.g., `"label"`)
  - `parentId`: `null` (top-level)
- Calls `CategoryRepository.createCategory()` from ViewModel
- Maps immediately, closes sheet

**Manual create behavior:**
- Navigates to category creation screen with `initialName` pre-filled
- On return, `refreshCategories()` and auto-match

### ViewModel changes

**New constructor dependency:** Add `CategoryRepository` as a parameter. Inject via `csv_import_route_scope.dart`.

**New methods:**
```dart
/// Infer category type from transaction types that use this category.
/// If all rows with categoryName == csvName are EXPENSE -> "expense"
/// If any row is INCOME -> "income"
/// Mixed or empty -> "expense" (safe default)
String _inferCategoryType(String csvName) {
  final rows = _extractionResult!.rows.where(
    (r) => r.categoryName == csvName,
  );
  if (rows.isEmpty) return 'expense';
  final hasIncome = rows.any((r) => r.type.toUpperCase() == 'INCOME');
  final hasExpense = rows.any((r) => r.type.toUpperCase() == 'EXPENSE');
  if (hasIncome && !hasExpense) return 'income';
  return 'expense';
}

Future<void> quickCreateCategoryAndMap(String csvName) async {
  final type = _inferCategoryType(csvName);
  final id = const Uuid().v4();
  await _categoryRepository.createCategory(
    id: id, name: csvName, type: type,
    color: '#9E9E9E', icon: 'label', defaultNature: '', parentId: null,
  );
  categoryIdMap[csvName] = id;
  await refreshCategories();
}
```

### Tree building helper
```dart
class CategoryNode {
  final CategoryModel category;
  final List<CategoryNode> children;
  final int depth;
}

List<CategoryNode> buildCategoryTree(List<CategoryModel> categories) {
  final byParent = <String?, List<CategoryModel>>{};
  for (final cat in categories) {
    byParent.putIfAbsent(cat.parentId, () => []).add(cat);
  }

  List<CategoryNode> buildChildren(String? parentId, int depth) {
    return (byParent[parentId] ?? []).map((cat) => CategoryNode(
      category: cat,
      children: buildChildren(cat.id, depth + 1),
      depth: depth,
    )).toList();
  }

  return buildChildren(null, 0);
}
```

### Routing for manual create with pre-filled name

The current route for `/categories/new` uses `state.extra` to pass a parent category. To also pass `initialName`:
- Change the extra to accept a `Map<String, dynamic>` with optional keys: `parent` (CategoryModel?) and `initialName` (String?)
- Navigation: `context.push('/categories/new', extra: {'initialName': csvName})`
- In the category form screen: if `initialName` is present, pre-fill the name field

### Files to modify
- `csv_mapping_screen.dart` — redesign `_showCategoryPicker()` with hierarchical collapsible list + quick-create
- `csv_import_view_model.dart` — add `_categoryRepository` field, `quickCreateCategoryAndMap()`, `_inferCategoryType()`, `buildCategoryTree()`, expose tree data
- `csv_import_route_scope.dart` — inject `CategoryRepository` into ViewModel constructor
- Category form screen — accept `initialName` from route extra, pre-fill name
- `router.dart` — update `/categories/new` route builder to handle Map extra

---

## 4. Optional CSV Column: `nature`

### Change
Support an optional `nature` column in the CSV. Valid values match the `FinancialNature` enum:
- `required`, `obligation`, `lifestyle`, `active`, `passive`, `windfall`
- Empty or missing → `""` (current default)

### CSV format
```csv
date,type,amount,currency,account,destination_account,category,tags,notes,nature
2025-04-07 12:00:00,EXPENSE,200,MXN,BBVA TC,,Internet,,TOTALPLAY,required
```

### Implementation

**Header detection in `parseAndExtract()`:**
1. Validate first 9 columns as before
2. Scan remaining headers for `"nature"` and `"installments_count"` (case-insensitive)
3. Store column indices for optional fields

**Domain model change (`CsvTransactionRow`):**
```dart
final String nature;  // "" if column not present or empty
```

**Validation:** Invalid `nature` values (not in the valid set and not empty) are treated as empty string `""` — no error thrown. This is lenient by design since nature is informational and can be corrected in-app.

**Batch building (`buildInsertBatch()` in `csv_import_service.dart`):**
- **New key** added to the transaction map: `'nature': row.nature` (this key is not currently emitted — the SQLite `DEFAULT ''` was hiding its absence)
- Must be added to both transfer and non-transfer code paths in `buildInsertBatch()`

### Files to modify
- `csv_import_service.dart` — header detection, parsing of optional column, pass to `CsvTransactionRow`, add `'nature'` key to batch maps
- `csv_transaction_row.dart` — add `nature` field

---

## 5. Optional CSV Column: `installments_count`

### Change
Support an optional `installments_count` column in the CSV. Must be a positive integer. Default: `1`.

### CSV format
```csv
date,type,amount,currency,account,destination_account,category,tags,notes,nature,installments_count
2025-04-07 12:00:00,EXPENSE,200,MXN,BBVA TC,,Internet,,TOTALPLAY,required,12
```

### Implementation

Same detection mechanism as `nature` — header-based.

**Domain model change (`CsvTransactionRow`):**
```dart
final int installmentsCount;  // 1 if column not present or empty
```

**Validation:** If `installments_count` is not a positive integer (e.g., `0`, `-3`, `abc`, empty), throw `FormatException` with the row number — consistent with how invalid `amount` values are handled. Empty/missing column defaults to `1`.

**Batch building (`buildInsertBatch()` in `csv_import_service.dart`):**
- Replace hardcoded `installments_count: 1` with `row.installmentsCount`
- Must be updated in both transfer and non-transfer code paths

### Files to modify
- `csv_import_service.dart` — header detection, parsing, validation, use in batch maps
- `csv_transaction_row.dart` — add `installmentsCount` field

---

## 6. Python Scripts Update

Update the PDF-to-CSV scripts to support the new optional columns.

**`scripts/parsers/base.py`**: Add to `Transaction` dataclass:
```python
nature: str = ""              # Default empty
installments_count: int = 1   # Default 1
```

**`scripts/csv_writer.py`**: Add the two new columns to headers and output.

**`scripts/parsers/bbva_tc.py`**: For MSI installments detected in the description (e.g., "AMAZON A MESES A 12 MESES S/I"), extract the installment count. For nature, leave empty (the app can set it later).

---

## Files Summary

| File | Changes |
|------|---------|
| `csv_mapping_screen.dart` | Remove tag section, redesign account/category bottom sheets with hierarchy and quick-create |
| `csv_import_view_model.dart` | New `_accountRepository`/`_categoryRepository` fields, quick-create methods, inference helpers, tree builder, tag auto-create in `importBatch()` |
| `csv_import_service.dart` | Optional column detection, parse `nature` + `installments_count`, add `'nature'` key to batch maps, use `installmentsCount` |
| `csv_transaction_row.dart` | Add `nature` (String), `installmentsCount` (int) fields |
| `csv_import_route_scope.dart` | Inject `AccountRepository` + `CategoryRepository` into ViewModel |
| `account_form_screen.dart` | Accept optional `initialName` parameter, pre-fill name field |
| `router.dart` | Handle `String` extra at `/accounts/new`, handle `Map` extra at `/categories/new` |
| Category form screen | Accept `initialName` from route extra Map, pre-fill name field |
| `scripts/parsers/base.py` | Add `nature`, `installments_count` to Transaction dataclass |
| `scripts/csv_writer.py` | Add new columns to CSV output |
| `scripts/parsers/bbva_tc.py` | Extract installment count from MSI descriptions |

## Verification

1. **Tags**: Import a CSV with new tags → tags auto-created, no mapping section shown
2. **Accounts**: Open account picker → quick-create appears at top, creates bank account with correct name/currency. Manual create pre-fills name.
3. **Categories**: Open category picker → hierarchical view with collapsible groups. Quick-create works. Manual create pre-fills name. Both parents and children are selectable.
4. **Nature column**: Import CSV with and without `nature` column → both work correctly. Transactions have correct nature value.
5. **Installments column**: Import CSV with `installments_count=12` → transaction stored with `installments_count=12`. Without column → defaults to 1.
6. **Backwards compatibility**: Import a CSV with only 9 columns → works exactly as before.
7. **Python scripts**: Run `parse_statement.py` → output CSV includes `nature` and `installments_count` columns.
