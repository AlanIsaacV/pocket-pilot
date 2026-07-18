# Transaction Filters Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a persistent filter sheet to the transactions screen with temporal and advanced filters, defaulting to last 30 days.

**Architecture:** A `TransactionFilter` value object flows from `TransactionFilterViewModel` (UI state) through `TransactionsViewModel` → `TransactionRepository` → `TransactionLocalStore` to produce a dynamic SQL WHERE clause. The filter sheet is a persistent `DraggableScrollableSheet` at the bottom of the transactions screen.

**Tech Stack:** Flutter, Provider/ChangeNotifier, sqflite, Material 3

**Spec:** `docs/superpowers/specs/2026-03-28-transaction-filters-design.md`

---

## File Structure

**New files** (all under `frontend/lib/src/features/transactions/`):

| File | Responsibility |
|---|---|
| `domain/transaction_filter.dart` | Immutable filter value object with date range, account, categories, type, status, currency |
| `ui/transaction_filter_view_model.dart` | UI state for the filter sheet (page index, quick selection, period nav, advanced filters) |
| `ui/widgets/filter_sheet.dart` | Persistent `DraggableScrollableSheet` container |
| `ui/widgets/temporal_page_view.dart` | `PageView` with Quick, Period, and Custom pages |
| `ui/widgets/advanced_filters.dart` | Dropdowns (account, type, status, currency) + category chips |
| `ui/widgets/category_multi_picker.dart` | Full-screen multi-select category picker |

**New migration:**

| File | Responsibility |
|---|---|
| `frontend/assets/migrations/002.sql` | Index on `transactions.date` |

**Modified files:**

| File | Change |
|---|---|
| `data/transaction_local_store.dart` | Add `queryRowsFiltered(TransactionFilter)` + `queryTopCategoryIds()` |
| `data/transaction_repository.dart` | `getTransactions()` accepts optional `TransactionFilter` |
| `ui/transactions_view_model.dart` | Depends on `TransactionFilterViewModel`, re-queries on filter change |
| `ui/transactions_route_scope.dart` | `MultiProvider` with both ViewModels |
| `ui/transactions_screen.dart` | Wrap list in `Stack` with `FilterSheet`, add filtered empty state |
| `core/db/database_helper.dart` | Bump `_version` to 2 |

---

### Task 1: TransactionFilter value object

**Files:**
- Create: `frontend/lib/src/features/transactions/domain/transaction_filter.dart`
- Test: `frontend/test/transaction_filter_test.dart`

- [ ] **Step 1: Write the test file**

```dart
// frontend/test/transaction_filter_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_pilot/src/features/transactions/domain/transaction_filter.dart';

void main() {
  group('TransactionFilter', () {
    test('defaultFilter returns 30D range ending today', () {
      final filter = TransactionFilter.defaultFilter();
      final today = DateTime.now();
      final todayStr =
          '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

      expect(filter.dateTo, todayStr);
      expect(filter.accountId, isNull);
      expect(filter.categoryIds, isEmpty);
      expect(filter.type, isNull);
      expect(filter.status, isNull);
      expect(filter.currencyCode, isNull);
    });

    test('typeValues maps transfer to both transfer types', () {
      final filter = TransactionFilter.defaultFilter().copyWith(type: 'transfer');
      expect(filter.typeValues, containsAll(['transfer_out', 'transfer_in']));
    });

    test('typeValues returns single value for income/expense', () {
      final income = TransactionFilter.defaultFilter().copyWith(type: 'income');
      expect(income.typeValues, ['income']);

      final expense = TransactionFilter.defaultFilter().copyWith(type: 'expense');
      expect(expense.typeValues, ['expense']);
    });

    test('typeValues returns null when type is null', () {
      final filter = TransactionFilter.defaultFilter();
      expect(filter.typeValues, isNull);
    });

    test('copyWith creates new instance with changed fields', () {
      final original = TransactionFilter.defaultFilter();
      final modified = original.copyWith(
        accountId: 'acc-1',
        categoryIds: ['cat-1', 'cat-2'],
        type: 'expense',
      );

      expect(modified.accountId, 'acc-1');
      expect(modified.categoryIds, ['cat-1', 'cat-2']);
      expect(modified.type, 'expense');
      // Unchanged fields
      expect(modified.dateFrom, original.dateFrom);
      expect(modified.dateTo, original.dateTo);
    });

    test('hasAdvancedFilters is false for default filter', () {
      expect(TransactionFilter.defaultFilter().hasAdvancedFilters, isFalse);
    });

    test('hasAdvancedFilters is true when any advanced field is set', () {
      final withAccount =
          TransactionFilter.defaultFilter().copyWith(accountId: 'acc-1');
      expect(withAccount.hasAdvancedFilters, isTrue);

      final withType =
          TransactionFilter.defaultFilter().copyWith(type: 'expense');
      expect(withType.hasAdvancedFilters, isTrue);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Volumes/rusty-drive/projects/pocket-pilot/frontend && flutter test test/transaction_filter_test.dart`
Expected: FAIL — cannot find `transaction_filter.dart`

- [ ] **Step 3: Create the TransactionFilter class**

```dart
// frontend/lib/src/features/transactions/domain/transaction_filter.dart

/// Immutable value object holding the resolved filter state.
///
/// Dates are YYYY-MM-DD strings matching the SQLite `date` column format.
class TransactionFilter {
  final String dateFrom;
  final String dateTo;
  final String? accountId;
  final List<String> categoryIds;
  final String? type;
  final String? status;
  final String? currencyCode;

  const TransactionFilter({
    required this.dateFrom,
    required this.dateTo,
    this.accountId,
    this.categoryIds = const [],
    this.type,
    this.status,
    this.currencyCode,
  });

  /// Default filter: last 30 days from today.
  factory TransactionFilter.defaultFilter() {
    final now = DateTime.now();
    final from = now.subtract(const Duration(days: 30));
    return TransactionFilter(
      dateFrom: _fmt(from),
      dateTo: _fmt(now),
    );
  }

  /// SQL-ready type values.
  /// "transfer" → ['transfer_out', 'transfer_in'].
  List<String>? get typeValues {
    if (type == null) return null;
    if (type == 'transfer') return ['transfer_out', 'transfer_in'];
    return [type!];
  }

  /// True if any advanced filter (non-temporal) is active.
  bool get hasAdvancedFilters =>
      accountId != null ||
      categoryIds.isNotEmpty ||
      type != null ||
      status != null ||
      currencyCode != null;

  TransactionFilter copyWith({
    String? dateFrom,
    String? dateTo,
    String? accountId,
    List<String>? categoryIds,
    String? type,
    String? status,
    String? currencyCode,
    bool clearAccountId = false,
    bool clearType = false,
    bool clearStatus = false,
    bool clearCurrencyCode = false,
  }) {
    return TransactionFilter(
      dateFrom: dateFrom ?? this.dateFrom,
      dateTo: dateTo ?? this.dateTo,
      accountId: clearAccountId ? null : (accountId ?? this.accountId),
      categoryIds: categoryIds ?? this.categoryIds,
      type: clearType ? null : (type ?? this.type),
      status: clearStatus ? null : (status ?? this.status),
      currencyCode:
          clearCurrencyCode ? null : (currencyCode ?? this.currencyCode),
    );
  }

  static String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /Volumes/rusty-drive/projects/pocket-pilot/frontend && flutter test test/transaction_filter_test.dart`
