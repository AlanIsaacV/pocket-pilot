# Statistics Tab — Historical Category Analytics Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a new "Estadísticas" tab inside `DashboardScreen` that lets the user inspect per-category historical spending/income over 3/6/12 months, drill into a category for a bar chart + budget integration + month's transactions, and seed a new budget from the observed average.

**Architecture:** New read-only `features/statistics/` module in 3 layers (data/domain/ui), derived from already-synced data. No remote service, no outbox, no sync handler. Two small additive changes to the Budgets feature: a per-category lookup and pre-fill of `BudgetFormScreen` via `go_router` query params. `DashboardScreen` is refactored to host a content `TabBar` with `DashboardSummaryTab` (existing widgets) and `StatisticsTab` (new).

**Tech Stack:** Flutter (Dart, sqflite, Provider, go_router), `fl_chart` (new), `BudgetLocalStore.computeSpentCents` (existing, re-used).

**Spec:** `docs/superpowers/specs/2026-04-17-statistics-tab-design.md`

---

## File Structure

| File | Action | Responsibility |
|---|---|---|
| `frontend/pubspec.yaml` | Modify | Add `fl_chart` dependency |
| `frontend/lib/src/features/budgets/data/budget_local_store.dart` | Modify | Add `findByCategory(categoryId)` |
| `frontend/lib/src/features/budgets/ui/budget_form_screen.dart` | Modify | Accept optional `initialCategoryId` / `initialLimitCents` / `initialCurrencyCode` named params and pre-fill form when `budget == null` |
| `frontend/lib/src/ui/router.dart` | Modify | Read `categoryId`/`suggested`/`currency` query params on `/accounts/budgets/new`; add `/dashboard/statistics/category/:categoryId` route |
| `frontend/lib/src/features/statistics/domain/trend.dart` | Create | `Trend` enum + `kTrendFlatThresholdRatio` constant |
| `frontend/lib/src/features/statistics/domain/category_series_dto.dart` | Create | Per-category aggregate DTO |
| `frontend/lib/src/features/statistics/domain/monthly_point_dto.dart` | Create | `{yearMonth, amountCents}` DTO |
| `frontend/lib/src/features/statistics/domain/category_history_dto.dart` | Create | `{summary, points, budget}` DTO |
| `frontend/lib/src/features/statistics/domain/window_math.dart` | Create | Pure window bound helpers (windowStart/End/Mid, currentYm) |
| `frontend/lib/src/features/statistics/data/statistics_local_store.dart` | Create | Raw SQL: `getCategorySeries` + `getMonthlySeries` |
| `frontend/lib/src/features/statistics/data/statistics_repository.dart` | Create | Orchestrator: sign-flip, trend, avg, zero-fill, budget lookup, transactions-for-month |
| `frontend/lib/src/features/statistics/ui/statistics_view_model.dart` | Create | `ChangeNotifier` with window + reactivity to `DashboardFilterViewModel` |
| `frontend/lib/src/features/statistics/ui/widgets/time_window_chips.dart` | Create | `SegmentedButton` for `3m/6m/12m` |
| `frontend/lib/src/features/statistics/ui/widgets/category_list_row.dart` | Create | Single category row for the list tab |
| `frontend/lib/src/features/statistics/ui/widgets/stat_delta_row.dart` | Create | Promedio + Este mes + delta% |
| `frontend/lib/src/features/statistics/ui/widgets/category_monthly_bar_chart.dart` | Create | `fl_chart` BarChart with optional budget line |
| `frontend/lib/src/features/statistics/ui/statistics_tab.dart` | Create | List view (tab body) |
| `frontend/lib/src/features/statistics/ui/category_history_screen.dart` | Create | Detail push-navigated screen |
| `frontend/lib/src/features/dashboard/ui/dashboard_route_scope.dart` | Modify | Provide `StatisticsViewModel` |
| `frontend/lib/src/ui/screens/dashboard/dashboard_screen.dart` | Modify | Host `TabBar` (Resumen / Estadísticas); extract current body into `DashboardSummaryTab` |
| `frontend/test/statistics_window_math_test.dart` | Create | Pure unit tests for window bounds |
| `frontend/test/statistics_repository_test.dart` | Create | Repository tests with fake local store |
| `frontend/test/statistics_view_model_test.dart` | Create | ViewModel reactivity tests |
| `frontend/test/statistics_category_list_row_test.dart` | Create | Widget test for list row |
| `frontend/test/statistics_stat_delta_row_test.dart` | Create | Widget test for stat row |
| `frontend/test/statistics_tab_smoke_test.dart` | Create | Smoke test: data / empty / error |
| `frontend/test/budget_form_prefill_test.dart` | Create | `BudgetFormScreen` pre-fill via params |
| `docs/context/.journal.md` | Modify | Session log entry |

---

### Task 1: Add fl_chart Dependency

**Files:**
- Modify: `frontend/pubspec.yaml`

- [ ] **Step 1: Add dependency**

Open `frontend/pubspec.yaml`. Under `dependencies:` (near other third-party packages like `google_fonts`), insert:

```yaml
  # --- Gráficas ---
  # fl_chart: librería declarativa de Flutter para gráficas (barras, líneas, pie).
  # Usada en la tab de Estadísticas del dashboard.
  fl_chart: ^0.69.0
```

- [ ] **Step 2: Install**

Run from `frontend/`:

```bash
flutter pub get
```

Expected: no error; `pubspec.lock` updated.

- [ ] **Step 3: Commit**

```bash
git add frontend/pubspec.yaml frontend/pubspec.lock
git commit -m "chore(front-statistics): add fl_chart dependency"
```

---

### Task 2: Add `BudgetLocalStore.findByCategory`

This is Query 4 from the spec. Strict additive change — no migration impact.

**Files:**
- Modify: `frontend/lib/src/features/budgets/data/budget_local_store.dart`

- [ ] **Step 1: Add the method**

Open `frontend/lib/src/features/budgets/data/budget_local_store.dart`. After the existing `queryRows()` method (around line 18), add:

```dart
  /// Returns the row for the budget owning [categoryId], or `null` when
  /// none exists (the table has `UNIQUE(category_id)` so at most one).
  Future<Map<String, dynamic>?> findByCategory(String categoryId) async {
    final db = await _db.database;
    final rows = await db.query(
      'budgets',
      where: 'category_id = ? AND deleted_at IS NULL',
      whereArgs: [categoryId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first;
  }
```

- [ ] **Step 2: Verify the feature still compiles**

Run from `frontend/`:

```bash
flutter analyze lib/src/features/budgets
```

Expected: `No issues found!` (or unchanged from the baseline).

- [ ] **Step 3: Commit**

```bash
git add frontend/lib/src/features/budgets/data/budget_local_store.dart
git commit -m "feat(front-budget): add findByCategory lookup"
```

---

### Task 3: `BudgetFormScreen` Pre-fill Via Route Params

This is the second Budgets cross-feature deliverable (spec §"Cross-feature deliverables (Budgets)").

**Files:**
- Modify: `frontend/lib/src/features/budgets/ui/budget_form_screen.dart`
- Modify: `frontend/lib/src/ui/router.dart`
- Test: `frontend/test/budget_form_prefill_test.dart`

- [ ] **Step 1: Write the failing test**

Create `frontend/test/budget_form_prefill_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:pocket_pilot/src/core/db/database_helper.dart';
import 'package:pocket_pilot/src/features/budgets/ui/budget_form_screen.dart';

void main() {
  testWidgets(
    'BudgetFormScreen pre-fills limit when initialLimitCents is provided',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Provider<DatabaseHelper>(
            create: (_) => DatabaseHelper(),
            child: const BudgetFormScreen(
              initialCategoryId: 'cat-1',
              initialLimitCents: 450000,
              initialCurrencyCode: 'MXN',
            ),
          ),
        ),
      );

      // Let the post-frame callback run.
      await tester.pump();

      final limitField = find.byType(TextFormField).first;
      final controller =
          (tester.widget(limitField) as TextFormField).controller!;
      expect(controller.text, '4500');
    },
  );
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run from `frontend/`:

```bash
flutter test test/budget_form_prefill_test.dart
```

Expected: FAIL — constructor does not accept `initialCategoryId`/`initialLimitCents`/`initialCurrencyCode`.

- [ ] **Step 3: Extend the `BudgetFormScreen` constructor**

Open `frontend/lib/src/features/budgets/ui/budget_form_screen.dart`. Replace the top of the class (the fields + constructor around lines 26-35) with:

```dart
class BudgetFormScreen extends StatefulWidget {
  final BudgetModel? budget;
  final String categoryRoute;
  final String? initialCategoryId;
  final int? initialLimitCents;
  final String? initialCurrencyCode;

  const BudgetFormScreen({
    this.budget,
    this.categoryRoute = '/accounts/budgets/new/category',
    this.initialCategoryId,
    this.initialLimitCents,
    this.initialCurrencyCode,
    super.key,
  });

  @override
  State<BudgetFormScreen> createState() => _BudgetFormScreenState();
}
```

- [ ] **Step 4: Pre-fill form fields when creating a new budget**

In `_BudgetFormScreenState.initState()` (around line 56), replace the body with:

```dart
  @override
  void initState() {
    super.initState();
    final budget = widget.budget;
    if (budget != null) {
      _limitController.text = _formatInitial(budget.limitAmountCents / 100);
      _selectedCategoryId = budget.categoryId;
      _selectedCurrencyCode = budget.currencyCode;
      _selectedPeriod = budget.period;
    } else {
      // New-budget pre-fill via route params (e.g. from Statistics).
      if (widget.initialLimitCents != null && widget.initialLimitCents! > 0) {
        _limitController.text =
            _formatInitial(widget.initialLimitCents! / 100);
      }
      if (widget.initialCategoryId != null) {
        _selectedCategoryId = widget.initialCategoryId;
      }
      if (widget.initialCurrencyCode != null) {
        _selectedCurrencyCode = widget.initialCurrencyCode!;
      }
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadCurrencyOptions();
      if (_selectedCategoryId != null) _loadSelectedCategory();
    });
  }
```

- [ ] **Step 5: Wire router query params into the form**

Open `frontend/lib/src/ui/router.dart`. Replace the `budgets/new` route builder (around line 287-289) with:

```dart
              GoRoute(
                path: 'budgets/new',
                builder: (context, state) {
                  final q = state.uri.queryParameters;
                  final categoryId = q['categoryId'];
                  final suggested = int.tryParse(q['suggested'] ?? '');
                  final currency = q['currency'];
                  return AccountsRouteScope(
                    child: BudgetFormScreen(
                      initialCategoryId: categoryId,
                      initialLimitCents: (suggested != null && suggested > 0)
                          ? suggested
                          : null,
                      initialCurrencyCode: currency,
                    ),
                  );
                },
                routes: [
                  GoRoute(
                    path: 'category',
                    builder: (context, state) {
                      final extra = state.extra as Map<String, dynamic>?;
                      final db = DatabaseHelper();
                      return Provider<CategoryLocalStore>(
                        create: (_) => CategoryLocalStore(db: db),
                        child: CategoryPickerScreen(
                          type: extra?['type'] as String? ?? 'expense',
                        ),
                      );
                    },
                  ),
                ],
              ),
