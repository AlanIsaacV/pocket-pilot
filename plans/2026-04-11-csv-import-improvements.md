# CSV Import UX Improvements — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reduce friction in the CSV import mapping flow by auto-creating tags, adding quick-create shortcuts for accounts/categories, showing category hierarchy, and supporting two new optional CSV columns (`nature`, `installments_count`).

**Architecture:** Changes touch 4 layers: domain models get new fields, the service gains optional-column detection, the ViewModel gains quick-create methods and tree building, and the UI removes the tag section and redesigns account/category bottom sheets. Python scripts get matching column updates.

**Tech Stack:** Flutter/Dart (frontend), Python 3.12+ with pdfplumber (scripts)

---

## File Map

| File | Action | Responsibility |
|------|--------|----------------|
| `frontend/lib/src/features/csv_import/domain/csv_transaction_row.dart` | Modify | Add `nature`, `installmentsCount` fields |
| `frontend/lib/src/features/csv_import/data/csv_import_service.dart` | Modify | Optional column detection, parse new fields, emit `nature` + `installments_count` in batch |
| `frontend/lib/src/features/csv_import/ui/csv_import_view_model.dart` | Modify | Tag auto-create, quick-create methods, currency/category-type inference, category tree builder |
| `frontend/lib/src/features/csv_import/ui/csv_import_route_scope.dart` | Modify | Inject `AccountRepository` + `CategoryRepository` |
| `frontend/lib/src/features/csv_import/ui/csv_mapping_screen.dart` | Modify | Remove tag section, redesign account/category pickers |
| `frontend/lib/src/features/accounts/ui/account_form_screen.dart` | Modify | Accept `initialName` parameter |
| `frontend/lib/src/features/categories/ui/category_form_screen.dart` | Modify | Accept `initialName` parameter |
| `frontend/lib/src/ui/router.dart` | Modify | Handle new extra types for `/accounts/new` and `/categories/new` |
| `scripts/parsers/base.py` | Modify | Add `nature`, `installments_count` to Transaction |
| `scripts/csv_writer.py` | Modify | Emit new columns |
| `scripts/parsers/bbva_tc.py` | Modify | Extract installment count from MSI descriptions |

---

### Task 1: Add `nature` and `installmentsCount` to `CsvTransactionRow`

**Files:**
- Modify: `frontend/lib/src/features/csv_import/domain/csv_transaction_row.dart`

- [ ] **Step 1: Add the two new fields to CsvTransactionRow**

Replace the entire file content:

```dart
/// Representa una fila parseada del CSV de importación.
///
/// Todos los campos son texto plano (nombres humanos, no UUIDs).
/// La resolución a IDs se hace en una fase posterior con [MappingDictionary].
class CsvTransactionRow {
  final String date;
  final String type;
  final double amount;
  final String currencyCode;
  final String accountName;
  final String? destinationAccountName;
  final String? categoryName;
  final List<String> tagNames;
  final String notes;
  final String nature;
  final int installmentsCount;

  const CsvTransactionRow({
    required this.date,
    required this.type,
    required this.amount,
    required this.currencyCode,
    required this.accountName,
    this.destinationAccountName,
    this.categoryName,
    required this.tagNames,
    required this.notes,
    this.nature = '',
    this.installmentsCount = 1,
  });
}
```

- [ ] **Step 2: Verify no compile errors**

Run: `cd /Volumes/rusty-drive/projects/pocket-pilot/frontend && flutter analyze lib/src/features/csv_import/domain/csv_transaction_row.dart`
Expected: No issues found.

- [ ] **Step 3: Commit**

```bash
git add frontend/lib/src/features/csv_import/domain/csv_transaction_row.dart
git commit -m "feat(csv-import): add nature and installmentsCount fields to CsvTransactionRow"
```

---

### Task 2: Add optional column detection and new fields to `CsvImportService`