Expected: All 6 tests PASS

- [ ] **Step 5: Commit**

```bash
cd /Volumes/rusty-drive/projects/pocket-pilot
git add frontend/lib/src/features/transactions/domain/transaction_filter.dart frontend/test/transaction_filter_test.dart
git commit -m "feat(transactions): add TransactionFilter value object"
```

---

### Task 2: Migration 002.sql + DatabaseHelper version bump

**Files:**
- Create: `frontend/assets/migrations/002.sql`
- Modify: `frontend/lib/src/core/db/database_helper.dart:25`

- [ ] **Step 1: Create migration file**

```sql
-- frontend/assets/migrations/002.sql
-- Index on date column for filtered transaction queries.
CREATE INDEX IF NOT EXISTS idx_transactions_date
  ON transactions(date) WHERE deleted_at IS NULL;
```

- [ ] **Step 2: Bump database version**

In `frontend/lib/src/core/db/database_helper.dart`, change line 25:

```dart
// Before:
static const int _version = 1;
// After:
static const int _version = 2;
```

- [ ] **Step 3: Verify migration file is listed in assets**

Check `frontend/pubspec.yaml` for an `assets:` section that includes `assets/migrations/`. If it uses a glob pattern like `assets/migrations/`, the new file is already included. If individual files are listed, add `002.sql`.

- [ ] **Step 4: Commit**

```bash
cd /Volumes/rusty-drive/projects/pocket-pilot
git add frontend/assets/migrations/002.sql frontend/lib/src/core/db/database_helper.dart
git commit -m "feat(db): add date index on transactions table (migration 002)"
```

---

### Task 3: TransactionLocalStore — filtered query + top categories

**Files:**
- Modify: `frontend/lib/src/features/transactions/data/transaction_local_store.dart`

- [ ] **Step 1: Add the queryRowsFiltered method**

Add this import at the top of the file (after the existing imports):

```dart
import 'package:pocket_pilot/src/features/transactions/domain/transaction_filter.dart';
```

Add these two methods after the existing `queryLastTransferPair()` method (after line 111), inside the READ section:

```dart
  /// Queries transactions matching [filter] with a dynamic WHERE clause.
  /// Returns raw maps (repository enriches with category type).
  Future<List<Map<String, dynamic>>> queryRowsFiltered(
    TransactionFilter filter,
  ) async {
    final db = await _db.database;
    final where = StringBuffer('deleted_at IS NULL');
    final args = <dynamic>[];

    // Date range (always present)
    where.write(' AND date BETWEEN ? AND ?');
    args.addAll([filter.dateFrom, filter.dateTo]);

    // Account
    if (filter.accountId != null) {
      where.write(' AND account_id = ?');
      args.add(filter.accountId);
    }

    // Categories
    if (filter.categoryIds.isNotEmpty) {
      final placeholders = List.filled(filter.categoryIds.length, '?').join(',');
      where.write(' AND category_id IN ($placeholders)');
      args.addAll(filter.categoryIds);
    }

    // Type
    final typeValues = filter.typeValues;
    if (typeValues != null) {
      final placeholders = List.filled(typeValues.length, '?').join(',');
      where.write(' AND type IN ($placeholders)');
      args.addAll(typeValues);
    }

    // Status
    if (filter.status != null) {
      where.write(' AND status = ?');
      args.add(filter.status);
    }

    // Currency
    if (filter.currencyCode != null) {
      where.write(' AND currency_code = ?');
      args.add(filter.currencyCode);
    }

    return db.query(
      'transactions',
      where: where.toString(),
      whereArgs: args,
      orderBy: 'date DESC',
    );
  }

  /// Returns the IDs of the N most frequently used categories.
  Future<List<String>> queryTopCategoryIds({int limit = 5}) async {
    final db = await _db.database;
    final rows = await db.rawQuery(
      'SELECT category_id, COUNT(*) as cnt '
      'FROM transactions '
      'WHERE deleted_at IS NULL AND category_id IS NOT NULL '
      'GROUP BY category_id '
      'ORDER BY cnt DESC '
      'LIMIT ?',
      [limit],
    );
    return rows.map((r) => r['category_id'] as String).toList();
  }
```

- [ ] **Step 2: Verify the app compiles**

Run: `cd /Volumes/rusty-drive/projects/pocket-pilot/frontend && flutter analyze lib/src/features/transactions/data/transaction_local_store.dart`
Expected: No issues found

- [ ] **Step 3: Commit**

```bash
cd /Volumes/rusty-drive/projects/pocket-pilot
git add frontend/lib/src/features/transactions/data/transaction_local_store.dart
git commit -m "feat(transactions): add filtered query and top categories to local store"
```

---

### Task 4: TransactionRepository — accept filter

**Files:**
- Modify: `frontend/lib/src/features/transactions/data/transaction_repository.dart`

- [ ] **Step 1: Add import for TransactionFilter**

Add after existing imports (after line 6):

```dart
import 'package:pocket_pilot/src/features/transactions/domain/transaction_filter.dart';
```

- [ ] **Step 2: Update getTransactions to accept optional filter**

Replace the existing `getTransactions()` method (lines 28-31):

```dart
  // Before:
  Future<List<TransactionModel>> getTransactions() async {
    final rows = await _local.queryRows();
    return rows.map((r) => TransactionModel.fromMap(r)).toList();
  }

  // After:
  Future<List<TransactionModel>> getTransactions({
    TransactionFilter? filter,
  }) async {
    final rows = filter != null
        ? await _local.queryRowsFiltered(filter)
        : await _local.queryRows();
    return rows.map((r) => TransactionModel.fromMap(r)).toList();
  }
```

- [ ] **Step 3: Verify the app compiles**

Run: `cd /Volumes/rusty-drive/projects/pocket-pilot/frontend && flutter analyze lib/src/features/transactions/data/transaction_repository.dart`
Expected: No issues found

- [ ] **Step 4: Commit**

```bash
cd /Volumes/rusty-drive/projects/pocket-pilot
git add frontend/lib/src/features/transactions/data/transaction_repository.dart
git commit -m "feat(transactions): repository accepts optional TransactionFilter"
```

---

### Task 5: TransactionFilterViewModel

**Files:**
- Create: `frontend/lib/src/features/transactions/ui/transaction_filter_view_model.dart`
- Test: `frontend/test/transaction_filter_view_model_test.dart`

- [ ] **Step 1: Write the test file**