```

- [ ] **Step 6: Run the test to verify it passes**

Run from `frontend/`:

```bash
flutter test test/budget_form_prefill_test.dart
```

Expected: PASS.

- [ ] **Step 7: Verify no regression in router-related tests**

Run from `frontend/`:

```bash
flutter test test/router_single_root_shell_test.dart
```

Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add frontend/lib/src/features/budgets/ui/budget_form_screen.dart \
         frontend/lib/src/ui/router.dart \
         frontend/test/budget_form_prefill_test.dart
git commit -m "feat(front-budget): pre-fill form via route query params"
```

---

### Task 4: Statistics Domain — Trend Enum and Threshold Constant

**Files:**
- Create: `frontend/lib/src/features/statistics/domain/trend.dart`

- [ ] **Step 1: Create the file**

```dart
// features/statistics/domain/trend.dart
//
// Trend signal for historical category aggregates. Shared between the
// list row (arrow chip) and the detail stat row (neutral-delta color).

/// Relative delta below this ratio counts as "flat" for trend and for
/// neutral-delta coloring. Keeping both in the same constant ensures
/// the arrow chip on the list row and the delta color in the detail
/// screen never disagree.
const double kTrendFlatThresholdRatio = 0.05;

enum Trend { up, down, flat }

/// Computes a trend from two halves of a window.
///
/// - Returns `Trend.flat` if either half is zero (insufficient signal)
///   or if the relative difference is below [kTrendFlatThresholdRatio].
/// - Uses the first-half total as the denominator when non-zero.
Trend computeTrend({
  required int firstHalfCents,
  required int secondHalfCents,
}) {
  if (firstHalfCents == 0 || secondHalfCents == 0) return Trend.flat;
  final diff = secondHalfCents - firstHalfCents;
  final ratio = diff.abs() / firstHalfCents.abs();
  if (ratio < kTrendFlatThresholdRatio) return Trend.flat;
  return diff > 0 ? Trend.up : Trend.down;
}
```

- [ ] **Step 2: Commit**

```bash
git add frontend/lib/src/features/statistics/domain/trend.dart
git commit -m "feat(front-statistics): add Trend enum and threshold constant"
```

---

### Task 5: Statistics Domain — DTOs

**Files:**
- Create: `frontend/lib/src/features/statistics/domain/category_series_dto.dart`
- Create: `frontend/lib/src/features/statistics/domain/monthly_point_dto.dart`
- Create: `frontend/lib/src/features/statistics/domain/category_history_dto.dart`

- [ ] **Step 1: Create `category_series_dto.dart`**

```dart
// features/statistics/domain/category_series_dto.dart
import 'package:pocket_pilot/src/features/statistics/domain/trend.dart';

class CategorySeriesDTO {
  final String categoryId;
  final String name;
  final String color;          // hex (e.g. "#A6E3A1")
  final String icon;
  final String kind;           // 'expense' | 'income'
  final String currencyCode;
  final int totalCents;        // already sign-flipped for income
  final int avgMonthlyCents;   // totalCents ~/ N
  final int currentMonthCents; // already sign-flipped for income
  final Trend trend;

  const CategorySeriesDTO({
    required this.categoryId,
    required this.name,
    required this.color,
    required this.icon,
    required this.kind,
    required this.currencyCode,
    required this.totalCents,
    required this.avgMonthlyCents,
    required this.currentMonthCents,
    required this.trend,
  });
}
```

- [ ] **Step 2: Create `monthly_point_dto.dart`**

```dart
// features/statistics/domain/monthly_point_dto.dart
class MonthlyPointDTO {
  final String yearMonth; // 'YYYY-MM'
  final int amountCents;  // already sign-flipped for income

  const MonthlyPointDTO({
    required this.yearMonth,
    required this.amountCents,
  });
}
```

- [ ] **Step 3: Create `category_history_dto.dart`**

```dart
// features/statistics/domain/category_history_dto.dart
import 'package:pocket_pilot/src/features/budgets/domain/budget_status.dart';
import 'package:pocket_pilot/src/features/statistics/domain/category_series_dto.dart';
import 'package:pocket_pilot/src/features/statistics/domain/monthly_point_dto.dart';

class CategoryHistoryDTO {
  final CategorySeriesDTO summary;
  final List<MonthlyPointDTO> points; // length == N, zero-filled
  final BudgetStatus? budget;         // null if no budget or currency mismatch

  const CategoryHistoryDTO({
    required this.summary,
    required this.points,
    this.budget,
  });
}
```

- [ ] **Step 4: Verify compilation**

Run from `frontend/`:

```bash
flutter analyze lib/src/features/statistics
```

Expected: `No issues found!`

- [ ] **Step 5: Commit**

```bash
git add frontend/lib/src/features/statistics/domain/
git commit -m "feat(front-statistics): add domain DTOs"
```

---

### Task 6: Statistics Domain — Window Math Helpers

Pure functions only — exactly the pattern of `test/schedule_date_math_test.dart`.

**Files:**
- Create: `frontend/lib/src/features/statistics/domain/window_math.dart`
- Test: `frontend/test/statistics_window_math_test.dart`

- [ ] **Step 1: Write the failing tests**

Create `frontend/test/statistics_window_math_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';

import 'package:pocket_pilot/src/features/statistics/domain/window_math.dart';

void main() {
  group('StatisticsWindow.fromNow', () {
    test('6-month window ending in April 2026', () {
      final w = StatisticsWindow.fromNow(
        months: 6,
        now: DateTime.utc(2026, 4, 17),
      );
      expect(w.months, 6);
      expect(w.windowStart, '2025-11-01'); // N-1 = 5 months back from April
      expect(w.windowEnd, '2026-05-01');   // first day of next month
      expect(w.currentYm, '2026-04');
      // windowMid = start of month at index N~/2 = 3 from windowStart
      expect(w.windowMid, '2026-02-01');
    });

    test('3-month window ending in April 2026', () {
      final w = StatisticsWindow.fromNow(
        months: 3,
        now: DateTime.utc(2026, 4, 1),
      );
      expect(w.windowStart, '2026-02-01');
      expect(w.windowEnd, '2026-05-01');
      expect(w.currentYm, '2026-04');
      expect(w.windowMid, '2026-03-01'); // N~/2 = 1
    });

    test('12-month window crossing years', () {
      final w = StatisticsWindow.fromNow(
        months: 12,
        now: DateTime.utc(2026, 4, 17),
      );
      expect(w.windowStart, '2025-05-01'); // 11 months back
      expect(w.windowEnd, '2026-05-01');
      expect(w.currentYm, '2026-04');
      expect(w.windowMid, '2025-11-01'); // index 6
    });

    test('month sequence is contiguous and length N', () {
      final w = StatisticsWindow.fromNow(
        months: 6,
        now: DateTime.utc(2026, 4, 17),
      );
      expect(w.monthsInWindow, [
        '2025-11',
        '2025-12',
        '2026-01',
        '2026-02',
        '2026-03',
        '2026-04',
      ]);
    });
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run from `frontend/`:

```bash
flutter test test/statistics_window_math_test.dart
```

Expected: FAIL — `StatisticsWindow` not found.

- [ ] **Step 3: Implement `window_math.dart`**

Create `frontend/lib/src/features/statistics/domain/window_math.dart`:

```dart
// features/statistics/domain/window_math.dart
//
// Pure time-window bounds for the Statistics tab. All dates are
// 'YYYY-MM-DD' strings so they compare lexicographically against the
// SQLite `date` column (same contract as `TransactionFilter`).

class StatisticsWindow {
  final int months;        // 3, 6, or 12
  final String windowStart; // inclusive, first day of oldest month
  final String windowEnd;   // exclusive, first day of month AFTER current
  final String windowMid;   // boundary between first/second trend halves
  final String currentYm;   // 'YYYY-MM' of `now`
  final List<String> monthsInWindow; // N contiguous 'YYYY-MM' strings

  const StatisticsWindow._({
    required this.months,
    required this.windowStart,
    required this.windowEnd,
    required this.windowMid,
    required this.currentYm,
    required this.monthsInWindow,
  });

  factory StatisticsWindow.fromNow({
    required int months,
    required DateTime now,
  }) {
    assert(months == 3 || months == 6 || months == 12);
    final y = now.year;
    final m = now.month;

    // First day of current month.
    final startOfCurrent = DateTime.utc(y, m, 1);
    // First day of next month (exclusive upper bound).
    final startOfNext = DateTime.utc(y, m + 1, 1);
    // First day of the oldest month in the window.
    final startOfOldest = DateTime.utc(y, m - (months - 1), 1);
    // Mid boundary: start of month at offset N~/2 from oldest.
    final startOfMid = DateTime.utc(y, m - (months - 1) + (months ~/ 2), 1);

    final list = <String>[];
    for (var i = 0; i < months; i++) {
      final d = DateTime.utc(y, m - (months - 1) + i, 1);
      list.add(_fmtYm(d));
    }

    return StatisticsWindow._(
      months: months,
      windowStart: _fmtDate(startOfOldest),
      windowEnd: _fmtDate(startOfNext),
      windowMid: _fmtDate(startOfMid),
      currentYm: _fmtYm(startOfCurrent),
      monthsInWindow: List.unmodifiable(list),
    );
  }

  static String _fmtDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}'
      '-${d.month.toString().padLeft(2, '0')}'
      '-${d.day.toString().padLeft(2, '0')}';

  static String _fmtYm(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}'
      '-${d.month.toString().padLeft(2, '0')}';
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run from `frontend/`:

```bash
flutter test test/statistics_window_math_test.dart
```

Expected: PASS (all 4 tests).

- [ ] **Step 5: Commit**

```bash
git add frontend/lib/src/features/statistics/domain/window_math.dart \
         frontend/test/statistics_window_math_test.dart
git commit -m "feat(front-statistics): add window bounds helpers"
```

---

### Task 7: Statistics Data — Local Store

Raw SQL only. Follows `DashboardLocalStore` conventions (no test at this level — verified indirectly via the repository tests in Task 8).

**Files:**
- Create: `frontend/lib/src/features/statistics/data/statistics_local_store.dart`

- [ ] **Step 1: Create the file**