**Files:**
- Modify: `frontend/lib/src/features/csv_import/data/csv_import_service.dart`

- [ ] **Step 1: Add valid natures constant after `_validTypes`**

After line 36 (`static const _validTypes = {'EXPENSE', 'INCOME', 'TRANSFER'};`), add:

```dart
static const _validNatures = {
  'required', 'obligation', 'lifestyle', 'active', 'passive', 'windfall',
};
```

- [ ] **Step 2: Update `parseAndExtract()` to detect optional columns and parse new fields**

After the header validation loop (line 68, the closing `}` of the for loop), add optional column detection:

```dart
    // Detect optional columns by name.
    int? natureCol;
    int? installmentsCol;
    for (var i = _expectedHeaders.length; i < headers.length; i++) {
      if (headers[i] == 'nature') natureCol = i;
      if (headers[i] == 'installments_count') installmentsCol = i;
    }
```

Then update the `rows.add(...)` call (currently at lines 130-140) to include the new fields. Replace:

```dart
      rows.add(CsvTransactionRow(
        date: raw[0].toString().trim(),
        type: type,
        amount: amount,
        currencyCode: raw[3].toString().trim(),
        accountName: accountName,
        destinationAccountName: destinationAccountName,
        categoryName: categoryName,
        tagNames: parsedTags,
        notes: raw[8].toString().trim(),
      ));
```

With:

```dart
      // Parse optional nature column.
      var nature = '';
      if (natureCol != null && raw.length > natureCol!) {
        final raw_nature = raw[natureCol!].toString().trim().toLowerCase();
        if (raw_nature.isNotEmpty && _validNatures.contains(raw_nature)) {
          nature = raw_nature;
        }
        // Invalid values silently default to '' (lenient by design).
      }

      // Parse optional installments_count column.
      var installmentsCount = 1;
      if (installmentsCol != null && raw.length > installmentsCol!) {
        final rawInstallments = raw[installmentsCol!].toString().trim();
        if (rawInstallments.isNotEmpty) {
          final parsed = int.tryParse(rawInstallments);
          if (parsed == null || parsed < 1) {
            throw FormatException(
              'Fila $rowNum: installments_count inválido "$rawInstallments". '
              'Debe ser un entero positivo.',
            );
          }
          installmentsCount = parsed;
        }
      }

      rows.add(CsvTransactionRow(
        date: raw[0].toString().trim(),
        type: type,
        amount: amount,
        currencyCode: raw[3].toString().trim(),
        accountName: accountName,
        destinationAccountName: destinationAccountName,
        categoryName: categoryName,
        tagNames: parsedTags,
        notes: raw[8].toString().trim(),
        nature: nature,
        installmentsCount: installmentsCount,
      ));
```

- [ ] **Step 3: Update `buildInsertBatch()` to use the new fields**

In `sharedFields` (transfer path, around line 225), replace:

```dart
          'installments_count': 1,
```

With:

```dart
          'installments_count': row.installmentsCount,
          'nature': row.nature,
```

In the non-transfer `txMap` (around line 264), replace:

```dart
          'installments_count': 1,
```

With:

```dart
          'installments_count': row.installmentsCount,
          'nature': row.nature,
```

- [ ] **Step 4: Verify compile**

Run: `cd /Volumes/rusty-drive/projects/pocket-pilot/frontend && flutter analyze lib/src/features/csv_import/data/csv_import_service.dart`
Expected: No issues found.

- [ ] **Step 5: Commit**

```bash
git add frontend/lib/src/features/csv_import/data/csv_import_service.dart
git commit -m "feat(csv-import): support optional nature and installments_count CSV columns"
```

---

### Task 3: Update ViewModel — tag auto-create, quick-create methods, category tree

**Files:**
- Modify: `frontend/lib/src/features/csv_import/ui/csv_import_view_model.dart`

- [ ] **Step 1: Add new imports and repository fields**