```dart
// frontend/test/transaction_filter_view_model_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_pilot/src/features/transactions/ui/transaction_filter_view_model.dart';

void main() {
  late TransactionFilterViewModel vm;

  setUp(() {
    vm = TransactionFilterViewModel();
  });

  group('TransactionFilterViewModel', () {
    test('initial state is Quick page with 30d selected', () {
      expect(vm.activePageIndex, 0);
      expect(vm.quickSelection, QuickRange.d30);
      expect(vm.resolvedFilter.type, isNull);
      expect(vm.resolvedFilter.accountId, isNull);
    });

    test('setQuickSelection updates filter and notifies', () {
      var notified = false;
      vm.addListener(() => notified = true);

      vm.setQuickSelection(QuickRange.d7);
      expect(vm.quickSelection, QuickRange.d7);
      expect(notified, isTrue);
    });

    test('setPeriodGranularity resets offset to 0', () {
      vm.setActivePageIndex(1);
      vm.navigatePeriod(-1); // go back one
      expect(vm.periodOffset, -1);

      vm.setPeriodGranularity(PeriodGranularity.year);
      expect(vm.periodOffset, 0);
      expect(vm.periodGranularity, PeriodGranularity.year);
    });

    test('navigatePeriod cannot go forward past 0', () {
      vm.setActivePageIndex(1);
      vm.navigatePeriod(1); // try to go forward from 0
      expect(vm.periodOffset, 0);
    });

    test('navigatePeriod can go back', () {
      vm.setActivePageIndex(1);
      vm.navigatePeriod(-1);
      expect(vm.periodOffset, -1);
      vm.navigatePeriod(-1);
      expect(vm.periodOffset, -2);
    });

    test('setCustomRange updates from and to', () {
      final from = DateTime(2026, 1, 1);
      final to = DateTime(2026, 1, 31);
      vm.setCustomRange(from, to);
      expect(vm.customFrom, from);
      expect(vm.customTo, to);
    });

    test('setAccountId updates resolvedFilter', () {
      vm.setAccountId('acc-1');
      expect(vm.resolvedFilter.accountId, 'acc-1');
    });

    test('setAccountId with null clears it', () {
      vm.setAccountId('acc-1');
      vm.setAccountId(null);
      expect(vm.resolvedFilter.accountId, isNull);
    });

    test('toggleCategory adds and removes', () {
      vm.toggleCategory('cat-1');
      expect(vm.resolvedFilter.categoryIds, ['cat-1']);

      vm.toggleCategory('cat-2');
      expect(vm.resolvedFilter.categoryIds, containsAll(['cat-1', 'cat-2']));

      vm.toggleCategory('cat-1');
      expect(vm.resolvedFilter.categoryIds, ['cat-2']);
    });

    test('clearAll resets to defaults', () {
      vm.setAccountId('acc-1');
      vm.setType('expense');
      vm.toggleCategory('cat-1');
      vm.setActivePageIndex(2);

      vm.clearAll();

      expect(vm.activePageIndex, 0);
      expect(vm.quickSelection, QuickRange.d30);
      expect(vm.resolvedFilter.accountId, isNull);
      expect(vm.resolvedFilter.type, isNull);
      expect(vm.resolvedFilter.categoryIds, isEmpty);
    });

    test('periodLabel returns correct label for month offset', () {
      vm.setActivePageIndex(1);
      vm.setPeriodGranularity(PeriodGranularity.month);
      // offset 0 = current month
      expect(vm.periodLabel, isNotEmpty);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Volumes/rusty-drive/projects/pocket-pilot/frontend && flutter test test/transaction_filter_view_model_test.dart`
Expected: FAIL — cannot find module

- [ ] **Step 3: Create the TransactionFilterViewModel**

```dart
// frontend/lib/src/features/transactions/ui/transaction_filter_view_model.dart

import 'package:flutter/foundation.dart';

import 'package:pocket_pilot/src/features/transactions/domain/transaction_filter.dart';

// ----------------------------------------------------------
// Enums
// ----------------------------------------------------------

enum QuickRange { d7, d30, m6, y1 }

enum PeriodGranularity { week, month, year }

// ----------------------------------------------------------
// ViewModel
// ----------------------------------------------------------

class TransactionFilterViewModel extends ChangeNotifier {
  // --- Temporal state ---
  int _activePageIndex = 0;
  QuickRange _quickSelection = QuickRange.d30;
  PeriodGranularity _periodGranularity = PeriodGranularity.month;
  int _periodOffset = 0;
  DateTime _customFrom = DateTime.now().subtract(const Duration(days: 30));
  DateTime _customTo = DateTime.now();

  // --- Advanced filter state ---
  String? _accountId;
  List<String> _categoryIds = [];
  String? _type;
  String? _status;
  String? _currencyCode;

  // --- Getters ---
  int get activePageIndex => _activePageIndex;
  QuickRange get quickSelection => _quickSelection;
  PeriodGranularity get periodGranularity => _periodGranularity;
  int get periodOffset => _periodOffset;
  DateTime get customFrom => _customFrom;
  DateTime get customTo => _customTo;
  String? get accountId => _accountId;
  List<String> get categoryIds => List.unmodifiable(_categoryIds);
  String? get type => _type;
  String? get status => _status;
  String? get currencyCode => _currencyCode;

  // ----------------------------------------------------------
  // Temporal setters
  // ----------------------------------------------------------

  void setActivePageIndex(int index) {
    _activePageIndex = index;
    notifyListeners();
  }

  void setQuickSelection(QuickRange range) {
    _quickSelection = range;
    _activePageIndex = 0;
    notifyListeners();
  }

  void setPeriodGranularity(PeriodGranularity g) {
    _periodGranularity = g;
    _periodOffset = 0;
    _activePageIndex = 1;
    notifyListeners();
  }

  void navigatePeriod(int delta) {
    final next = _periodOffset + delta;
    if (next > 0) return; // cannot go past current period
    _periodOffset = next;
    notifyListeners();
  }

  void setCustomRange(DateTime from, DateTime to) {
    _customFrom = from;
    _customTo = to;
    _activePageIndex = 2;
    notifyListeners();
  }

  // ----------------------------------------------------------
  // Advanced setters
  // ----------------------------------------------------------

  void setAccountId(String? id) {
    _accountId = id;
    notifyListeners();
  }

  void toggleCategory(String id) {
    if (_categoryIds.contains(id)) {
      _categoryIds = _categoryIds.where((c) => c != id).toList();
    } else {
      _categoryIds = [..._categoryIds, id];
    }
    notifyListeners();
  }

  void setCategoryIds(List<String> ids) {
    _categoryIds = ids;
    notifyListeners();
  }

  void setType(String? t) {
    _type = t;
    notifyListeners();
  }

  void setStatus(String? s) {
    _status = s;
    notifyListeners();
  }

  void setCurrencyCode(String? c) {
    _currencyCode = c;
    notifyListeners();
  }

  void clearAll() {
    _activePageIndex = 0;
    _quickSelection = QuickRange.d30;
    _periodGranularity = PeriodGranularity.month;
    _periodOffset = 0;
    _customFrom = DateTime.now().subtract(const Duration(days: 30));
    _customTo = DateTime.now();
    _accountId = null;
    _categoryIds = [];
    _type = null;
    _status = null;
    _currencyCode = null;
    notifyListeners();
  }

  // ----------------------------------------------------------
  // Resolved filter
  // ----------------------------------------------------------

  TransactionFilter get resolvedFilter {
    final (from, to) = _resolveDateRange();
    return TransactionFilter(
      dateFrom: from,
      dateTo: to,
      accountId: _accountId,
      categoryIds: _categoryIds,
      type: _type,
      status: _status,
      currencyCode: _currencyCode,
    );
  }

  (String, String) _resolveDateRange() {
    switch (_activePageIndex) {
      case 0:
        return _resolveQuick();
      case 1:
        return _resolvePeriod();
      case 2:
        return (TransactionFilter._fmt(_customFrom),
            TransactionFilter._fmt(_customTo));
      default:
        return _resolveQuick();
    }
  }

  (String, String) _resolveQuick() {
    final now = DateTime.now();
    final Duration duration;
    switch (_quickSelection) {
      case QuickRange.d7:
        duration = const Duration(days: 7);
      case QuickRange.d30:
        duration = const Duration(days: 30);
      case QuickRange.m6:
        duration = const Duration(days: 182);
      case QuickRange.y1:
        duration = const Duration(days: 365);
    }
    final from = now.subtract(duration);
    return (TransactionFilter._fmt(from), TransactionFilter._fmt(now));
  }

  (String, String) _resolvePeriod() {
    final now = DateTime.now();
    switch (_periodGranularity) {
      case PeriodGranularity.week:
        final currentMonday = now.subtract(Duration(days: now.weekday - 1));
        final targetMonday =
            currentMonday.add(Duration(days: 7 * _periodOffset));
        final targetSunday = targetMonday.add(const Duration(days: 6));
        return (TransactionFilter._fmt(targetMonday),
            TransactionFilter._fmt(targetSunday));
      case PeriodGranularity.month:
        final targetMonth =
            DateTime(now.year, now.month + _periodOffset, 1);
        final lastDay =
            DateTime(targetMonth.year, targetMonth.month + 1, 0);
        return (TransactionFilter._fmt(targetMonth),
            TransactionFilter._fmt(lastDay));
      case PeriodGranularity.year:
        final targetYear = DateTime(now.year + _periodOffset, 1, 1);
        final lastDay = DateTime(targetYear.year, 12, 31);
        return (TransactionFilter._fmt(targetYear),
            TransactionFilter._fmt(lastDay));
    }
  }

  // ----------------------------------------------------------
  // Period label for display
  // ----------------------------------------------------------

  String get periodLabel {
    if (_periodOffset == 0) return _periodGranularityLabel;
    final now = DateTime.now();
    switch (_periodGranularity) {
      case PeriodGranularity.week:
        final currentMonday = now.subtract(Duration(days: now.weekday - 1));
        final targetMonday =
            currentMonday.add(Duration(days: 7 * _periodOffset));
        return '${targetMonday.day}/${targetMonday.month}';
      case PeriodGranularity.month:
        final target = DateTime(now.year, now.month + _periodOffset, 1);
        return _monthName(target.month);
      case PeriodGranularity.year:
        return '${now.year + _periodOffset}';
    }
  }

  String get _periodGranularityLabel {
    switch (_periodGranularity) {
      case PeriodGranularity.week:
        return 'Week';
      case PeriodGranularity.month:
        return 'Month';
      case PeriodGranularity.year:
        return 'Year';
    }
  }

  bool get isAtCurrentPeriod => _periodOffset == 0;

  static String _monthName(int month) {
    const names = [
      'Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio',
      'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre',
    ];
    return names[month - 1];
  }
}
```