```dart
// features/statistics/data/statistics_local_store.dart
//
// Read-only SQL for historical category aggregates.
// Mirrors the netting rules in BudgetLocalStore.computeSpentCents and
// the YM grouping in DashboardLocalStore.getMonthlySpendByCategory.
// MSI proration is intentionally NOT applied: a transaction is
// attributed entirely to its purchase-month bar.

import 'package:pocket_pilot/src/core/db/database_helper.dart';

class StatisticsLocalStore {
  final DatabaseHelper _db;

  StatisticsLocalStore({required DatabaseHelper db}) : _db = db;

  /// Summary per category across the window, with embedded partial
  /// aggregates to feed current-month and trend calculations without
  /// extra round-trips. Income nets negative (see spec §Netting
  /// Semantics); the repository flips the sign for income categories
  /// before exposing domain values.
  Future<List<Map<String, dynamic>>> getCategorySeries({
    required String currencyCode,
    required String windowStart,
    required String windowEnd,
    required String windowMid,
    required String currentYm,
  }) async {
    final db = await _db.database;
    return db.rawQuery(
      '''
      SELECT
        c.id AS category_id,
        c.name, c.color, c.icon, c.kind,
        COALESCE(SUM(CASE WHEN t.type = 'expense' THEN  t.amount_cents
                          WHEN t.type = 'income'  THEN -t.amount_cents
                          ELSE 0 END), 0) AS total_cents,
        COALESCE(SUM(CASE WHEN strftime('%Y-%m', t.date) = ? THEN
                               CASE WHEN t.type = 'expense' THEN  t.amount_cents
                                    WHEN t.type = 'income'  THEN -t.amount_cents
                                    ELSE 0 END
                          END), 0) AS current_month_cents,
        COALESCE(SUM(CASE WHEN t.date <  ? THEN
                               CASE WHEN t.type = 'expense' THEN  t.amount_cents
                                    WHEN t.type = 'income'  THEN -t.amount_cents
                                    ELSE 0 END
                          END), 0) AS first_half_cents,
        COALESCE(SUM(CASE WHEN t.date >= ? THEN
                               CASE WHEN t.type = 'expense' THEN  t.amount_cents
                                    WHEN t.type = 'income'  THEN -t.amount_cents
                                    ELSE 0 END
                          END), 0) AS second_half_cents
      FROM categories c
      LEFT JOIN transactions t
        ON t.category_id    = c.id
        AND t.currency_code = ?
        AND t.date         >= ?
        AND t.date         <  ?
        AND t.deleted_at   IS NULL
        AND t.type         IN ('expense', 'income')
      WHERE c.deleted_at IS NULL
      GROUP BY c.id
      HAVING ABS(total_cents) > 0
      ORDER BY ABS(total_cents) DESC
      ''',
      [
        currentYm,
        windowMid,
        windowMid,
        currencyCode,
        windowStart,
        windowEnd,
      ],
    );
  }

  /// Monthly series for a single category. Returns only months that
  /// have activity; the repository zero-fills missing months.
  Future<List<Map<String, dynamic>>> getMonthlySeries({
    required String categoryId,
    required String currencyCode,
    required String windowStart,
    required String windowEnd,
  }) async {
    final db = await _db.database;
    return db.rawQuery(
      '''
      SELECT
        strftime('%Y-%m', t.date) AS ym,
        COALESCE(SUM(CASE WHEN t.type = 'expense' THEN  t.amount_cents
                          WHEN t.type = 'income'  THEN -t.amount_cents
                          ELSE 0 END), 0) AS amount_cents
      FROM transactions t
      WHERE t.category_id  = ?
        AND t.currency_code = ?
        AND t.date         >= ?
        AND t.date         <  ?
        AND t.deleted_at   IS NULL
        AND t.type         IN ('expense', 'income')
      GROUP BY ym
      ORDER BY ym
      ''',
      [categoryId, currencyCode, windowStart, windowEnd],
    );
  }
}
```

- [ ] **Step 2: Verify compilation**

Run from `frontend/`:

```bash
flutter analyze lib/src/features/statistics/data
```

Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
git add frontend/lib/src/features/statistics/data/statistics_local_store.dart
git commit -m "feat(front-statistics): add local store SQL"
```

---

### Task 8: Statistics Data — Repository

**Files:**
- Create: `frontend/lib/src/features/statistics/data/statistics_repository.dart`
- Test: `frontend/test/statistics_repository_test.dart`

- [ ] **Step 1: Write the failing tests**

Create `frontend/test/statistics_repository_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';

import 'package:pocket_pilot/src/core/db/database_helper.dart';
import 'package:pocket_pilot/src/features/budgets/data/budget_local_store.dart';
import 'package:pocket_pilot/src/features/statistics/data/statistics_local_store.dart';
import 'package:pocket_pilot/src/features/statistics/data/statistics_repository.dart';
import 'package:pocket_pilot/src/features/statistics/domain/trend.dart';

void main() {
  group('StatisticsRepository.getSeriesList', () {
    test('expense category: avg = total / N, trend flat', () async {
      final repo = StatisticsRepository(
        local: _FakeLocalStore(
          categorySeries: const [
            {
              'category_id': 'c1',
              'name': 'Comida',
              'color': '#FF0000',
              'icon': 'restaurant',
              'kind': 'expense',
              'total_cents': 60000,         // 6 months * 10000
              'current_month_cents': 10000,
              'first_half_cents': 30000,
              'second_half_cents': 30000,
            },
          ],
        ),
        budgetLocal: _FakeBudgetLocalStore(),
      );

      final list = await repo.getSeriesList(
        currencyCode: 'MXN',
        windowStart: '2025-11-01',
        windowEnd: '2026-05-01',
        windowMid: '2026-02-01',
        currentYm: '2026-04',
        months: 6,
      );

      expect(list, hasLength(1));
      expect(list[0].categoryId, 'c1');
      expect(list[0].totalCents, 60000);
      expect(list[0].avgMonthlyCents, 10000);
      expect(list[0].currentMonthCents, 10000);
      expect(list[0].trend, Trend.flat);
    });

    test('income category: sign is flipped to positive', () async {
      final repo = StatisticsRepository(
        local: _FakeLocalStore(
          categorySeries: const [
            {
              'category_id': 'c2',
              'name': 'Salario',
              'color': '#00FF00',
              'icon': 'work',
              'kind': 'income',
              // Income subtracts in SQL, so totals come back negative.
              'total_cents': -120000,
              'current_month_cents': -20000,
              'first_half_cents': -60000,
              'second_half_cents': -60000,
            },
          ],
        ),
        budgetLocal: _FakeBudgetLocalStore(),
      );

      final list = await repo.getSeriesList(
        currencyCode: 'MXN',
        windowStart: '2025-11-01',
        windowEnd: '2026-05-01',
        windowMid: '2026-02-01',
        currentYm: '2026-04',
        months: 6,
      );

      expect(list[0].totalCents, 120000);
      expect(list[0].currentMonthCents, 20000);
      expect(list[0].avgMonthlyCents, 20000);
      expect(list[0].kind, 'income');
    });

    test('trend up when second half > first half by > threshold', () async {
      final repo = StatisticsRepository(
        local: _FakeLocalStore(
          categorySeries: const [
            {
              'category_id': 'c3',
              'name': 'Ocio',
              'color': '#A0A0A0',
              'icon': 'movie',
              'kind': 'expense',
              'total_cents': 100,
              'current_month_cents': 0,
              'first_half_cents': 40,
              'second_half_cents': 60, // +50% over first half
            },
          ],
        ),
        budgetLocal: _FakeBudgetLocalStore(),
      );

      final list = await repo.getSeriesList(
        currencyCode: 'MXN',
        windowStart: '2025-11-01',
        windowEnd: '2026-05-01',
        windowMid: '2026-02-01',
        currentYm: '2026-04',
        months: 6,
      );

      expect(list[0].trend, Trend.up);
    });
  });

  group('StatisticsRepository.getHistory', () {
    test('zero-fills missing months in order', () async {
      final repo = StatisticsRepository(
        local: _FakeLocalStore(
          monthlySeries: const [
            {'ym': '2026-01', 'amount_cents': 5000},
            {'ym': '2026-03', 'amount_cents': 7000},
          ],
          categorySeries: const [
            {
              'category_id': 'c1',
              'name': 'Comida',
              'color': '#FF0000',
              'icon': 'restaurant',
              'kind': 'expense',
              'total_cents': 12000,
              'current_month_cents': 0,
              'first_half_cents': 0,
              'second_half_cents': 12000,
            },
          ],
        ),
        budgetLocal: _FakeBudgetLocalStore(),
      );

      final history = await repo.getHistory(
        categoryId: 'c1',
        currencyCode: 'MXN',
        months: 3,
        now: DateTime.utc(2026, 3, 15),
      );

      expect(history.points.map((p) => p.yearMonth).toList(), [
        '2026-01',
        '2026-02',
        '2026-03',
      ]);
      expect(history.points.map((p) => p.amountCents).toList(), [
        5000,
        0,
        7000,
      ]);
    });

    test('budget with non-matching currency resolves to null', () async {
      final repo = StatisticsRepository(
        local: _FakeLocalStore(
          categorySeries: const [
            {
              'category_id': 'c1',
              'name': 'Comida',
              'color': '#FF0000',
              'icon': 'restaurant',
              'kind': 'expense',
              'total_cents': 1,
              'current_month_cents': 0,
              'first_half_cents': 0,
              'second_half_cents': 1,
            },
          ],
        ),
        budgetLocal: _FakeBudgetLocalStore(
          budgetRow: const {
            'id': 'b1',
            'category_id': 'c1',
            'limit_amount_cents': 10000,
            'currency_code': 'USD', // mismatch
            'period': 'MONTHLY',
            'created_at': '2026-01-01T00:00:00Z',
            'updated_at': '2026-01-01T00:00:00Z',
            'deleted_at': null,
          },
        ),
      );

      final history = await repo.getHistory(
        categoryId: 'c1',
        currencyCode: 'MXN',
        months: 3,
        now: DateTime.utc(2026, 4, 1),
      );

      expect(history.budget, isNull);
    });

    test('budget lookup failure leaves budget null (logged)', () async {
      final repo = StatisticsRepository(
        local: _FakeLocalStore(
          categorySeries: const [
            {
              'category_id': 'c1',
              'name': 'Comida',
              'color': '#FF0000',
              'icon': 'restaurant',
              'kind': 'expense',
              'total_cents': 1,
              'current_month_cents': 0,
              'first_half_cents': 0,
              'second_half_cents': 1,
            },
          ],
        ),
        budgetLocal: _FakeBudgetLocalStore(throwOnFind: true),
      );

      final history = await repo.getHistory(
        categoryId: 'c1',
        currencyCode: 'MXN',
        months: 3,
        now: DateTime.utc(2026, 4, 1),
      );

      expect(history.budget, isNull);
    });
  });
}

// ---- fakes ---------------------------------------------------------

class _FakeLocalStore extends StatisticsLocalStore {
  final List<Map<String, dynamic>> categorySeries;
  final List<Map<String, dynamic>> monthlySeries;

  _FakeLocalStore({
    this.categorySeries = const [],
    this.monthlySeries = const [],
  }) : super(db: DatabaseHelper());

  @override
  Future<List<Map<String, dynamic>>> getCategorySeries({
    required String currencyCode,
    required String windowStart,
    required String windowEnd,
    required String windowMid,
    required String currentYm,
  }) async =>
      categorySeries;