Add imports after the existing imports (after line 21):

```dart
import 'package:pocket_pilot/src/features/accounts/data/account_repository.dart';
import 'package:pocket_pilot/src/features/categories/data/category_repository.dart';
```

Add two new fields to the class (after `final TagRepository _tagRepository;` at line 31):

```dart
  final AccountRepository _accountRepository;
  final CategoryRepository _categoryRepository;
```

Update the constructor (lines 33-45) to accept and assign the new dependencies:

```dart
  CsvImportViewModel({
    required CsvImportService service,
    required CsvImportRepository repository,
    required AccountLocalStore accountStore,
    required CategoryLocalStore categoryStore,
    required TagLocalStore tagStore,
    required TagRepository tagRepository,
    required AccountRepository accountRepository,
    required CategoryRepository categoryRepository,
  })  : _service = service,
        _repository = repository,
        _accountStore = accountStore,
        _categoryStore = categoryStore,
        _tagStore = tagStore,
        _tagRepository = tagRepository,
        _accountRepository = accountRepository,
        _categoryRepository = categoryRepository;
```

- [ ] **Step 2: Update `allMapped` to exclude tags**

Replace the `allMapped` getter (lines 113-116):

```dart
  bool get allMapped =>
      unmappedAccountCount == 0 &&
      unmappedCategoryCount == 0 &&
      unmappedTagCount == 0;
```

With:

```dart
  bool get allMapped =>
      unmappedAccountCount == 0 &&
      unmappedCategoryCount == 0;
```

- [ ] **Step 3: Remove `createTagAndMap()` method**

Delete lines 228-235 (the `createTagAndMap` method). This is replaced by auto-creation in `importBatch()`.

- [ ] **Step 4: Add tag auto-creation to `importBatch()`**

In `importBatch()`, add tag auto-creation before the `MappingDictionary` construction. After `notifyListeners();` on line 256 and before `final mapping = MappingDictionary(...)` on line 259, add:

```dart
      // Auto-create tags that didn't auto-match.
      final result = _extractionResult;
      if (result != null) {
        for (final tagName in result.uniqueTagNames) {
          if (!tagIdMap.containsKey(tagName)) {
            final id = const Uuid().v4();
            await _tagRepository.createTag(id: id, name: tagName);
            tagIdMap[tagName] = id;
          }
        }
      }
```

- [ ] **Step 5: Add quick-create and inference methods**

After the `refreshCategories()` method (line 247), add:

```dart
  // ----------------------------------------------------------
  // Quick-create shortcuts
  // ----------------------------------------------------------

  String _inferCurrencyForAccount(String csvName) {
    final rows = _extractionResult?.rows ?? [];
    final matching = rows.where(
      (r) => r.accountName == csvName || r.destinationAccountName == csvName,
    );
    if (matching.isEmpty) return 'MXN';
    final counts = <String, int>{};
    for (final r in matching) {
      counts[r.currencyCode] = (counts[r.currencyCode] ?? 0) + 1;
    }
    return counts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
  }

  Future<void> quickCreateAccountAndMap(String csvName) async {
    final currencyCode = _inferCurrencyForAccount(csvName);
    final id = const Uuid().v4();
    await _accountRepository.createAccount(
      id: id,
      name: csvName,
      type: 'bank',
      currencyCode: currencyCode,
    );
    accountIdMap[csvName] = id;
    await refreshAccounts();
  }

  String _inferCategoryType(String csvName) {
    final rows = _extractionResult?.rows ?? [];
    final matching = rows.where((r) => r.categoryName == csvName);
    if (matching.isEmpty) return 'expense';
    final hasIncome = matching.any((r) => r.type.toUpperCase() == 'INCOME');
    final hasExpense = matching.any((r) => r.type.toUpperCase() == 'EXPENSE');
    if (hasIncome && !hasExpense) return 'income';
    return 'expense';
  }

  Future<void> quickCreateCategoryAndMap(String csvName) async {
    final type = _inferCategoryType(csvName);
    final id = const Uuid().v4();
    await _categoryRepository.createCategory(
      id: id,
      name: csvName,
      type: type,
      color: '#9E9E9E',
      icon: 'label',
      defaultNature: '',
    );
    categoryIdMap[csvName] = id;
    await refreshCategories();
  }

  // ----------------------------------------------------------
  // Category tree
  // ----------------------------------------------------------

  List<CategoryNode> get categoryTree => _buildCategoryTree(_existingCategories);

  List<CategoryNode> _buildCategoryTree(List<CategoryModel> categories) {
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

- [ ] **Step 6: Add `CategoryNode` class at the bottom of the file**

After the closing `}` of `CsvImportViewModel`, add:

```dart
class CategoryNode {
  final CategoryModel category;
  final List<CategoryNode> children;
  final int depth;