- [ ] **Step 4: Make `_fmt` accessible from ViewModel**

The ViewModel calls `TransactionFilter._fmt()` which is private. Change `_fmt` to a package-private static method. In `transaction_filter.dart`, rename:

```dart
// Before:
static String _fmt(DateTime d) =>
// After:
static String fmt(DateTime d) =>
```

And update the `defaultFilter` factory to call `fmt` instead of `_fmt`.

Then in `transaction_filter_view_model.dart`, replace all `TransactionFilter._fmt(` with `TransactionFilter.fmt(`.

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd /Volumes/rusty-drive/projects/pocket-pilot/frontend && flutter test test/transaction_filter_view_model_test.dart`
Expected: All tests PASS

- [ ] **Step 6: Commit**

```bash
cd /Volumes/rusty-drive/projects/pocket-pilot
git add frontend/lib/src/features/transactions/ui/transaction_filter_view_model.dart frontend/lib/src/features/transactions/domain/transaction_filter.dart frontend/test/transaction_filter_view_model_test.dart
git commit -m "feat(transactions): add TransactionFilterViewModel with temporal and advanced state"
```

---

### Task 6: Modify TransactionsViewModel to use filter

**Files:**
- Modify: `frontend/lib/src/features/transactions/ui/transactions_view_model.dart`

- [ ] **Step 1: Add import and dependency**

Add import (after line 6):

```dart
import 'package:pocket_pilot/src/features/transactions/ui/transaction_filter_view_model.dart';
```

- [ ] **Step 2: Update constructor and add dispose**

Replace the constructor and field declarations (lines 15-30) with:

```dart
class TransactionsViewModel extends ChangeNotifier {
  final TransactionRepository _repository;
  final SyncService _syncService;
  final TransactionFilterViewModel _filterViewModel;

  List<TransactionModel> transactions = [];
  bool isLoading = false;
  bool isSyncing = false;
  String? errorMessage;

  DateTime? _lastSyncAt;

  TransactionsViewModel({
    required TransactionRepository repository,
    required SyncService syncService,
    required TransactionFilterViewModel filterViewModel,
  }) : _repository = repository,
       _syncService = syncService,
       _filterViewModel = filterViewModel {
    _filterViewModel.addListener(_onFilterChanged);
  }

  void _onFilterChanged() {
    _loadLocal();
  }

  @override
  void dispose() {
    _filterViewModel.removeListener(_onFilterChanged);
    super.dispose();
  }
```

- [ ] **Step 3: Add `_loadLocal` helper and update existing methods**

Add a `_loadLocal` method and update `_loadLocalThenMaybeSync` and `_runSync` to use the filter. Replace the implementation section (lines 83-115):

```dart
  // ----------------------------------------------------------
  // Implementación interna
  // ----------------------------------------------------------

  Future<void> _loadLocal() async {
    transactions = await _repository.getTransactions(
      filter: _filterViewModel.resolvedFilter,
    );
    notifyListeners();
  }

  Future<void> _loadLocalThenMaybeSync() async {
    await _loadLocal();
    await _maybeSyncRemote();
  }

  Future<void> _maybeSyncRemote() async {
    final last = _lastSyncAt;
    if (last != null &&
        DateTime.now().difference(last) < const Duration(seconds: 5)) {
      return;
    }
    await _runSync();
  }