  @override
  Future<List<Map<String, dynamic>>> getMonthlySeries({
    required String categoryId,
    required String currencyCode,
    required String windowStart,
    required String windowEnd,
  }) async =>
      monthlySeries;
}

class _FakeBudgetLocalStore extends BudgetLocalStore {
  final Map<String, dynamic>? budgetRow;
  final bool throwOnFind;

  _FakeBudgetLocalStore({this.budgetRow, this.throwOnFind = false})
      : super(db: DatabaseHelper());

  @override
  Future<Map<String, dynamic>?> findByCategory(String categoryId) async {
    if (throwOnFind) throw StateError('boom');
    return budgetRow;
  }

  @override
  Future<int> computeSpentCents(String categoryId, String period) async => 0;
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run from `frontend/`:

```bash
flutter test test/statistics_repository_test.dart
```

Expected: FAIL — `StatisticsRepository` not found.

- [ ] **Step 3: Implement the repository**

Create `frontend/lib/src/features/statistics/data/statistics_repository.dart`:

```dart
// features/statistics/data/statistics_repository.dart
//
// Orchestrates StatisticsLocalStore + BudgetLocalStore to produce the
// Statistics domain objects. All sign flips, trend computation, avg
// division, and zero-filling live here (not in SQL).

import 'package:flutter/foundation.dart';

import 'package:pocket_pilot/src/features/budgets/data/budget_local_store.dart';
import 'package:pocket_pilot/src/features/budgets/domain/budget.dart';
import 'package:pocket_pilot/src/features/budgets/domain/budget_status.dart';
import 'package:pocket_pilot/src/features/statistics/data/statistics_local_store.dart';
import 'package:pocket_pilot/src/features/statistics/domain/category_history_dto.dart';
import 'package:pocket_pilot/src/features/statistics/domain/category_series_dto.dart';
import 'package:pocket_pilot/src/features/statistics/domain/monthly_point_dto.dart';
import 'package:pocket_pilot/src/features/statistics/domain/trend.dart';
import 'package:pocket_pilot/src/features/statistics/domain/window_math.dart';

class StatisticsRepository {
  final StatisticsLocalStore _local;
  final BudgetLocalStore _budgetLocal;

  StatisticsRepository({
    required StatisticsLocalStore local,
    required BudgetLocalStore budgetLocal,
  })  : _local = local,
        _budgetLocal = budgetLocal;

  /// Returns summary rows for every category with activity in the
  /// window, already sign-flipped for income and annotated with trend.
  Future<List<CategorySeriesDTO>> getSeriesList({
    required String currencyCode,
    required String windowStart,
    required String windowEnd,
    required String windowMid,
    required String currentYm,
    required int months,
  }) async {
    final rows = await _local.getCategorySeries(
      currencyCode: currencyCode,
      windowStart: windowStart,
      windowEnd: windowEnd,
      windowMid: windowMid,
      currentYm: currentYm,
    );
    return rows.map((r) => _toSeries(r, months, currencyCode)).toList();
  }

  Future<CategoryHistoryDTO> getHistory({
    required String categoryId,
    required String currencyCode,
    required int months,
    required DateTime now,
  }) async {
    final window = StatisticsWindow.fromNow(months: months, now: now);

    final seriesRows = await _local.getCategorySeries(
      currencyCode: currencyCode,
      windowStart: window.windowStart,
      windowEnd: window.windowEnd,
      windowMid: window.windowMid,
      currentYm: window.currentYm,
    );
    final summaryRow = seriesRows.firstWhere(
      (r) => r['category_id'] == categoryId,
      orElse: () => <String, dynamic>{},
    );
    // If no activity in the window, fabricate an empty summary so the
    // screen can still render (e.g. user arrived via deep link).
    final summary = summaryRow.isEmpty
        ? _emptySeries(categoryId, currencyCode, months)
        : _toSeries(summaryRow, months, currencyCode);

    final pointRows = await _local.getMonthlySeries(
      categoryId: categoryId,
      currencyCode: currencyCode,
      windowStart: window.windowStart,
      windowEnd: window.windowEnd,
    );
    final byYm = <String, int>{
      for (final r in pointRows)
        r['ym'] as String: _signFlip(_asInt(r['amount_cents']), summary.kind),
    };
    final points = window.monthsInWindow
        .map(
          (ym) => MonthlyPointDTO(
            yearMonth: ym,
            amountCents: byYm[ym] ?? 0,
          ),
        )
        .toList(growable: false);

    final budget = await _loadBudget(categoryId, currencyCode);

    return CategoryHistoryDTO(
      summary: summary,
      points: points,
      budget: budget,
    );
  }

  // ---- helpers -----------------------------------------------------

  CategorySeriesDTO _toSeries(
    Map<String, dynamic> r,
    int months,
    String currencyCode,
  ) {
    final kind = r['kind'] as String;
    final totalSigned = _asInt(r['total_cents']);
    final currentSigned = _asInt(r['current_month_cents']);
    final firstHalfSigned = _asInt(r['first_half_cents']);
    final secondHalfSigned = _asInt(r['second_half_cents']);

    final total = _signFlip(totalSigned, kind);
    final current = _signFlip(currentSigned, kind);
    final first = _signFlip(firstHalfSigned, kind);
    final second = _signFlip(secondHalfSigned, kind);

    return CategorySeriesDTO(
      categoryId: r['category_id'] as String,
      name: r['name'] as String,
      color: (r['color'] as String?) ?? '',
      icon: (r['icon'] as String?) ?? '',
      kind: kind,
      currencyCode: currencyCode,
      totalCents: total,
      avgMonthlyCents: months > 0 ? total ~/ months : 0,
      currentMonthCents: current,
      trend: computeTrend(
        firstHalfCents: first,
        secondHalfCents: second,
      ),
    );
  }

  CategorySeriesDTO _emptySeries(
    String categoryId,
    String currencyCode,
    int months,
  ) =>
      CategorySeriesDTO(
        categoryId: categoryId,
        name: '',
        color: '',
        icon: '',
        kind: 'expense',
        currencyCode: currencyCode,
        totalCents: 0,
        avgMonthlyCents: 0,
        currentMonthCents: 0,
        trend: Trend.flat,
      );

  Future<BudgetStatus?> _loadBudget(
    String categoryId,
    String currencyCode,
  ) async {
    try {
      final row = await _budgetLocal.findByCategory(categoryId);
      if (row == null) return null;
      final budget = BudgetModel.fromMap(row);
      if (budget.currencyCode != currencyCode) return null;
      final spent =
          await _budgetLocal.computeSpentCents(budget.categoryId, budget.period);
      return BudgetStatus(budget: budget, spentAmountCents: spent);
    } catch (e, st) {
      debugPrint('StatisticsRepository: budget lookup failed: $e\n$st');
      return null;
    }
  }

  static int _signFlip(int value, String kind) =>
      kind == 'income' ? -value : value;

  static int _asInt(Object? raw) {
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    if (raw == null) return 0;
    return int.parse(raw.toString());
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run from `frontend/`:

```bash
flutter test test/statistics_repository_test.dart
```

Expected: PASS (all 6 tests).

- [ ] **Step 5: Commit**

```bash
git add frontend/lib/src/features/statistics/data/statistics_repository.dart \
         frontend/test/statistics_repository_test.dart
git commit -m "feat(front-statistics): add repository with trend/avg/zero-fill"
```

---

### Task 9: Statistics ViewModel

**Files:**
- Create: `frontend/lib/src/features/statistics/ui/statistics_view_model.dart`
- Test: `frontend/test/statistics_view_model_test.dart`

- [ ] **Step 1: Write the failing tests**

Create `frontend/test/statistics_view_model_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';

import 'package:pocket_pilot/src/core/db/database_helper.dart';
import 'package:pocket_pilot/src/features/budgets/data/budget_local_store.dart';
import 'package:pocket_pilot/src/features/dashboard/ui/dashboard_filter_view_model.dart';
import 'package:pocket_pilot/src/features/statistics/data/statistics_local_store.dart';
import 'package:pocket_pilot/src/features/statistics/data/statistics_repository.dart';
import 'package:pocket_pilot/src/features/statistics/ui/statistics_view_model.dart';

void main() {
  test('initial load with no currency emits empty list', () async {
    final filter = DashboardFilterViewModel();
    final vm = StatisticsViewModel(
      repository: _FakeRepo(rowsByCurrency: const {}),
      filterViewModel: filter,
      now: () => DateTime.utc(2026, 4, 17),
    );

    await vm.refresh();

    expect(vm.isLoading, false);
    expect(vm.series, isEmpty);
    expect(vm.errorMessage, isNull);
  });

  test('window change triggers reload', () async {
    final filter = DashboardFilterViewModel()..setCurrencyCode('MXN');
    final repo = _FakeRepo(
      rowsByCurrency: {
        'MXN': 1,
      },
    );
    final vm = StatisticsViewModel(
      repository: repo,
      filterViewModel: filter,
      now: () => DateTime.utc(2026, 4, 17),
    );
    await vm.refresh();
    final firstCalls = repo.callsByMonths;

    vm.setWindow(12);
    await Future<void>.delayed(Duration.zero);

    expect(vm.months, 12);
    expect(repo.callsByMonths[12], (firstCalls[12] ?? 0) + 1);
  });

  test('currency change triggers reload', () async {
    final filter = DashboardFilterViewModel()..setCurrencyCode('MXN');
    final repo = _FakeRepo(rowsByCurrency: const {'MXN': 1, 'USD': 1});
    final vm = StatisticsViewModel(
      repository: repo,
      filterViewModel: filter,
      now: () => DateTime.utc(2026, 4, 17),
    );
    await vm.refresh();
    expect(repo.lastCurrency, 'MXN');

    filter.setCurrencyCode('USD');
    await Future<void>.delayed(Duration.zero);

    expect(repo.lastCurrency, 'USD');
  });

  test('repository failure surfaces errorMessage', () async {
    final filter = DashboardFilterViewModel()..setCurrencyCode('MXN');
    final vm = StatisticsViewModel(
      repository: _ThrowingRepo(),
      filterViewModel: filter,
      now: () => DateTime.utc(2026, 4, 17),
    );

    await vm.refresh();

    expect(vm.errorMessage, isNotNull);
    expect(vm.series, isEmpty);
  });
}

class _FakeRepo extends StatisticsRepository {
  final Map<String, int> rowsByCurrency;
  final Map<int, int> callsByMonths = {};
  String? lastCurrency;

  _FakeRepo({required this.rowsByCurrency})
      : super(
          local: StatisticsLocalStore(db: DatabaseHelper()),
          budgetLocal: BudgetLocalStore(db: DatabaseHelper()),
        );