  const CategoryNode({
    required this.category,
    required this.children,
    required this.depth,
  });

  bool get hasChildren => children.isNotEmpty;
}
```

- [ ] **Step 7: Verify compile**

Run: `cd /Volumes/rusty-drive/projects/pocket-pilot/frontend && flutter analyze lib/src/features/csv_import/ui/csv_import_view_model.dart`
Expected: No issues (route scope will show error since it doesn't pass the new params yet — that's Task 4).

- [ ] **Step 8: Commit**

```bash
git add frontend/lib/src/features/csv_import/ui/csv_import_view_model.dart
git commit -m "feat(csv-import): tag auto-create, quick-create methods, category tree builder"
```

---

### Task 4: Inject new repositories in Route Scope

**Files:**
- Modify: `frontend/lib/src/features/csv_import/ui/csv_import_route_scope.dart`

- [ ] **Step 1: Add imports and inject repositories**

Add imports after line 14:

```dart
import 'package:pocket_pilot/src/features/accounts/data/account_repository.dart';
import 'package:pocket_pilot/src/features/categories/data/category_repository.dart';
```

In the `build()` method, after `final tagRepository = ...` (line 32), add:

```dart
        final accountRepository = AccountRepository(local: accountStore, outbox: outbox);
        final categoryRepository = CategoryRepository(local: categoryStore, outbox: outbox);
```

Update the `CsvImportViewModel(...)` constructor call (lines 34-41) to pass the new params:

```dart
        return CsvImportViewModel(
          service: service,
          repository: repository,
          accountStore: accountStore,
          categoryStore: categoryStore,
          tagStore: tagStore,
          tagRepository: tagRepository,
          accountRepository: accountRepository,
          categoryRepository: categoryRepository,
        );
```

- [ ] **Step 2: Verify full compile of the csv_import feature**

Run: `cd /Volumes/rusty-drive/projects/pocket-pilot/frontend && flutter analyze lib/src/features/csv_import/`
Expected: No issues found.

- [ ] **Step 3: Commit**

```bash
git add frontend/lib/src/features/csv_import/ui/csv_import_route_scope.dart
git commit -m "feat(csv-import): inject AccountRepository and CategoryRepository in route scope"
```

---

### Task 5: Update router and form screens for `initialName` pre-fill

**Files:**
- Modify: `frontend/lib/src/ui/router.dart`
- Modify: `frontend/lib/src/features/accounts/ui/account_form_screen.dart`
- Modify: `frontend/lib/src/features/categories/ui/category_form_screen.dart`

- [ ] **Step 1: Update `/accounts/new` route to handle String extra**

In `router.dart`, replace the `/accounts/new` route builder (lines 257-259):

```dart
              GoRoute(
                path: 'new',
                builder: (context, state) =>
                    const AccountsRouteScope(child: AccountFormScreen()),
              ),
```

With:

```dart
              GoRoute(
                path: 'new',
                builder: (context, state) => AccountsRouteScope(
                  child: AccountFormScreen(
                    initialName: state.extra is String ? state.extra as String : null,
                  ),
                ),
              ),