  Future<void> _runSync() async {
    isLoading = transactions.isEmpty;
    isSyncing = true;
    notifyListeners();

    try {
      await _syncService.sync();
      transactions = await _repository.getTransactions(
        filter: _filterViewModel.resolvedFilter,
      );
      _lastSyncAt = DateTime.now();
      errorMessage = null;
    } catch (e) {
      errorMessage = e.toString();
    } finally {
      isLoading = false;
      isSyncing = false;
      notifyListeners();
    }
  }
```

- [ ] **Step 4: Verify the file compiles**

Run: `cd /Volumes/rusty-drive/projects/pocket-pilot/frontend && flutter analyze lib/src/features/transactions/ui/transactions_view_model.dart`
Expected: No issues found

- [ ] **Step 5: Commit**

```bash
cd /Volumes/rusty-drive/projects/pocket-pilot
git add frontend/lib/src/features/transactions/ui/transactions_view_model.dart
git commit -m "feat(transactions): TransactionsViewModel listens to filter changes"
```

---

### Task 7: Update TransactionsRouteScope with MultiProvider

**Files:**
- Modify: `frontend/lib/src/features/transactions/ui/transactions_route_scope.dart`

- [ ] **Step 1: Rewrite the route scope**

Replace the entire file content with:

```dart
// ============================================================
// TransactionsRouteScope — inyección de dependencias de Transactions
// ============================================================

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import 'package:pocket_pilot/src/core/db/database_helper.dart';
import 'package:pocket_pilot/src/core/sync/sync_outbox.dart';
import 'package:pocket_pilot/src/core/sync/sync_service.dart';
import 'package:pocket_pilot/src/features/transactions/data/transaction_local_store.dart';
import 'package:pocket_pilot/src/features/transactions/data/transaction_repository.dart';
import 'package:pocket_pilot/src/features/transactions/ui/transaction_filter_view_model.dart';
import 'package:pocket_pilot/src/features/transactions/ui/transactions_view_model.dart';

class TransactionsRouteScope extends StatelessWidget {
  final Widget child;

  const TransactionsRouteScope({required this.child, super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => TransactionFilterViewModel(),
        ),
        ChangeNotifierProvider(
          create: (ctx) {
            final db = ctx.read<DatabaseHelper>();
            final outbox = ctx.read<SyncOutbox>();
            final syncService = ctx.read<SyncService>();
            final filterVM = ctx.read<TransactionFilterViewModel>();

            final transactionLocalStore = TransactionLocalStore(db: db);
            final repository = TransactionRepository(
              local: transactionLocalStore,
              outbox: outbox,
            );

            return TransactionsViewModel(
              repository: repository,
              syncService: syncService,
              filterViewModel: filterVM,
            )..loadOnAppear();
          },
        ),
      ],
      child: child,
    );
  }
}
```

- [ ] **Step 2: Verify the app compiles**

Run: `cd /Volumes/rusty-drive/projects/pocket-pilot/frontend && flutter analyze lib/src/features/transactions/ui/transactions_route_scope.dart`
Expected: No issues found

- [ ] **Step 3: Commit**

```bash
cd /Volumes/rusty-drive/projects/pocket-pilot
git add frontend/lib/src/features/transactions/ui/transactions_route_scope.dart
git commit -m "feat(transactions): MultiProvider scope with FilterViewModel"
```

---

### Task 8: TemporalPageView widget

**Files:**
- Create: `frontend/lib/src/features/transactions/ui/widgets/temporal_page_view.dart`

- [ ] **Step 1: Create the widget**

```dart
// frontend/lib/src/features/transactions/ui/widgets/temporal_page_view.dart

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'package:pocket_pilot/src/core/theme/app_theme.dart';
import 'package:pocket_pilot/src/features/transactions/ui/transaction_filter_view_model.dart';

class TemporalPageView extends StatefulWidget {
  const TemporalPageView({super.key});

  @override
  State<TemporalPageView> createState() => _TemporalPageViewState();
}

class _TemporalPageViewState extends State<TemporalPageView> {
  late PageController _pageController;

  @override
  void initState() {
    super.initState();
    final vm = context.read<TransactionFilterViewModel>();
    _pageController = PageController(initialPage: vm.activePageIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<TransactionFilterViewModel>();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 40,
          child: PageView(
            controller: _pageController,
            onPageChanged: (i) => vm.setActivePageIndex(i),
            children: [
              _QuickPage(vm: vm),
              _PeriodPage(vm: vm),
              _CustomPage(vm: vm),
            ],
          ),
        ),
        const SizedBox(height: 8),
        _DotsIndicator(
          count: 3,
          activeIndex: vm.activePageIndex,
        ),
      ],
    );
  }
}

// ----------------------------------------------------------
// Page 1: Quick (7D, 30D, 6M, 1Y)
// ----------------------------------------------------------

class _QuickPage extends StatelessWidget {
  final TransactionFilterViewModel vm;
  const _QuickPage({required this.vm});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: QuickRange.values.map((range) {
        final isSelected = vm.quickSelection == range &&
            vm.activePageIndex == 0;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: _FilterChip(
            label: _label(range),
            isSelected: isSelected,
            onTap: () => vm.setQuickSelection(range),
          ),
        );
      }).toList(),
    );
  }

  String _label(QuickRange r) => switch (r) {
        QuickRange.d7 => '7D',
        QuickRange.d30 => '30D',
        QuickRange.m6 => '6M',
        QuickRange.y1 => '1Y',
      };
}

// ----------------------------------------------------------
// Page 2: Period (← [dropdown] →)
// ----------------------------------------------------------

class _PeriodPage extends StatelessWidget {
  final TransactionFilterViewModel vm;
  const _PeriodPage({required this.vm});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left_rounded),
          iconSize: 22,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          onPressed: () => vm.navigatePeriod(-1),
        ),
        GestureDetector(
          onTap: () => _showGranularityPicker(context),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: vm.activePageIndex == 1
                  ? cs.primary.withValues(alpha: 0.15)
                  : cs.surfaceContainerHigh,
              borderRadius: AppTheme.radiusSmall,
              border: vm.activePageIndex == 1
                  ? Border.all(color: cs.primary.withValues(alpha: 0.4))
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  vm.periodLabel,
                  style: GoogleFonts.ibmPlexSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.arrow_drop_down_rounded,
                  size: 18,
                  color: cs.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.chevron_right_rounded),
          iconSize: 22,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          onPressed: vm.isAtCurrentPeriod
              ? null
              : () => vm.navigatePeriod(1),
        ),
      ],
    );
  }

  void _showGranularityPicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: PeriodGranularity.values.map((g) {
            final label = switch (g) {
              PeriodGranularity.week => 'Week',
              PeriodGranularity.month => 'Month',
              PeriodGranularity.year => 'Year',
            };
            return ListTile(
              title: Text(label),
              trailing: vm.periodGranularity == g
                  ? Icon(Icons.check_rounded,
                      color: Theme.of(context).colorScheme.primary)
                  : null,
              onTap: () {
                vm.setPeriodGranularity(g);
                Navigator.of(context).pop();
              },
            );
          }).toList(),
        ),
      ),
    );
  }
}

// ----------------------------------------------------------
// Page 3: Custom (date — date)
// ----------------------------------------------------------

class _CustomPage extends StatelessWidget {
  final TransactionFilterViewModel vm;
  const _CustomPage({required this.vm});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _DateButton(
          date: vm.customFrom,
          cs: cs,
          onTap: () => _pickDate(context, isFrom: true),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text('—',
              style: GoogleFonts.ibmPlexSans(
                  color: cs.onSurfaceVariant, fontSize: 14)),
        ),
        _DateButton(
          date: vm.customTo,
          cs: cs,
          onTap: () => _pickDate(context, isFrom: false),
        ),
      ],
    );
  }

  Future<void> _pickDate(BuildContext context, {required bool isFrom}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isFrom ? vm.customFrom : vm.customTo,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      if (isFrom) {
        vm.setCustomRange(picked, vm.customTo);
      } else {
        vm.setCustomRange(vm.customFrom, picked);
      }
    }
  }
}