  @override
  Future<List<CategorySeriesDTO>> getSeriesList({
    required String currencyCode,
    required String windowStart,
    required String windowEnd,
    required String windowMid,
    required String currentYm,
    required int months,
  }) async {
    lastCurrency = currencyCode;
    callsByMonths[months] = (callsByMonths[months] ?? 0) + 1;
    final count = rowsByCurrency[currencyCode] ?? 0;
    return List.generate(
      count,
      (i) => CategorySeriesDTO(
        categoryId: 'c$i',
        name: 'Cat $i',
        color: '',
        icon: '',
        kind: 'expense',
        currencyCode: currencyCode,
        totalCents: 100,
        avgMonthlyCents: 100 ~/ months,
        currentMonthCents: 10,
        trend: Trend.flat,
      ),
    );
  }
}

class _ThrowingRepo extends _FakeRepo {
  _ThrowingRepo() : super(rowsByCurrency: const {});

  @override
  Future<List<CategorySeriesDTO>> getSeriesList({
    required String currencyCode,
    required String windowStart,
    required String windowEnd,
    required String windowMid,
    required String currentYm,
    required int months,
  }) async {
    throw StateError('db down');
  }
}
```

Required imports for the test file — add at the top:

```dart
import 'package:pocket_pilot/src/features/statistics/domain/category_series_dto.dart';
import 'package:pocket_pilot/src/features/statistics/domain/trend.dart';
```

- [ ] **Step 2: Run tests to verify they fail**

Run from `frontend/`:

```bash
flutter test test/statistics_view_model_test.dart
```

Expected: FAIL — `StatisticsViewModel` not found.

- [ ] **Step 3: Implement the ViewModel**

Create `frontend/lib/src/features/statistics/ui/statistics_view_model.dart`:

```dart
// features/statistics/ui/statistics_view_model.dart
import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:pocket_pilot/src/features/dashboard/ui/dashboard_filter_view_model.dart';
import 'package:pocket_pilot/src/features/statistics/data/statistics_repository.dart';
import 'package:pocket_pilot/src/features/statistics/domain/category_series_dto.dart';
import 'package:pocket_pilot/src/features/statistics/domain/window_math.dart';

class StatisticsViewModel extends ChangeNotifier {
  final StatisticsRepository _repository;
  final DashboardFilterViewModel _filterVM;
  final DateTime Function() _now;

  int months = 6; // default window
  List<CategorySeriesDTO> series = const [];
  bool isLoading = false;
  String? errorMessage;

  bool _disposed = false;

  StatisticsViewModel({
    required StatisticsRepository repository,
    required DashboardFilterViewModel filterViewModel,
    DateTime Function()? now,
  })  : _repository = repository,
        _filterVM = filterViewModel,
        _now = now ?? DateTime.now {
    _filterVM.addListener(_onFilterChanged);
  }

  void setWindow(int nextMonths) {
    if (nextMonths == months) return;
    assert(nextMonths == 3 || nextMonths == 6 || nextMonths == 12);
    months = nextMonths;
    unawaited(refresh());
  }

  void loadOnAppear() {
    unawaited(refresh());
  }