```

- [ ] **Step 2: Update `AccountFormScreen` to accept and use `initialName`**

In `account_form_screen.dart`, add the parameter to the widget (around line 27):

```dart
class AccountFormScreen extends StatefulWidget {
  final AccountModel? account;
  final String? initialName;

  const AccountFormScreen({this.account, this.initialName, super.key});
```

In `_AccountFormScreenState.initState()` (around line 65-70), after the existing `if (account == null)` block, add pre-fill logic. After line 70 (`(_) => _loadCurrencyOptions(),`), add:

```dart
      if (widget.initialName != null) {
        _nameController.text = widget.initialName!;
      }
```

- [ ] **Step 3: Update `/categories/new` route to handle Map extra**

In `router.dart`, replace the `/categories/new` route builder (lines 361-365):

```dart
          GoRoute(
            path: 'new',
            builder: (context, state) => CategoriesRouteScope(
              child: CategoryFormScreen(parent: state.extra as CategoryModel?),
            ),
          ),
```

With:

```dart
          GoRoute(
            path: 'new',
            builder: (context, state) {
              final extra = state.extra;
              CategoryModel? parent;
              String? initialName;
              if (extra is CategoryModel) {
                parent = extra;
              } else if (extra is Map<String, dynamic>) {
                parent = extra['parent'] as CategoryModel?;
                initialName = extra['initialName'] as String?;
              }
              return CategoriesRouteScope(
                child: CategoryFormScreen(
                  parent: parent,
                  initialName: initialName,
                ),
              );
            },
          ),
```

- [ ] **Step 4: Update `CategoryFormScreen` to accept and use `initialName`**

In `category_form_screen.dart`, add the parameter (around line 25):

```dart
class CategoryFormScreen extends StatefulWidget {
  final CategoryModel? category;
  final CategoryModel? parent;
  final String? initialName;