class _DateButton extends StatelessWidget {
  final DateTime date;
  final ColorScheme cs;
  final VoidCallback onTap;
  const _DateButton({required this.date, required this.cs, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final label =
        '${_monthAbbr(date.month)} ${date.day}, ${date.year}';
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHigh,
          borderRadius: AppTheme.radiusSmall,
          border: Border.all(color: cs.outline),
        ),
        child: Text(
          label,
          style: GoogleFonts.ibmPlexSans(fontSize: 13, color: cs.onSurface),
        ),
      ),
    );
  }

  static String _monthAbbr(int m) {
    const abbrs = [
      'Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun',
      'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic',
    ];
    return abbrs[m - 1];
  }
}

// ----------------------------------------------------------
// Shared widgets
// ----------------------------------------------------------

class _FilterChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  const _FilterChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? cs.primary.withValues(alpha: 0.15)
              : cs.surfaceContainerHigh,
          borderRadius: AppTheme.radiusFull,
          border: isSelected
              ? Border.all(color: cs.primary.withValues(alpha: 0.5))
              : null,
        ),
        child: Text(
          label,
          style: GoogleFonts.ibmPlexSans(
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
            color: isSelected ? cs.primary : cs.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _DotsIndicator extends StatelessWidget {
  final int count;
  final int activeIndex;
  const _DotsIndicator({required this.count, required this.activeIndex});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (i) {
        return Container(
          width: 6,
          height: 6,
          margin: const EdgeInsets.symmetric(horizontal: 3),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: i == activeIndex
                ? cs.primary
                : cs.onSurfaceVariant.withValues(alpha: 0.3),
          ),
        );
      }),
    );
  }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `cd /Volumes/rusty-drive/projects/pocket-pilot/frontend && flutter analyze lib/src/features/transactions/ui/widgets/temporal_page_view.dart`
Expected: No issues found

- [ ] **Step 3: Commit**

```bash
cd /Volumes/rusty-drive/projects/pocket-pilot
git add frontend/lib/src/features/transactions/ui/widgets/temporal_page_view.dart
git commit -m "feat(transactions): add TemporalPageView with Quick, Period, Custom pages"
```

---

### Task 9: AdvancedFilters widget

**Files:**
- Create: `frontend/lib/src/features/transactions/ui/widgets/advanced_filters.dart`

- [ ] **Step 1: Create the widget**

```dart
// frontend/lib/src/features/transactions/ui/widgets/advanced_filters.dart

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'package:pocket_pilot/src/core/theme/app_colors.dart';
import 'package:pocket_pilot/src/core/theme/app_theme.dart';
import 'package:pocket_pilot/src/features/accounts/domain/account.dart';
import 'package:pocket_pilot/src/features/categories/domain/category.dart';
import 'package:pocket_pilot/src/features/categories/ui/category_icon_data.dart';
import 'package:pocket_pilot/src/features/transactions/ui/transaction_filter_view_model.dart';
import 'package:pocket_pilot/src/features/transactions/ui/widgets/category_multi_picker.dart';

class AdvancedFilters extends StatelessWidget {
  final List<AccountModel> accounts;
  final List<CategoryModel> topCategories;
  final List<String> currencies;

  const AdvancedFilters({
    required this.accounts,
    required this.topCategories,
    required this.currencies,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<TransactionFilterViewModel>();
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        // Row 1: Account + Type
        Row(
          children: [
            Expanded(
              child: _DropdownField(
                label: 'Account',
                value: vm.accountId,
                items: [
                  const DropdownMenuItem(value: null, child: Text('All')),
                  ...accounts.map((a) => DropdownMenuItem(
                        value: a.id,
                        child: Text(a.name, overflow: TextOverflow.ellipsis),
                      )),
                ],
                onChanged: (v) => vm.setAccountId(v),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _DropdownField(
                label: 'Type',
                value: vm.type,
                items: const [
                  DropdownMenuItem(value: null, child: Text('All')),
                  DropdownMenuItem(value: 'income', child: Text('Income')),
                  DropdownMenuItem(value: 'expense', child: Text('Expense')),
                  DropdownMenuItem(value: 'transfer', child: Text('Transfer')),
                ],
                onChanged: (v) => vm.setType(v),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        // Row 2: Status + Currency
        Row(
          children: [
            Expanded(
              child: _DropdownField(
                label: 'Status',
                value: vm.status,
                items: const [
                  DropdownMenuItem(value: null, child: Text('All')),
                  DropdownMenuItem(value: 'cleared', child: Text('Cleared')),
                  DropdownMenuItem(value: 'pending', child: Text('Pending')),
                ],
                onChanged: (v) => vm.setStatus(v),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _DropdownField(
                label: 'Currency',
                value: vm.currencyCode,
                items: [
                  const DropdownMenuItem(value: null, child: Text('All')),
                  ...currencies.map((c) => DropdownMenuItem(
                        value: c,
                        child: Text(c),
                      )),
                ],
                onChanged: (v) => vm.setCurrencyCode(v),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        // Categories
        _SectionLabel(label: 'Categories'),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            ...topCategories.map((cat) {
              final isSelected = vm.categoryIds.contains(cat.id);
              return _CategoryChipFilter(
                category: cat,
                isSelected: isSelected,
                onTap: () => vm.toggleCategory(cat.id),
              );
            }),
            _MoreChip(
              onTap: () => _openMultiPicker(context, vm),
            ),
          ],
        ),
        const SizedBox(height: 14),
        // Clear all
        Center(
          child: TextButton(
            onPressed: vm.resolvedFilter.hasAdvancedFilters ||
                    vm.activePageIndex != 0 ||
                    vm.quickSelection != QuickRange.d30
                ? () => vm.clearAll()
                : null,
            child: Text(
              'Limpiar filtros',
              style: GoogleFonts.ibmPlexSans(fontSize: 13),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _openMultiPicker(
    BuildContext context,
    TransactionFilterViewModel vm,
  ) async {
    final result = await Navigator.of(context).push<List<String>>(
      MaterialPageRoute(
        builder: (_) => CategoryMultiPicker(
          selectedIds: vm.categoryIds,
        ),
      ),
    );
    if (result != null) {
      vm.setCategoryIds(result);
    }
  }
}

// ----------------------------------------------------------
// Internal widgets
// ----------------------------------------------------------

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(
      label.toUpperCase(),
      style: GoogleFonts.ibmPlexSans(
        fontSize: 10,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}

class _DropdownField extends StatelessWidget {
  final String label;
  final String? value;
  final List<DropdownMenuItem<String?>> items;
  final ValueChanged<String?> onChanged;

  const _DropdownField({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionLabel(label: label),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHigh,
            borderRadius: AppTheme.radiusSmall,
            border: Border.all(color: cs.outline),
          ),
          child: DropdownButton<String?>(
            value: value,
            items: items,
            onChanged: onChanged,
            isExpanded: true,
            underline: const SizedBox.shrink(),
            icon: Icon(Icons.arrow_drop_down_rounded,
                size: 20, color: cs.onSurfaceVariant),
            style: GoogleFonts.ibmPlexSans(
              fontSize: 13,
              color: cs.onSurface,
            ),
            dropdownColor: cs.surfaceContainerHigh,
          ),
        ),
      ],
    );
  }
}

Color _hexToColor(String hex) {
  if (hex.isEmpty) return AppColors.primary;
  try {
    final sanitized = hex.replaceFirst('#', '');
    if (sanitized.length != 6) return AppColors.primary;
    return Color(int.parse('FF$sanitized', radix: 16));
  } catch (_) {
    return AppColors.primary;
  }
}

class _CategoryChipFilter extends StatelessWidget {
  final CategoryModel category;
  final bool isSelected;
  final VoidCallback onTap;
  const _CategoryChipFilter({
    required this.category,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final chipColor = _hexToColor(category.color);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? cs.primary.withValues(alpha: 0.15)
              : cs.surfaceContainerHigh,
          borderRadius: AppTheme.radiusFull,
          border: isSelected
              ? Border.all(color: cs.primary.withValues(alpha: 0.5))
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: chipColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              category.name,
              style: GoogleFonts.ibmPlexSans(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                color: cs.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MoreChip extends StatelessWidget {
  final VoidCallback onTap;
  const _MoreChip({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHigh,
          borderRadius: AppTheme.radiusFull,
        ),
        child: Text(
          '+ More',
          style: GoogleFonts.ibmPlexSans(
            fontSize: 12,
            color: cs.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Verify it compiles** (will fail until CategoryMultiPicker exists — that's next)

- [ ] **Step 3: Commit** (commit together with Task 10)

---

### Task 10: CategoryMultiPicker

**Files:**
- Create: `frontend/lib/src/features/transactions/ui/widgets/category_multi_picker.dart`

- [ ] **Step 1: Create the multi-select picker**

Based on the existing `CategoryPickerScreen` pattern but returns `List<String>` of selected IDs:

```dart
// frontend/lib/src/features/transactions/ui/widgets/category_multi_picker.dart

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'package:pocket_pilot/src/core/theme/app_colors.dart';
import 'package:pocket_pilot/src/core/theme/app_theme.dart';
import 'package:pocket_pilot/src/features/categories/data/category_local_store.dart';
import 'package:pocket_pilot/src/features/categories/domain/category.dart';
import 'package:pocket_pilot/src/features/categories/ui/category_icon_data.dart';