  Future<void> refresh() async {
    final currency = _filterVM.currencyCode;
    if (currency == null) {
      series = const [];
      errorMessage = null;
      isLoading = false;
      _safeNotify();
      return;
    }

    isLoading = series.isEmpty;
    _safeNotify();

    try {
      final window = StatisticsWindow.fromNow(months: months, now: _now());
      series = await _repository.getSeriesList(
        currencyCode: currency,
        windowStart: window.windowStart,
        windowEnd: window.windowEnd,
        windowMid: window.windowMid,
        currentYm: window.currentYm,
        months: months,
      );
      errorMessage = null;
    } catch (e) {
      series = const [];
      errorMessage = e.toString();
    } finally {
      isLoading = false;
      _safeNotify();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _filterVM.removeListener(_onFilterChanged);
    super.dispose();
  }

  void _onFilterChanged() {
    unawaited(refresh());
  }

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run from `frontend/`:

```bash
flutter test test/statistics_view_model_test.dart
```

Expected: PASS (all 4 tests).

- [ ] **Step 5: Commit**

```bash
git add frontend/lib/src/features/statistics/ui/statistics_view_model.dart \
         frontend/test/statistics_view_model_test.dart
git commit -m "feat(front-statistics): add view model with filter reactivity"
```

---

### Task 10: Widget — Time Window Chips

**Files:**
- Create: `frontend/lib/src/features/statistics/ui/widgets/time_window_chips.dart`

- [ ] **Step 1: Create the widget**

```dart
// features/statistics/ui/widgets/time_window_chips.dart
import 'package:flutter/material.dart';

class TimeWindowChips extends StatelessWidget {
  final int selectedMonths;
  final ValueChanged<int> onChanged;

  const TimeWindowChips({
    super.key,
    required this.selectedMonths,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<int>(
      showSelectedIcon: false,
      segments: const [
        ButtonSegment<int>(value: 3, label: Text('3m')),
        ButtonSegment<int>(value: 6, label: Text('6m')),
        ButtonSegment<int>(value: 12, label: Text('12m')),
      ],
      selected: {selectedMonths},
      onSelectionChanged: (s) => onChanged(s.first),
    );
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add frontend/lib/src/features/statistics/ui/widgets/time_window_chips.dart
git commit -m "feat(front-statistics): add time window chips"
```

---

### Task 11: Widget — Category List Row

**Files:**
- Create: `frontend/lib/src/features/statistics/ui/widgets/category_list_row.dart`
- Test: `frontend/test/statistics_category_list_row_test.dart`

- [ ] **Step 1: Write the failing test**

Create `frontend/test/statistics_category_list_row_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pocket_pilot/src/features/statistics/domain/category_series_dto.dart';
import 'package:pocket_pilot/src/features/statistics/domain/trend.dart';
import 'package:pocket_pilot/src/features/statistics/ui/widgets/category_list_row.dart';

void main() {
  testWidgets('renders name, current month amount, avg, and up arrow for Trend.up',
      (tester) async {
    const item = CategorySeriesDTO(
      categoryId: 'c1',
      name: 'Comida',
      color: '#A6E3A1',
      icon: 'restaurant',
      kind: 'expense',
      currencyCode: 'MXN',
      totalCents: 600000,
      avgMonthlyCents: 100000,
      currentMonthCents: 120000,
      trend: Trend.up,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CategoryListRow(item: item, windowMonths: 6, onTap: () {}),
        ),
      ),
    );

    expect(find.text('Comida'), findsOneWidget);
    expect(find.textContaining('1,200'), findsOneWidget); // current month
    expect(find.textContaining('prom'), findsOneWidget);
    expect(find.byIcon(Icons.trending_up), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run from `frontend/`:

```bash
flutter test test/statistics_category_list_row_test.dart
```

Expected: FAIL — widget not found.

- [ ] **Step 3: Implement the widget**

```dart
// features/statistics/ui/widgets/category_list_row.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:pocket_pilot/src/core/theme/app_theme.dart';
import 'package:pocket_pilot/src/features/statistics/domain/category_series_dto.dart';
import 'package:pocket_pilot/src/features/statistics/domain/trend.dart';

class CategoryListRow extends StatelessWidget {
  final CategorySeriesDTO item;
  final int windowMonths;
  final VoidCallback onTap;

  const CategoryListRow({
    super.key,
    required this.item,
    required this.windowMonths,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = _parseHex(item.color, cs.primary);

    return InkWell(
      borderRadius: AppTheme.radiusMedium,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: cs.surfaceContainer,
          borderRadius: AppTheme.radiusMedium,
          border: Border.all(color: cs.surfaceContainerHigh, width: 1),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: AppTheme.radiusSmall,
              ),
              child: Icon(Icons.category_outlined, size: 20, color: color),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    style: GoogleFonts.ibmPlexSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface,
                    ),
                  ),
                  Row(
                    children: [
                      Text(
                        'prom. últimos ${windowMonths}m: '
                        '${_fmt(item.avgMonthlyCents, item.currencyCode)}',
                        style: GoogleFonts.ibmPlexSans(
                          fontSize: 12,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Icon(
                        _trendIcon(item.trend),
                        size: 14,
                        color: _trendColor(item.trend, item.kind, cs),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Text(
              _fmt(item.currentMonthCents, item.currencyCode),
              style: GoogleFonts.ibmPlexSans(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static IconData _trendIcon(Trend t) => switch (t) {
        Trend.up => Icons.trending_up,
        Trend.down => Icons.trending_down,
        Trend.flat => Icons.trending_flat,
      };

  static Color _trendColor(Trend t, String kind, ColorScheme cs) {
    if (t == Trend.flat) return cs.onSurfaceVariant;
    final goingUp = t == Trend.up;
    // For expenses, up = worse (red). For income, up = better (green).
    final good = (kind == 'income') == goingUp;
    return good ? cs.primary : cs.error;
  }

  static Color _parseHex(String hex, Color fallback) {
    if (hex.isEmpty) return fallback;
    try {
      final cleaned = hex.replaceFirst('#', '');
      return Color(int.parse('FF$cleaned', radix: 16));
    } catch (_) {
      return fallback;
    }
  }

  static String _fmt(int cents, String currency) {
    final sign = cents < 0 ? '-' : '';
    final abs = cents.abs();
    final whole = abs ~/ 100;
    final frac = abs % 100;
    final buf = StringBuffer();
    final s = whole.toString();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    final wholeStr = buf.toString();
    final fracStr = frac == 0 ? '' : '.${frac.toString().padLeft(2, '0')}';
    return '$sign$currency \$$wholeStr$fracStr';
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run from `frontend/`:

```bash
flutter test test/statistics_category_list_row_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add frontend/lib/src/features/statistics/ui/widgets/category_list_row.dart \
         frontend/test/statistics_category_list_row_test.dart
git commit -m "feat(front-statistics): add category list row widget"
```

---

### Task 12: Widget — Stat Delta Row

**Files:**
- Create: `frontend/lib/src/features/statistics/ui/widgets/stat_delta_row.dart`
- Test: `frontend/test/statistics_stat_delta_row_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// frontend/test/statistics_stat_delta_row_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pocket_pilot/src/features/statistics/ui/widgets/stat_delta_row.dart';

void main() {
  testWidgets('shows promedio, este mes, and delta %', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: StatDeltaRow(
            currency: 'MXN',
            avgCents: 450000,
            currentCents: 380000,
            kind: 'expense',
          ),
        ),
      ),
    );

    expect(find.text('Promedio'), findsOneWidget);
    expect(find.text('Este mes'), findsOneWidget);
    expect(find.textContaining('4,500'), findsOneWidget);
    expect(find.textContaining('3,800'), findsOneWidget);
    expect(find.textContaining('-15%'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run from `frontend/`:

```bash
flutter test test/statistics_stat_delta_row_test.dart
```

Expected: FAIL.

- [ ] **Step 3: Implement the widget**

```dart
// features/statistics/ui/widgets/stat_delta_row.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:pocket_pilot/src/core/theme/app_theme.dart';
import 'package:pocket_pilot/src/features/statistics/domain/trend.dart';

class StatDeltaRow extends StatelessWidget {
  final String currency;
  final int avgCents;
  final int currentCents;
  final String kind; // 'expense' | 'income'

  const StatDeltaRow({
    super.key,
    required this.currency,
    required this.avgCents,
    required this.currentCents,
    required this.kind,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final deltaPct = _deltaPct();
    final deltaColor = _deltaColor(cs);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        borderRadius: AppTheme.radiusMedium,
        border: Border.all(color: cs.surfaceContainerHigh, width: 1),
      ),
      child: Row(
        children: [
          Expanded(
            child: _Stat(
              label: 'Promedio',
              value: _fmt(avgCents, currency),
              color: cs.onSurface,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: _Stat(
              label: 'Este mes',
              value: _fmt(currentCents, currency),
              color: cs.onSurface,
              trailing: deltaPct == null
                  ? null
                  : Text(
                      (deltaPct > 0 ? '+' : '') + '$deltaPct%',
                      style: GoogleFonts.ibmPlexSans(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: deltaColor,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  int? _deltaPct() {
    if (avgCents == 0) return null;
    final diff = currentCents - avgCents;
    return (diff / avgCents * 100).round();
  }

  Color _deltaColor(ColorScheme cs) {
    final d = _deltaPct();
    if (d == null) return cs.onSurfaceVariant;
    final ratio = d.abs() / 100;
    if (ratio < kTrendFlatThresholdRatio) return cs.onSurfaceVariant;
    final higher = d > 0;
    // For expense: lower is better (primary). For income: higher is better.
    final good = (kind == 'income') == higher;
    return good ? cs.primary : cs.error;
  }

  static String _fmt(int cents, String currency) {
    final sign = cents < 0 ? '-' : '';
    final abs = cents.abs();
    final whole = abs ~/ 100;
    final frac = abs % 100;
    final buf = StringBuffer();
    final s = whole.toString();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    final fracStr = frac == 0 ? '' : '.${frac.toString().padLeft(2, '0')}';
    return '$sign$currency \$${buf.toString()}$fracStr';
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final Widget? trailing;

  const _Stat({
    required this.label,
    required this.value,
    required this.color,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.ibmPlexSans(
            fontSize: 11,
            color: cs.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Flexible(
              child: Text(
                value,
                style: GoogleFonts.ibmPlexSans(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 8),
              trailing!,
            ],
          ],
        ),
      ],
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run from `frontend/`:

```bash
flutter test test/statistics_stat_delta_row_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add frontend/lib/src/features/statistics/ui/widgets/stat_delta_row.dart \
         frontend/test/statistics_stat_delta_row_test.dart
git commit -m "feat(front-statistics): add stat delta row widget"
```

---

### Task 13: Widget — Category Monthly Bar Chart

**Files:**
- Create: `frontend/lib/src/features/statistics/ui/widgets/category_monthly_bar_chart.dart`

No widget test — `fl_chart` renders complex CustomPaint and is not productive to assert on pixels. We cover it in the screen-level smoke test (Task 15).

- [ ] **Step 1: Create the widget**

```dart
// features/statistics/ui/widgets/category_monthly_bar_chart.dart
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:pocket_pilot/src/features/statistics/domain/monthly_point_dto.dart';

class CategoryMonthlyBarChart extends StatelessWidget {
  final List<MonthlyPointDTO> points;
  final int? budgetLimitCents;
  final String currentYm;
  final int? selectedIndex;
  final ValueChanged<int> onBarTap;

  const CategoryMonthlyBarChart({
    super.key,
    required this.points,
    required this.currentYm,
    required this.onBarTap,
    this.budgetLimitCents,
    this.selectedIndex,
  });

  static const _monthAbbr = [
    'ene', 'feb', 'mar', 'abr', 'may', 'jun',
    'jul', 'ago', 'sep', 'oct', 'nov', 'dic',
  ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final allZero = points.every((p) => p.amountCents == 0);
    if (points.isEmpty || allZero) {
      return SizedBox(
        height: 180,
        child: Center(
          child: Text(
            'Sin datos en esta ventana',
            style: GoogleFonts.ibmPlexSans(
              fontSize: 13,
              color: cs.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    final maxAmount = points.map((p) => p.amountCents).reduce(
          (a, b) => a > b ? a : b,
        );
    final cap = [maxAmount, budgetLimitCents ?? 0].reduce((a, b) => a > b ? a : b);
    final axisMax = (cap * 1.15).clamp(1, double.infinity).toDouble();

    final crossesYears = points.any((p) => !p.yearMonth.startsWith(
          points.first.yearMonth.substring(0, 4),
        ));

    return SizedBox(
      height: 200,
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: axisMax,
          minY: 0,
          barTouchData: BarTouchData(
            enabled: true,
            touchCallback: (event, response) {
              if (event is! FlTapUpEvent) return;
              final idx = response?.spot?.touchedBarGroupIndex;
              if (idx != null) onBarTap(idx);
            },
            touchTooltipData: BarTouchTooltipData(
              getTooltipItem: (group, _, rod, __) {
                final p = points[group.x];
                return BarTooltipItem(
                  '${_labelFor(p.yearMonth, crossesYears)}\n'
                  '\$${(p.amountCents / 100).toStringAsFixed(0)}',
                  GoogleFonts.ibmPlexSans(
                    fontSize: 12,
                    color: cs.onInverseSurface,
                  ),
                );
              },
            ),
          ),
          titlesData: FlTitlesData(
            leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 22,
                getTitlesWidget: (x, _) {
                  final i = x.toInt();
                  if (i < 0 || i >= points.length) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      _labelFor(points[i].yearMonth, crossesYears),
                      style: GoogleFonts.ibmPlexSans(
                        fontSize: 10,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          barGroups: [
            for (var i = 0; i < points.length; i++)
              BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: points[i].amountCents.toDouble().clamp(0, axisMax),
                    width: 14,
                    color: points[i].yearMonth == currentYm
                        ? cs.primary
                        : cs.surfaceContainerHigh,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(3),
                    ),
                  ),
                ],
              ),
          ],
          extraLinesData: ExtraLinesData(
            horizontalLines: [
              if (budgetLimitCents != null && budgetLimitCents! > 0)
                HorizontalLine(
                  y: budgetLimitCents!.toDouble(),
                  color: cs.error,
                  strokeWidth: 1.5,
                  dashArray: const [4, 4],
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _labelFor(String ym, bool includeYear) {
    final year = int.parse(ym.substring(0, 4));
    final month = int.parse(ym.substring(5, 7));
    final abbr = _monthAbbr[month - 1];
    if (!includeYear) return abbr;
    return "$abbr '${year.toString().substring(2)}";
  }
}
```

- [ ] **Step 2: Verify compilation**

Run from `frontend/`:

```bash
flutter analyze lib/src/features/statistics/ui/widgets/category_monthly_bar_chart.dart
```

Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
git add frontend/lib/src/features/statistics/ui/widgets/category_monthly_bar_chart.dart
git commit -m "feat(front-statistics): add monthly bar chart widget"
```

---

### Task 14: Statistics Tab (List Screen Body)

**Files:**
- Create: `frontend/lib/src/features/statistics/ui/statistics_tab.dart`

The smoke test lives in Task 15 alongside integration wiring so it exercises the full widget tree.

- [ ] **Step 1: Create the widget**

```dart
// features/statistics/ui/statistics_tab.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'package:pocket_pilot/src/core/theme/app_theme.dart';
import 'package:pocket_pilot/src/features/statistics/domain/category_series_dto.dart';
import 'package:pocket_pilot/src/features/statistics/ui/statistics_view_model.dart';
import 'package:pocket_pilot/src/features/statistics/ui/widgets/category_list_row.dart';
import 'package:pocket_pilot/src/features/statistics/ui/widgets/time_window_chips.dart';

class StatisticsTab extends StatelessWidget {
  const StatisticsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Consumer<StatisticsViewModel>(
      builder: (context, vm, _) {
        if (vm.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }
        if (vm.errorMessage != null) {
          return _ErrorState(
            message: vm.errorMessage!,
            onRetry: vm.refresh,
          );
        }

        final expense = vm.series.where((s) => s.kind == 'expense').toList();
        final income = vm.series.where((s) => s.kind == 'income').toList();

        return RefreshIndicator(
          onRefresh: vm.refresh,
          child: CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 96),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    Center(
                      child: TimeWindowChips(
                        selectedMonths: vm.months,
                        onChanged: vm.setWindow,
                      ),
                    ),
                    const SizedBox(height: 20),
                    if (vm.series.isEmpty)
                      _EmptyState(cs: cs)
                    else ...[
                      if (expense.isNotEmpty) ...[
                        _SectionHeader(title: 'Gastos'),
                        const SizedBox(height: 12),
                        ...expense.map(
                          (s) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: CategoryListRow(
                              item: s,
                              windowMonths: vm.months,
                              onTap: () => _openDetail(context, s),
                            ),
                          ),
                        ),
                      ],
                      if (income.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        _SectionHeader(title: 'Ingresos'),
                        const SizedBox(height: 12),
                        ...income.map(
                          (s) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: CategoryListRow(
                              item: s,
                              windowMonths: vm.months,
                              onTap: () => _openDetail(context, s),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ]),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _openDetail(BuildContext context, CategorySeriesDTO item) {
    context.push(
      '/dashboard/statistics/category/${item.categoryId}',
      extra: item,
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: GoogleFonts.ibmPlexSans(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: Theme.of(context).colorScheme.onSurface,
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final ColorScheme cs;
  const _EmptyState({required this.cs});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          Icon(Icons.query_stats, size: 40, color: cs.onSurfaceVariant),
          const SizedBox(height: 12),
          Text(
            'Aún no hay suficiente historial',
            style: GoogleFonts.ibmPlexSans(
              fontSize: 14,
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => context.go('/transactions'),
            child: const Text('Ver transacciones'),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final Future<void> Function() onRetry;
  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 40, color: cs.error),
            const SizedBox(height: 12),
            Text(
              'No se pudieron cargar las estadísticas',
              style: GoogleFonts.ibmPlexSans(
                fontSize: 14,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              message,
              style: GoogleFonts.ibmPlexSans(
                fontSize: 12,
                color: cs.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: () => onRetry(), child: const Text('Reintentar')),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Verify compilation**

Run from `frontend/`:

```bash
flutter analyze lib/src/features/statistics/ui/statistics_tab.dart
```

Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
git add frontend/lib/src/features/statistics/ui/statistics_tab.dart
git commit -m "feat(front-statistics): add statistics tab list"
```

---

### Task 15: Category History Screen (Detail)

**Files:**
- Create: `frontend/lib/src/features/statistics/ui/category_history_screen.dart`

- [ ] **Step 1: Create the screen**

```dart
// features/statistics/ui/category_history_screen.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'package:pocket_pilot/src/core/theme/app_theme.dart';
import 'package:pocket_pilot/src/features/budgets/domain/budget_status.dart';
import 'package:pocket_pilot/src/features/dashboard/ui/dashboard_filter_view_model.dart';
import 'package:pocket_pilot/src/features/statistics/data/statistics_repository.dart';
import 'package:pocket_pilot/src/features/statistics/domain/category_history_dto.dart';
import 'package:pocket_pilot/src/features/statistics/domain/category_series_dto.dart';
import 'package:pocket_pilot/src/features/statistics/ui/widgets/category_monthly_bar_chart.dart';
import 'package:pocket_pilot/src/features/statistics/ui/widgets/stat_delta_row.dart';
import 'package:pocket_pilot/src/features/statistics/ui/widgets/time_window_chips.dart';

class CategoryHistoryScreen extends StatefulWidget {
  final String categoryId;
  final CategorySeriesDTO? initialSummary;

  const CategoryHistoryScreen({
    super.key,
    required this.categoryId,
    this.initialSummary,
  });

  @override
  State<CategoryHistoryScreen> createState() => _CategoryHistoryScreenState();
}

class _CategoryHistoryScreenState extends State<CategoryHistoryScreen> {
  int _months = 6;
  int? _selectedBarIndex;
  CategoryHistoryDTO? _history;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final repo = context.read<StatisticsRepository>();
    final filter = context.read<DashboardFilterViewModel>();
    final currency = filter.currencyCode;
    if (currency == null) {
      setState(() {
        _loading = false;
        _error = 'Selecciona una moneda primero';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await repo.getHistory(
        categoryId: widget.categoryId,
        currencyCode: currency,
        months: _months,
        now: DateTime.now(),
      );
      setState(() {
        _history = data;
        _selectedBarIndex = data.points.length - 1;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final summary = _history?.summary ?? widget.initialSummary;

    return Scaffold(
      appBar: AppBar(
        title: Text(summary?.name ?? ''),
        actions: [
          IconButton(
            icon: const Icon(Icons.list_alt),
            tooltip: 'Ver transacciones',
            onPressed: () => context.go(
              '/transactions',
              extra: {'categoryId': widget.categoryId},
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _Error(message: _error!, onRetry: _load)
              : _Body(
                  history: _history!,
                  months: _months,
                  selectedBarIndex: _selectedBarIndex,
                  onWindowChanged: (m) {
                    setState(() => _months = m);
                    _load();
                  },
                  onBarTap: (i) => setState(() => _selectedBarIndex = i),
                  cs: cs,
                ),
    );
  }
}

class _Body extends StatelessWidget {
  final CategoryHistoryDTO history;
  final int months;
  final int? selectedBarIndex;
  final ValueChanged<int> onWindowChanged;
  final ValueChanged<int> onBarTap;
  final ColorScheme cs;

  const _Body({
    required this.history,
    required this.months,
    required this.selectedBarIndex,
    required this.onWindowChanged,
    required this.onBarTap,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    final s = history.summary;
    final current = history.points.isEmpty ? 0 : history.points.last.amountCents;
    final currentYm = history.points.isEmpty ? '' : history.points.last.yearMonth;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 96),
      children: [
        Center(
          child: TimeWindowChips(
            selectedMonths: months,
            onChanged: onWindowChanged,
          ),
        ),
        const SizedBox(height: 16),
        StatDeltaRow(
          currency: s.currencyCode,
          avgCents: s.avgMonthlyCents,
          currentCents: current,
          kind: s.kind,
        ),
        const SizedBox(height: 16),
        CategoryMonthlyBarChart(
          points: history.points,
          currentYm: currentYm,
          budgetLimitCents: history.budget?.budget.period == 'MONTHLY'
              ? history.budget!.budget.limitAmountCents
              : null,
          selectedIndex: selectedBarIndex,
          onBarTap: onBarTap,
        ),
        const SizedBox(height: 20),
        _BudgetCard(
          status: history.budget,
          fallbackSuggestionCents: s.avgMonthlyCents,
          categoryId: s.categoryId,
          currency: s.currencyCode,
        ),
      ],
    );
  }
}

class _BudgetCard extends StatelessWidget {
  final BudgetStatus? status;
  final int fallbackSuggestionCents;
  final String categoryId;
  final String currency;

  const _BudgetCard({
    required this.status,
    required this.fallbackSuggestionCents,
    required this.categoryId,
    required this.currency,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (status == null) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: AppTheme.radiusMedium,
          border: Border.all(color: cs.surfaceContainerHigh),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Crea un presupuesto basado en tu promedio',
              style: GoogleFonts.ibmPlexSans(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: () => context.push(
                '/accounts/budgets/new'
                '?categoryId=$categoryId'
                '&suggested=$fallbackSuggestionCents'
                '&currency=$currency',
              ),
              child: const Text('Crear presupuesto'),
            ),
          ],
        ),
      );
    }

    final pct = status!.progressPercentage.clamp(0, 100).toDouble();
    final isOver = status!.spentAmountCents > status!.budget.limitAmountCents;
    final isMonthly = status!.budget.period == 'MONTHLY';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        borderRadius: AppTheme.radiusMedium,
        border: Border.all(color: cs.surfaceContainerHigh),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isMonthly
                ? 'Presupuesto mensual'
                : 'Presupuesto anual — línea no mostrada',
            style: GoogleFonts.ibmPlexSans(
              fontSize: 12,
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: pct / 100,
            color: isOver ? cs.error : cs.primary,
            backgroundColor: cs.surfaceContainerHigh,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                '${pct.round()}%',
                style: GoogleFonts.ibmPlexSans(
                  fontSize: 13,
                  color: cs.onSurface,
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: () => context.push(
                  '/accounts/budgets/${status!.budget.id}/edit',
                  extra: status!.budget,
                ),
                child: const Text('Editar'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Error extends StatelessWidget {
  final String message;
  final Future<void> Function() onRetry;
  const _Error({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message),
            const SizedBox(height: 12),
            FilledButton(onPressed: onRetry, child: const Text('Reintentar')),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Verify compilation**

Run from `frontend/`:

```bash
flutter analyze lib/src/features/statistics/ui/category_history_screen.dart
```

Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
git add frontend/lib/src/features/statistics/ui/category_history_screen.dart
git commit -m "feat(front-statistics): add category history detail screen"
```

---

### Task 16: Dashboard Integration — TabBar + Route Scope + Route

**Files:**
- Modify: `frontend/lib/src/features/dashboard/ui/dashboard_route_scope.dart`
- Modify: `frontend/lib/src/ui/screens/dashboard/dashboard_screen.dart`
- Modify: `frontend/lib/src/ui/router.dart`

- [ ] **Step 1: Provide `StatisticsViewModel` in the route scope**

Replace `frontend/lib/src/features/dashboard/ui/dashboard_route_scope.dart` with:

```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:pocket_pilot/src/core/db/database_helper.dart';
import 'package:pocket_pilot/src/features/budgets/data/budget_local_store.dart';
import 'package:pocket_pilot/src/features/dashboard/data/dashboard_local_store.dart';
import 'package:pocket_pilot/src/features/dashboard/data/dashboard_repository.dart';
import 'package:pocket_pilot/src/features/dashboard/ui/dashboard_filter_view_model.dart';
import 'package:pocket_pilot/src/features/dashboard/ui/dashboard_view_model.dart';
import 'package:pocket_pilot/src/features/statistics/data/statistics_local_store.dart';
import 'package:pocket_pilot/src/features/statistics/data/statistics_repository.dart';
import 'package:pocket_pilot/src/features/statistics/ui/statistics_view_model.dart';

class DashboardRouteScope extends StatelessWidget {
  final Widget child;

  const DashboardRouteScope({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => DashboardFilterViewModel()),
        Provider<StatisticsRepository>(
          create: (ctx) {
            final db = ctx.read<DatabaseHelper>();
            return StatisticsRepository(
              local: StatisticsLocalStore(db: db),
              budgetLocal: BudgetLocalStore(db: db),
            );
          },
        ),
        ChangeNotifierProvider(
          create: (ctx) {
            final db = ctx.read<DatabaseHelper>();
            final localStore = DashboardLocalStore(db: db);
            final repository = DashboardRepository(local: localStore);
            final filterVM = ctx.read<DashboardFilterViewModel>();
            return DashboardViewModel(
              repository: repository,
              filterViewModel: filterVM,
            )..loadOnAppear();
          },
        ),
        ChangeNotifierProvider(
          create: (ctx) {
            final repo = ctx.read<StatisticsRepository>();
            final filterVM = ctx.read<DashboardFilterViewModel>();
            return StatisticsViewModel(
              repository: repo,
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

- [ ] **Step 2: Refactor `DashboardScreen` to host a TabBar**

Refactoring `dashboard_screen.dart` is a larger surgical change. Extract the existing body (everything currently inside the `Consumer2.builder`) into a new file `frontend/lib/src/ui/screens/dashboard/dashboard_summary_tab.dart`, then replace `dashboard_screen.dart` with a TabBar-hosting shell.

**2a.** Create `frontend/lib/src/ui/screens/dashboard/dashboard_summary_tab.dart` and paste the entire current body of `DashboardScreen` into a new `DashboardSummaryTab` widget. Keep all private `_FilterButton`, `_CurrencyTabs`, `_NetWorthCard`, `_MetricsGrid`, `_MetricCard`, `_AccountCard`, `_CreditCardPaymentCard`, `_SpendBreakdown`, `_NatureSpendBreakdown`, `_TagSpendBreakdown`, `_SectionHeader`, `_EmptyHint`, `_formatAmount`, `_formatWithCommas`, `_accountIcon`, `_accountTypeLabel`, and `_parseCategoryColor` symbols inside this new file (they are all private and only used here). The widget class is:

```dart
class DashboardSummaryTab extends StatelessWidget {
  const DashboardSummaryTab({super.key});

  @override
  Widget build(BuildContext context) {
    // ... paste the exact body (Consumer2 + RefreshIndicator + CustomScrollView)
    // from the old DashboardScreen.build() here.
  }
}
```

**2b.** Replace `dashboard_screen.dart` with a shell that hosts the TabBar:

```dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'package:pocket_pilot/src/features/dashboard/ui/dashboard_filter_view_model.dart';
import 'package:pocket_pilot/src/features/statistics/ui/statistics_tab.dart';
import 'package:pocket_pilot/src/ui/screens/dashboard/dashboard_summary_tab.dart';
import 'package:pocket_pilot/src/ui/widgets/notification_bell.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final filterVM = context.watch<DashboardFilterViewModel>();

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        floatingActionButton: FloatingActionButton(
          onPressed: () => context.go('/transactions/new'),
          tooltip: 'Nueva transacción',
          child: const Icon(Icons.add),
        ),
        appBar: AppBar(
          title: Text(
            'Dashboard',
            style: GoogleFonts.ibmPlexSans(
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
          ),
          actions: const [
            NotificationBell(),
            SizedBox(width: 8),
          ],
          bottom: TabBar(
            tabs: const [
              Tab(text: 'Resumen'),
              Tab(text: 'Estadísticas'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            DashboardSummaryTab(),
            StatisticsTab(),
          ],
        ),
      ),
    );
  }
}
```

Important: since the old `DashboardScreen` owned the `SliverAppBar` + `_FilterButton`, move that SliverAppBar logic into `DashboardSummaryTab` so the existing filters continue to work on the Resumen tab (the TabBar is now the shared chrome). Concretely, the top of `DashboardSummaryTab.build` keeps the same `Consumer2<DashboardViewModel, DashboardFilterViewModel>` and the `CustomScrollView` with its existing `SliverAppBar` + content slivers — just remove the title `Text('Dashboard')` and `NotificationBell()` from that SliverAppBar (those now live in the outer AppBar) and keep `_FilterButton` in the SliverAppBar actions.

- [ ] **Step 3: Add the detail route**

Open `frontend/lib/src/ui/router.dart`. Inside the `'/dashboard'` GoRoute (around line 96), add `routes: [...]`:

```dart
          GoRoute(
            path: '/dashboard',
            builder: (context, state) =>
                const DashboardRouteScope(child: DashboardScreen()),
            routes: [
              GoRoute(
                path: 'statistics/category/:categoryId',
                builder: (context, state) => DashboardRouteScope(
                  child: CategoryHistoryScreen(
                    categoryId: state.pathParameters['categoryId']!,
                    initialSummary: state.extra as CategorySeriesDTO?,
                  ),
                ),
              ),
            ],
          ),
```

Also add the new imports at the top of `router.dart`:

```dart
import 'package:pocket_pilot/src/features/statistics/domain/category_series_dto.dart';
import 'package:pocket_pilot/src/features/statistics/ui/category_history_screen.dart';
```

- [ ] **Step 4: Run analyzer and existing tests**

Run from `frontend/`:

```bash
flutter analyze lib
flutter test test/router_single_root_shell_test.dart
```

Expected: `No issues found!` and PASS.

- [ ] **Step 5: Commit**

```bash
git add frontend/lib/src/features/dashboard/ui/dashboard_route_scope.dart \
         frontend/lib/src/ui/screens/dashboard/dashboard_screen.dart \
         frontend/lib/src/ui/screens/dashboard/dashboard_summary_tab.dart \
         frontend/lib/src/ui/router.dart
git commit -m "feat(front-dashboard): add Estadísticas tab with route scope"
```

---

### Task 17: Smoke Test — StatisticsTab End-to-End

**Files:**
- Test: `frontend/test/statistics_tab_smoke_test.dart`

- [ ] **Step 1: Write the smoke test**

```dart
// frontend/test/statistics_tab_smoke_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:pocket_pilot/src/core/db/database_helper.dart';
import 'package:pocket_pilot/src/features/budgets/data/budget_local_store.dart';
import 'package:pocket_pilot/src/features/dashboard/ui/dashboard_filter_view_model.dart';
import 'package:pocket_pilot/src/features/statistics/data/statistics_local_store.dart';
import 'package:pocket_pilot/src/features/statistics/data/statistics_repository.dart';
import 'package:pocket_pilot/src/features/statistics/domain/category_series_dto.dart';
import 'package:pocket_pilot/src/features/statistics/domain/trend.dart';
import 'package:pocket_pilot/src/features/statistics/ui/statistics_tab.dart';
import 'package:pocket_pilot/src/features/statistics/ui/statistics_view_model.dart';

class _FakeRepo extends StatisticsRepository {
  final List<CategorySeriesDTO> data;
  final bool shouldThrow;

  _FakeRepo({this.data = const [], this.shouldThrow = false})
      : super(
          local: StatisticsLocalStore(db: DatabaseHelper()),
          budgetLocal: BudgetLocalStore(db: DatabaseHelper()),
        );

  @override
  Future<List<CategorySeriesDTO>> getSeriesList({
    required String currencyCode,
    required String windowStart,
    required String windowEnd,
    required String windowMid,
    required String currentYm,
    required int months,
  }) async {
    if (shouldThrow) throw StateError('db down');
    return data;
  }
}

Widget _wrap({required _FakeRepo repo}) {
  final filter = DashboardFilterViewModel()..setCurrencyCode('MXN');
  return MaterialApp(
    home: MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: filter),
        ChangeNotifierProvider(
          create: (_) => StatisticsViewModel(
            repository: repo,
            filterViewModel: filter,
            now: () => DateTime.utc(2026, 4, 17),
          )..loadOnAppear(),
        ),
      ],
      child: const Scaffold(body: StatisticsTab()),
    ),
  );
}

void main() {
  testWidgets('shows expense + income sections when data present',
      (tester) async {
    await tester.pumpWidget(_wrap(
      repo: _FakeRepo(data: const [
        CategorySeriesDTO(
          categoryId: 'c1',
          name: 'Comida',
          color: '',
          icon: '',
          kind: 'expense',
          currencyCode: 'MXN',
          totalCents: 600000,
          avgMonthlyCents: 100000,
          currentMonthCents: 120000,
          trend: Trend.up,
        ),
        CategorySeriesDTO(
          categoryId: 'c2',
          name: 'Salario',
          color: '',
          icon: '',
          kind: 'income',
          currencyCode: 'MXN',
          totalCents: 1200000,
          avgMonthlyCents: 200000,
          currentMonthCents: 200000,
          trend: Trend.flat,
        ),
      ]),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Gastos'), findsOneWidget);
    expect(find.text('Ingresos'), findsOneWidget);
    expect(find.text('Comida'), findsOneWidget);
    expect(find.text('Salario'), findsOneWidget);
  });

  testWidgets('empty state when repository returns nothing', (tester) async {
    await tester.pumpWidget(_wrap(repo: _FakeRepo()));
    await tester.pumpAndSettle();

    expect(find.text('Aún no hay suficiente historial'), findsOneWidget);
  });

  testWidgets('error state shows retry button', (tester) async {
    await tester.pumpWidget(_wrap(repo: _FakeRepo(shouldThrow: true)));
    await tester.pumpAndSettle();

    expect(find.text('Reintentar'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run the test**

Run from `frontend/`:

```bash
flutter test test/statistics_tab_smoke_test.dart
```

Expected: PASS (3 tests).

- [ ] **Step 3: Commit**

```bash
git add frontend/test/statistics_tab_smoke_test.dart
git commit -m "test(front-statistics): add tab smoke tests"
```

---

### Task 18: Full Suite + Manual Verification + Journal

**Files:**
- Modify: `docs/context/.journal.md`

- [ ] **Step 1: Run the full test suite**

Run from `frontend/`:

```bash
flutter test
```

Expected: PASS across all tests (including existing ones).

- [ ] **Step 2: Run analyzer on the whole frontend**

Run from `frontend/`:

```bash
flutter analyze
```

Expected: `No issues found!`

- [ ] **Step 3: Manual verification on a device or simulator**

Launch the app and validate each bullet from spec §"Manual verification":
- Switch currency in Dashboard → Estadísticas list updates.
- Toggle window (3/6/12) → list reorders / refreshes.
- Tap a category → detail screen opens with chart + budget card.
- Tap a bar on the chart → the bar tooltip shows month and amount.
- If no budget exists: tap "Crear presupuesto" → the Budgets form opens with category + suggested limit + currency pre-filled.
- Tap AppBar list icon on detail → navigates to `/transactions` (transaction filters honoring `extra` are out of scope for this spec, but the navigation must not crash).

- [ ] **Step 4: Add a journal entry**

Append to `docs/context/.journal.md`:

```markdown
## 2026-04-17 — Statistics Tab (category analytics)

- New feature `features/statistics/` (read-only) added:
  - Layered as data / domain / ui.
  - `StatisticsLocalStore` runs two raw SQL aggregates (category summary + monthly series) with netted expenses/income.
  - `StatisticsRepository` sign-flips income, computes trend + average, zero-fills months, and integrates with `BudgetLocalStore`.
- `DashboardScreen` now hosts a TabBar with `DashboardSummaryTab` (existing body extracted) and `StatisticsTab`. `DashboardRouteScope` now provides `StatisticsViewModel` + `StatisticsRepository`.
- Cross-feature additions to Budgets (both strictly additive):
  - `BudgetLocalStore.findByCategory(categoryId)` for per-category lookup.
  - `BudgetFormScreen` accepts `initialCategoryId/initialLimitCents/initialCurrencyCode` and the `/accounts/budgets/new` route reads `categoryId`, `suggested`, and `currency` query params.
- New dependency: `fl_chart`.
- Deferred follow-ups tracked in the spec: historical metrics, cash flow, period comparison, forecasting, deleted-category resurfacing, MSI proration for statistics.
```

- [ ] **Step 5: Commit**

```bash
git add docs/context/.journal.md
git commit -m "docs: journal entry for statistics tab"
```

---

## Self-Review Checklist

- **Spec coverage:**
  - Goals 1-4: covered by Tasks 7-17 (list, detail, budget seeding, month drill-in).
  - Netting semantics: Task 7 (SQL) + Task 8 (sign flip in repo).
  - MSI deferral: not implemented (by design); noted in spec.
  - Window math: Task 6.
  - DTOs: Tasks 4-5.
  - Cross-feature Budgets deliverables: Tasks 2-3.
  - Route `/dashboard/statistics/category/:categoryId`: Task 16 step 3.
  - TabBar integration: Task 16 step 2.
  - Error handling (DB / budget / empty data): Tasks 8, 13, 14.
  - Currency-mismatch budget: Task 8 (`_loadBudget`) + test coverage.
  - Testing requirements from spec: `statistics_repository_test.dart` (Task 8), `statistics_view_model_test.dart` (Task 9), widget tests (Tasks 11, 12), smoke tests (Task 17), budget pre-fill (Task 3). `statistics_local_store_test.dart` is intentionally skipped — the codebase pattern (see `dashboard_repository_credit_card_obligation_test.dart`) is to test the repository with a `_FakeLocalStore`, not exercise raw SQL. `window_math` pure tests replace it (Task 6).
- **No placeholders.** No TBD/TODO markers. Every code block is complete.
- **Type consistency.**
  - `getSeriesList` signature matches in repository + ViewModel + smoke test fake.
  - `getCategorySeries` / `getMonthlySeries` signatures identical in local store and its fakes.
  - `CategorySeriesDTO` fields used identically in repository, ViewModel, widgets, and fakes.
  - `findByCategory(categoryId)` returns `Map<String,dynamic>?` everywhere.
  - `BudgetFormScreen` constructor: the three new params are listed identically in Task 3 edits, router (Task 3 step 5), and test (Task 3 step 1).
  - `kTrendFlatThresholdRatio` referenced from both `trend.dart` (declaration) and `stat_delta_row.dart` (`_deltaColor`).

---

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-04-17-statistics-tab.md`. Two execution options:

**1. Subagent-Driven (recommended)** — I dispatch a fresh subagent per task, review between tasks, fast iteration.

**2. Inline Execution** — Execute tasks in this session using executing-plans, batch execution with checkpoints.

**Which approach?**