  const CategoryFormScreen({this.category, this.parent, this.initialName, super.key});
```

In `initState()` (around line 49-68), in the `else` branch (create mode, line 61), add after line 67:

```dart
      if (widget.initialName != null) {
        _nameController.text = widget.initialName!;
      }
```

- [ ] **Step 5: Verify compile of modified files**

Run: `cd /Volumes/rusty-drive/projects/pocket-pilot/frontend && flutter analyze lib/src/ui/router.dart lib/src/features/accounts/ui/account_form_screen.dart lib/src/features/categories/ui/category_form_screen.dart`
Expected: No issues found.

- [ ] **Step 6: Commit**

```bash
git add frontend/lib/src/ui/router.dart frontend/lib/src/features/accounts/ui/account_form_screen.dart frontend/lib/src/features/categories/ui/category_form_screen.dart
git commit -m "feat(csv-import): pre-fill initialName on account and category form screens"
```

---

### Task 6: Redesign the mapping screen — remove tags, add quick-create, hierarchical categories

**Files:**
- Modify: `frontend/lib/src/features/csv_import/ui/csv_mapping_screen.dart`

This is the largest task. It modifies the UI extensively.

- [ ] **Step 1: Remove the tag section from `build()`**

Delete lines 74-86 (the entire `if (result != null && result.uniqueTagNames.isNotEmpty)` block):

```dart
                  if (result != null &&
                      result.uniqueTagNames.isNotEmpty) ...[
                    _buildSectionHeader(
                      context,
                      'Tags',
                      vm.unmappedTagCount,
                    ),
                    const SizedBox(height: 8),
                    ...result.uniqueTagNames.map(
                      (name) => _buildTagTile(context, vm, name),
                    ),
                  ],
```

- [ ] **Step 2: Delete tag tile and picker methods**

Delete `_buildTagTile` (lines 316-331) and `_showTagPicker` (lines 333-364) entirely.

- [ ] **Step 3: Add `_expandedCategoryIds` state to `_CsvMappingScreenState`**

After `bool _loading = true;` (line 24), add:

```dart
  final Set<String> _expandedCategoryIds = {};
```

- [ ] **Step 4: Redesign `_showAccountPicker()` with quick-create**

Replace the entire `_showAccountPicker` method (lines 219-252) with:

```dart
  Future<void> _showAccountPicker(
    BuildContext context,
    CsvImportViewModel vm,
    String csvName,
  ) async {
    await showFormBottomSheet(
      context: context,
      builder: (ctx) => ScrollableBottomSheet(
        title: 'Seleccionar cuenta para "$csvName"',
        children: [
          // Quick-create shortcut.
          SheetItem(
            icon: Icons.bolt_rounded,
            label: 'Crear "$csvName" como cuenta (bank)',
            onTap: () async {
              Navigator.of(ctx).pop();
              await vm.quickCreateAccountAndMap(csvName);
            },
          ),
          const Divider(height: 1),
          // Existing accounts.
          ...vm.existingAccounts.map(
            (account) => SheetItem(
              icon: accountIconForType(account.type),
              label: account.name,
              onTap: () {
                vm.updateAccountMapping(csvName, account.id);
                Navigator.of(ctx).pop();
              },
            ),
          ),
          const Divider(height: 1),
          // Manual create with pre-filled name.
          SheetItem(
            icon: Icons.add_circle_outline_rounded,
            label: 'Crear cuenta manualmente',
            onTap: () async {
              Navigator.of(ctx).pop();
              await context.push('/accounts/new', extra: csvName);
              if (!mounted) return;
              await vm.refreshAccounts();
            },
          ),
        ],
      ),
    );
  }
```

- [ ] **Step 5: Redesign `_showCategoryPicker()` with hierarchy and quick-create**

Replace the entire `_showCategoryPicker` method (lines 275-310) with:

```dart
  Future<void> _showCategoryPicker(
    BuildContext context,
    CsvImportViewModel vm,
    String csvName,
  ) async {
    await showFormBottomSheet(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => ScrollableBottomSheet(
          title: 'Seleccionar categoría para "$csvName"',
          children: [
            // Quick-create shortcut.
            SheetItem(
              icon: Icons.bolt_rounded,
              label: 'Crear "$csvName" como categoría',
              onTap: () async {
                Navigator.of(ctx).pop();
                await vm.quickCreateCategoryAndMap(csvName);
              },
            ),
            const Divider(height: 1),
            // Hierarchical category list.
            ..._buildCategoryTreeItems(ctx, vm, csvName, vm.categoryTree, setSheetState),
            const Divider(height: 1),
            // Manual create with pre-filled name.
            SheetItem(
              icon: Icons.add_circle_outline_rounded,
              label: 'Crear categoría manualmente',
              onTap: () async {
                Navigator.of(ctx).pop();
                await context.push(
                  '/categories/new',
                  extra: <String, dynamic>{'initialName': csvName},
                );
                if (!mounted) return;
                await vm.refreshCategories();
              },
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildCategoryTreeItems(
    BuildContext ctx,
    CsvImportViewModel vm,
    String csvName,
    List<CategoryNode> nodes,
    StateSetter setSheetState,
  ) {
    final widgets = <Widget>[];
    for (final node in nodes) {
      final cat = node.category;
      final isExpanded = _expandedCategoryIds.contains(cat.id);
      final icon = cat.icon.isNotEmpty
          ? CategoryIconData.iconFromHex(cat.icon)
          : Icons.category_outlined;

      widgets.add(
        Padding(
          padding: EdgeInsets.only(left: node.depth * 16.0),
          child: SheetItem(
            icon: icon,
            label: cat.name,
            trailing: node.hasChildren
                ? GestureDetector(
                    onTap: () {
                      setSheetState(() {
                        if (isExpanded) {
                          _expandedCategoryIds.remove(cat.id);
                        } else {
                          _expandedCategoryIds.add(cat.id);
                        }
                      });
                    },
                    child: Icon(
                      isExpanded
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      size: 20,
                    ),
                  )
                : null,
            onTap: () {
              vm.updateCategoryMapping(csvName, cat.id);
              Navigator.of(ctx).pop();
            },
          ),
        ),
      );

      if (node.hasChildren && isExpanded) {
        widgets.addAll(
          _buildCategoryTreeItems(ctx, vm, csvName, node.children, setSheetState),
        );
      }
    }
    return widgets;
  }
```

- [ ] **Step 6: Add `trailing` support to `SheetItem`**

The `SheetItem` widget in `form_widgets.dart` needs a `trailing` parameter. Open `frontend/lib/src/features/transactions/ui/form_widgets.dart` and find the `SheetItem` class (around line 303). Add a `trailing` field:

In the class declaration, add the field:

```dart
class SheetItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Widget? trailing;

  const SheetItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.trailing,
    super.key,
  });
```

In the `build()` method's Row children, after the `label` Text widget and before the closing `]` of the Row's children, add:

```dart
            if (trailing != null) ...[
              const Spacer(),
              trailing!,
            ],
```

- [ ] **Step 7: Add the `CategoryNode` import to the mapping screen**

At the top of `csv_mapping_screen.dart`, the import for `csv_import_view_model.dart` already exists (line 13). Since `CategoryNode` is defined in the same file as the ViewModel, no additional import is needed.

- [ ] **Step 8: Verify full compile**

Run: `cd /Volumes/rusty-drive/projects/pocket-pilot/frontend && flutter analyze lib/src/features/csv_import/ lib/src/features/transactions/ui/form_widgets.dart`
Expected: No issues found.

- [ ] **Step 9: Commit**

```bash
git add frontend/lib/src/features/csv_import/ui/csv_mapping_screen.dart frontend/lib/src/features/transactions/ui/form_widgets.dart
git commit -m "feat(csv-import): remove tag section, add quick-create accounts, hierarchical categories"
```

---

### Task 7: Update Python scripts for new CSV columns

**Files:**
- Modify: `scripts/parsers/base.py`
- Modify: `scripts/csv_writer.py`
- Modify: `scripts/parsers/bbva_tc.py`

- [ ] **Step 1: Add new fields to `Transaction` dataclass**

In `scripts/parsers/base.py`, add two new fields with defaults after `notes`:

```python
@dataclass
class Transaction:
    date: date
    type: str               # "EXPENSE" | "INCOME"
    amount: float           # Always positive, in unit currency (pesos)
    currency: str           # "MXN"
    account: str            # Account name for CSV
    destination_account: str  # Always ""
    category: str           # Mapped category or ""
    tags: str               # Always ""
    notes: str              # Original bank concept
    nature: str = ""        # Financial nature (required, obligation, etc.)
    installments_count: int = 1  # MSI installment count
```

- [ ] **Step 2: Update CSV writer to emit new columns**

In `scripts/csv_writer.py`, update `HEADERS` and the row writer:

```python
import csv
from pathlib import Path

from parsers.base import Transaction

HEADERS = [
    "date", "type", "amount", "currency", "account",
    "destination_account", "category", "tags", "notes",
    "nature", "installments_count",
]


def write_csv(transactions: list[Transaction], output_path: Path) -> None:
    """Write transactions to CSV in the format Pocket Pilot expects."""
    with open(output_path, "w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow(HEADERS)
        for tx in transactions:
            writer.writerow([
                f"{tx.date} 12:00:00",
                tx.type,
                f"{tx.amount:.2f}",
                tx.currency,
                tx.account,
                tx.destination_account,
                tx.category,
                tx.tags,
                tx.notes,
                tx.nature,
                tx.installments_count,
            ])
```

- [ ] **Step 3: Extract installment count from MSI descriptions in `bbva_tc.py`**

In `scripts/parsers/bbva_tc.py`, add a regex after `TRANSACTION_RE` (after line 23):

```python
# Regex to extract MSI info from description like "AMAZON A MESES A 12 MESES S/I"
MSI_RE = re.compile(r"A\s+(\d+)\s+MESES\s+S/I")
```

In the `parse()` method, after extracting the description from the regex match (around line 106), add installment detection before creating the `Transaction`. Replace the section from `op_date_str, description, ...` through `transactions.append(...)`:

```python
                    op_date_str, description, sign, amount_str = match.groups()

                    op_date = _parse_date(op_date_str)
                    amount = _parse_amount(amount_str)

                    # + means charge (expense), - means payment/credit (income)
                    tx_type = "EXPENSE" if sign == "+" else "INCOME"

                    # Detect MSI installments from description.
                    installments_count = 1
                    msi_match = MSI_RE.search(description)
                    if msi_match:
                        installments_count = int(msi_match.group(1))

                    transactions.append(Transaction(
                        date=op_date,
                        type=tx_type,
                        amount=amount,
                        currency="MXN",
                        account=account_name,
                        destination_account="",
                        category="",
                        tags="",
                        notes=description.strip(),
                        installments_count=installments_count,
                    ))
```

- [ ] **Step 4: Verify by running against the real PDF**

Run: `cd /Volumes/rusty-drive/projects/pocket-pilot/scripts && uv run python parse_statement.py ../bbva_tc.pdf`
Expected: Output includes new columns. Check the CSV header line includes `nature,installments_count`. Check that MSI lines (like `AMAZON A MESES A 12 MESES S/I`) have `installments_count=12`.

- [ ] **Step 5: Commit**

```bash
git add scripts/parsers/base.py scripts/csv_writer.py scripts/parsers/bbva_tc.py
git commit -m "feat(scripts): add nature and installments_count columns to CSV output"
```

---

### Task 8: Manual end-to-end verification

- [ ] **Step 1: Run full Flutter analyze**

Run: `cd /Volumes/rusty-drive/projects/pocket-pilot/frontend && flutter analyze`
Expected: No issues in any of the modified files.

- [ ] **Step 2: Generate a test CSV with new columns**

Create a test CSV file at the project root with 11 columns:

```csv
date,type,amount,currency,account,destination_account,category,tags,notes,nature,installments_count
2026-04-01 12:00:00,EXPENSE,500.00,MXN,BBVA TC,,Internet,,TOTALPLAY,required,1
2026-04-02 12:00:00,EXPENSE,1200.00,MXN,Test Account,,NewCategory,NewTag,Amazon MSI,lifestyle,12
2026-04-03 12:00:00,INCOME,30000.00,MXN,BBVA,,Salario,,NOMINA,active,1
```

- [ ] **Step 3: Test CSV import in the app**

1. Launch the app: `cd /Volumes/rusty-drive/projects/pocket-pilot/frontend && flutter run`
2. Navigate to Settings → CSV Import
3. Import the test CSV
4. Verify: no tag section shown in mapping screen
5. Verify: account picker shows quick-create option for "Test Account"
6. Verify: category picker shows hierarchical view with collapsible groups
7. Verify: quick-create category for "NewCategory" works
8. Verify: import succeeds, check that nature and installments_count are stored correctly

- [ ] **Step 4: Test backwards compatibility with 9-column CSV**

Use the existing `pocket_pilot.csv` (9 columns) — import should work exactly as before with no errors.

- [ ] **Step 5: Test Python scripts**

Run: `cd /Volumes/rusty-drive/projects/pocket-pilot/scripts && uv run python parse_statement.py ../bbva_tc.pdf`
Verify the output CSV has 11 columns and MSI entries have correct `installments_count`.