class CategoryMultiPicker extends StatefulWidget {
  final List<String> selectedIds;

  const CategoryMultiPicker({required this.selectedIds, super.key});

  @override
  State<CategoryMultiPicker> createState() => _CategoryMultiPickerState();
}

class _CategoryMultiPickerState extends State<CategoryMultiPicker> {
  List<CategoryModel> _allCategories = [];
  late Set<String> _selected;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _selected = Set.of(widget.selectedIds);
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    final store = context.read<CategoryLocalStore>();
    final categories = await store.getCategories();
    setState(() {
      _allCategories = categories;
      _isLoading = false;
    });
  }

  List<CategoryModel> get _rootCategories =>
      _allCategories.where((c) => c.parentId == null).toList();

  List<CategoryModel> _childrenOf(String parentId) =>
      _allCategories.where((c) => c.parentId == parentId).toList();

  bool _hasChildren(String id) =>
      _allCategories.any((c) => c.parentId == id);

  void _toggle(String id) {
    setState(() {
      if (_selected.contains(id)) {
        _selected.remove(id);
      } else {
        _selected.add(id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Seleccionar categorías'),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(_selected.toList()),
            child: Text(
              'Listo (${_selected.length})',
              style: GoogleFonts.ibmPlexSans(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              children: _rootCategories
                  .expand((cat) => _buildCategoryTree(cat, 0))
                  .toList(),
            ),
    );
  }

  List<Widget> _buildCategoryTree(CategoryModel cat, int depth) {
    final children = _childrenOf(cat.id);
    return [
      _CategoryMultiTile(
        category: cat,
        isSelected: _selected.contains(cat.id),
        depth: depth,
        onTap: () => _toggle(cat.id),
      ),
      ...children.expand((child) => _buildCategoryTree(child, depth + 1)),
    ];
  }
}

Color _hexToColor(String hex) {
  if (hex.isEmpty) return AppColors.primary;
  try {
    final sanitized = hex.replaceFirst('#', '');
    if (sanitized.length != 6) return AppColors.primary;
    return Color(int.parse('FF$sanitized', radix: 16));
  } catch (_) {
    return AppColors.primary;
  }
}

class _CategoryMultiTile extends StatelessWidget {
  final CategoryModel category;
  final bool isSelected;
  final int depth;
  final VoidCallback onTap;

  const _CategoryMultiTile({
    required this.category,
    required this.isSelected,
    required this.depth,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tileColor = _hexToColor(category.color);

    return InkWell(
      onTap: onTap,
      borderRadius: AppTheme.radiusMedium,
      child: Padding(
        padding: EdgeInsets.fromLTRB(16.0 + depth * 24.0, 8, 16, 8),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: tileColor.withValues(alpha: 0.15),
                borderRadius: AppTheme.radiusMedium,
              ),
              child: Center(
                child: Icon(
                  CategoryIconData.iconFromHex(category.icon),
                  size: 16,
                  color: tileColor,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                category.name,
                style: GoogleFonts.ibmPlexSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: cs.onSurface,
                ),
              ),
            ),
            Icon(
              isSelected
                  ? Icons.check_circle_rounded
                  : Icons.circle_outlined,
              size: 22,
              color: isSelected ? cs.primary : cs.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Verify both widgets compile**

Run: `cd /Volumes/rusty-drive/projects/pocket-pilot/frontend && flutter analyze lib/src/features/transactions/ui/widgets/`
Expected: No issues found

- [ ] **Step 3: Commit**

```bash
cd /Volumes/rusty-drive/projects/pocket-pilot
git add frontend/lib/src/features/transactions/ui/widgets/advanced_filters.dart frontend/lib/src/features/transactions/ui/widgets/category_multi_picker.dart
git commit -m "feat(transactions): add AdvancedFilters and CategoryMultiPicker widgets"
```

---

### Task 11: FilterSheet container

**Files:**
- Create: `frontend/lib/src/features/transactions/ui/widgets/filter_sheet.dart`

- [ ] **Step 1: Create the FilterSheet**

```dart
// frontend/lib/src/features/transactions/ui/widgets/filter_sheet.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:pocket_pilot/src/core/db/database_helper.dart';
import 'package:pocket_pilot/src/core/theme/app_theme.dart';
import 'package:pocket_pilot/src/features/accounts/data/account_local_store.dart';
import 'package:pocket_pilot/src/features/accounts/domain/account.dart';
import 'package:pocket_pilot/src/features/categories/data/category_local_store.dart';
import 'package:pocket_pilot/src/features/categories/domain/category.dart';
import 'package:pocket_pilot/src/features/transactions/data/transaction_local_store.dart';
import 'package:pocket_pilot/src/features/transactions/ui/widgets/advanced_filters.dart';
import 'package:pocket_pilot/src/features/transactions/ui/widgets/temporal_page_view.dart';

class FilterSheet extends StatefulWidget {
  const FilterSheet({super.key});

  @override
  State<FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<FilterSheet> {
  List<AccountModel> _accounts = [];
  List<CategoryModel> _topCategories = [];
  List<String> _currencies = [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadFilterData();
  }

  Future<void> _loadFilterData() async {
    final db = context.read<DatabaseHelper>();
    final accountStore = AccountLocalStore(db: db);
    final categoryStore = CategoryLocalStore(db: db);
    final txnStore = TransactionLocalStore(db: db);

    final accounts = await accountStore.getAccounts();
    final topIds = await txnStore.queryTopCategoryIds();
    final allCategories = await categoryStore.getCategories();

    // Resolve top categories in order, keeping only existing ones
    final topCategories = <CategoryModel>[];
    for (final id in topIds) {
      final cat = allCategories.where((c) => c.id == id).firstOrNull;
      if (cat != null) topCategories.add(cat);
    }

    // Distinct currencies from accounts
    final currencies = accounts.map((a) => a.currencyCode).toSet().toList()
      ..sort();

    if (mounted) {
      setState(() {
        _accounts = accounts;
        _topCategories = topCategories;
        _currencies = currencies;
        _loaded = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return DraggableScrollableSheet(
      initialChildSize: 0.12,
      minChildSize: 0.12,
      maxChildSize: 0.55,
      snap: true,
      snapSizes: const [0.12, 0.55],
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: cs.surfaceContainer,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(16),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 8,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius: AppTheme.radiusFull,
                  ),
                ),
              ),
              // Temporal filters (always visible)
              const TemporalPageView(),
              // Advanced filters (visible when expanded)
              if (_loaded)
                AdvancedFilters(
                  accounts: _accounts,
                  topCategories: _topCategories,
                  currencies: _currencies,
                ),
            ],
          ),
        );
      },
    );
  }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `cd /Volumes/rusty-drive/projects/pocket-pilot/frontend && flutter analyze lib/src/features/transactions/ui/widgets/filter_sheet.dart`
Expected: No issues found

- [ ] **Step 3: Commit**

```bash
cd /Volumes/rusty-drive/projects/pocket-pilot
git add frontend/lib/src/features/transactions/ui/widgets/filter_sheet.dart
git commit -m "feat(transactions): add FilterSheet DraggableScrollableSheet container"
```

---

### Task 12: Integrate FilterSheet into TransactionsScreen

**Files:**
- Modify: `frontend/lib/src/features/transactions/ui/transactions_screen.dart`

- [ ] **Step 1: Add import**

Add after line 16:

```dart
import 'package:pocket_pilot/src/features/transactions/ui/transaction_filter_view_model.dart';
import 'package:pocket_pilot/src/features/transactions/ui/widgets/filter_sheet.dart';
```

- [ ] **Step 2: Replace the Scaffold body to add Stack with FilterSheet**

Replace the `body:` inside `Scaffold` (lines 26-57) with:

```dart
      body: Consumer<TransactionsViewModel>(
        builder: (context, vm, _) {
          final filterVM = context.watch<TransactionFilterViewModel>();
          final hasFilters = filterVM.resolvedFilter.hasAdvancedFilters ||
              filterVM.activePageIndex != 0 ||
              filterVM.quickSelection != QuickRange.d30;

          return Stack(
            children: [
              Column(
                children: [
                  if (vm.isSyncing && !vm.isLoading)
                    LinearProgressIndicator(
                      color: Theme.of(context).colorScheme.primary,
                      backgroundColor: Theme.of(
                        context,
                      ).colorScheme.surfaceContainer,
                      minHeight: 2,
                    ),
                  Expanded(
                    child: PpScreenState(
                      isLoading: vm.isLoading,
                      errorMessage: vm.transactions.isEmpty
                          ? vm.errorMessage
                          : null,
                      isEmpty: vm.transactions.isEmpty,
                      emptyIcon: hasFilters
                          ? Icons.filter_list_off_rounded
                          : Icons.receipt_long_outlined,
                      emptyLabel: hasFilters
                          ? 'No hay transacciones con estos filtros'
                          : 'No hay transacciones aún',
                      emptySubLabel: hasFilters
                          ? 'Intenta cambiar los filtros'
                          : 'Presiona + para registrar una',
                      onRefresh: vm.refresh,
                      child: _TransactionList(
                        transactions: vm.transactions,
                        vm: vm,
                      ),
                    ),
                  ),
                ],
              ),
              const FilterSheet(),
            ],
          );
        },
      ),
```

- [ ] **Step 3: Update list bottom padding to account for filter sheet**

In the `_TransactionList` widget, change the ListView padding (line 151) from:

```dart
padding: const EdgeInsets.only(bottom: 96),
```

to:

```dart
padding: const EdgeInsets.only(bottom: 160),
```

This gives enough room for the collapsed filter sheet + FAB.

- [ ] **Step 4: Verify the app compiles**

Run: `cd /Volumes/rusty-drive/projects/pocket-pilot/frontend && flutter analyze lib/src/features/transactions/ui/transactions_screen.dart`
Expected: No issues found

- [ ] **Step 5: Run the full app to verify**

Run: `cd /Volumes/rusty-drive/projects/pocket-pilot/frontend && flutter build apk --debug 2>&1 | tail -5`
Expected: BUILD SUCCESSFUL

- [ ] **Step 6: Run all tests**

Run: `cd /Volumes/rusty-drive/projects/pocket-pilot/frontend && flutter test`
Expected: All tests pass

- [ ] **Step 7: Commit**

```bash
cd /Volumes/rusty-drive/projects/pocket-pilot
git add frontend/lib/src/features/transactions/ui/transactions_screen.dart
git commit -m "feat(transactions): integrate FilterSheet into TransactionsScreen with filtered empty state"
```

---

### Task 13: Journal entry

**Files:**
- Modify: `docs/context/.journal.md`

- [ ] **Step 1: Add journal entry**

Append to the journal file:

```markdown
## 2026-03-29 — Transaction Filters

- Added `TransactionFilter` value object for immutable filter state
- Added `TransactionFilterViewModel` (ChangeNotifier) for filter sheet UI state
- Modified `TransactionsViewModel` to listen to filter changes and re-query
- Modified `TransactionLocalStore` with `queryRowsFiltered()` for dynamic SQL WHERE
- Modified `TransactionRepository.getTransactions()` to accept optional filter
- Updated `TransactionsRouteScope` to use `MultiProvider` with both ViewModels
- Added `FilterSheet` (persistent `DraggableScrollableSheet`) with:
  - `TemporalPageView`: Quick (7D/30D/6M/1Y), Period (dropdown + arrows), Custom (date pickers)
  - `AdvancedFilters`: Account, Type, Status, Currency dropdowns + Category multi-select chips
  - `CategoryMultiPicker`: Full-screen multi-select category picker
- Added migration `002.sql` with date index, bumped DB version to 2
- Added filtered empty state ("No hay transacciones con estos filtros")
```

- [ ] **Step 2: Commit**

```bash
cd /Volumes/rusty-drive/projects/pocket-pilot
git add docs/context/.journal.md
git commit -m "docs: log transaction filters implementation in journal"
```
