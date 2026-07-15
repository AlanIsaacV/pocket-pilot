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
    Set<String>? accountIds,
  }) async {
    final db = await _db.database;
    final accountsClause = StringBuffer();
    final accountsArgs = <Object?>[];
    if (accountIds != null && accountIds.isNotEmpty) {
      final placeholders = List.filled(accountIds.length, '?').join(',');
      accountsClause.write(' AND t.account_id IN ($placeholders)');
      accountsArgs.addAll(accountIds);
    }
    return db.rawQuery(
      '''
      SELECT
        c.id AS category_id,
        c.name, c.color, c.icon, c.type AS kind,
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
        ${accountsClause.toString()}
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
        ...accountsArgs,
      ],
    );
  }

  /// Monthly series for a single tag. Returns only months that have
  /// activity; the repository zero-fills missing months.
  ///
  /// Uses `json_each` to flatten the JSON `tags` array on each row.
  /// Same netting rules as [getMonthlySeries] (expense +, income -),
  /// transfers excluded.
  Future<List<Map<String, dynamic>>> getTagMonthlySeries({
    required String tagName,
    required String currencyCode,
    required String windowStart,
    required String windowEnd,
    Set<String>? accountIds,
  }) async {
    final db = await _db.database;
    final accountsClause = StringBuffer();
    final accountsArgs = <Object?>[];
    if (accountIds != null && accountIds.isNotEmpty) {
      final placeholders = List.filled(accountIds.length, '?').join(',');
      accountsClause.write(' AND t.account_id IN ($placeholders)');
      accountsArgs.addAll(accountIds);
    }
    return db.rawQuery(
      '''
      SELECT
        strftime('%Y-%m', t.date) AS ym,
        COALESCE(SUM(CASE WHEN t.type = 'expense' THEN  t.amount_cents
                          WHEN t.type = 'income'  THEN -t.amount_cents
                          ELSE 0 END), 0) AS amount_cents
      FROM transactions t, json_each(t.tags) j
      WHERE j.value         = ?
        AND t.currency_code = ?
        AND t.date         >= ?
        AND t.date         <  ?
        AND t.deleted_at   IS NULL
        AND t.status        = 'cleared'
        AND t.type         IN ('expense', 'income')
        AND t.tags IS NOT NULL AND t.tags != '' AND t.tags != '[]'
        ${accountsClause.toString()}
      GROUP BY ym
      ORDER BY ym
      ''',
      [
        tagName,
        currencyCode,
        windowStart,
        windowEnd,
        ...accountsArgs,
      ],
    );
  }

  /// Breakdown by category for a single tag inside the window.
  /// Returns one row per (category_id) with category metadata.
  Future<List<Map<String, dynamic>>> getTagCategoryBreakdown({
    required String tagName,
    required String currencyCode,
    required String windowStart,
    required String windowEnd,
    Set<String>? accountIds,
  }) async {
    final db = await _db.database;
    final accountsClause = StringBuffer();
    final accountsArgs = <Object?>[];
    if (accountIds != null && accountIds.isNotEmpty) {
      final placeholders = List.filled(accountIds.length, '?').join(',');
      accountsClause.write(' AND t.account_id IN ($placeholders)');
      accountsArgs.addAll(accountIds);
    }
    return db.rawQuery(
      '''
      SELECT
        c.id   AS category_id,
        c.name AS category_name,
        c.color AS category_color,
        c.icon  AS category_icon,
        c.type  AS kind,
        COALESCE(SUM(CASE WHEN t.type = 'expense' THEN  t.amount_cents
                          WHEN t.type = 'income'  THEN -t.amount_cents
                          ELSE 0 END), 0) AS amount_cents
      FROM transactions t
      JOIN json_each(t.tags) j
      LEFT JOIN categories c ON c.id = t.category_id
      WHERE j.value         = ?
        AND t.currency_code = ?
        AND t.date         >= ?
        AND t.date         <  ?
        AND t.deleted_at   IS NULL
        AND t.status        = 'cleared'
        AND t.type         IN ('expense', 'income')
        AND t.tags IS NOT NULL AND t.tags != '' AND t.tags != '[]'
        ${accountsClause.toString()}
      GROUP BY c.id
      HAVING ABS(amount_cents) > 0
      ORDER BY ABS(amount_cents) DESC
      ''',
      [
        tagName,
        currencyCode,
        windowStart,
        windowEnd,
        ...accountsArgs,
      ],
    );
  }

  /// Total spend per tag inside the window, all currencies. Used by the
  /// tags-list hub entry. Excludes tags with zero net activity.
  Future<List<Map<String, dynamic>>> getAllTagsWithTotals({
    required String windowStart,
    required String windowEnd,
    Set<String>? accountIds,
    String? currencyCode,
  }) async {
    final db = await _db.database;
    final accountsClause = StringBuffer();
    final accountsArgs = <Object?>[];
    if (accountIds != null && accountIds.isNotEmpty) {
      final placeholders = List.filled(accountIds.length, '?').join(',');
      accountsClause.write(' AND t.account_id IN ($placeholders)');
      accountsArgs.addAll(accountIds);
    }
    final currencyClause = StringBuffer();
    final currencyArgs = <Object?>[];
    if (currencyCode != null) {
      currencyClause.write(' AND t.currency_code = ?');
      currencyArgs.add(currencyCode);
    }
    return db.rawQuery(
      '''
      SELECT
        j.value         AS tag_name,
        t.currency_code AS currency_code,
        COALESCE(SUM(CASE WHEN t.type = 'expense' THEN  t.amount_cents
                          WHEN t.type = 'income'  THEN -t.amount_cents
                          ELSE 0 END), 0) AS amount_cents
      FROM transactions t, json_each(t.tags) j
      WHERE t.date       >= ?
        AND t.date       <  ?
        AND t.deleted_at IS NULL
        AND t.status      = 'cleared'
        AND t.type       IN ('expense', 'income')
        AND t.tags IS NOT NULL AND t.tags != '' AND t.tags != '[]'
        ${currencyClause.toString()}
        ${accountsClause.toString()}
      GROUP BY j.value, t.currency_code
      HAVING amount_cents > 0
      ORDER BY amount_cents DESC
      ''',
      [
        windowStart,
        windowEnd,
        ...currencyArgs,
        ...accountsArgs,
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
    Set<String>? accountIds,
  }) async {
    final db = await _db.database;
    final accountsClause = StringBuffer();
    final accountsArgs = <Object?>[];
    if (accountIds != null && accountIds.isNotEmpty) {
      final placeholders = List.filled(accountIds.length, '?').join(',');
      accountsClause.write(' AND t.account_id IN ($placeholders)');
      accountsArgs.addAll(accountIds);
    }
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
        ${accountsClause.toString()}
      GROUP BY ym
      ORDER BY ym
      ''',
      [
        categoryId,
        currencyCode,
        windowStart,
        windowEnd,
        ...accountsArgs,
      ],
    );
  }
}
