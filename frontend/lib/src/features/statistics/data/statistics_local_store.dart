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
      WHERE c.deleted_at IS NULL
      GROUP BY c.id
      HAVING ABS(total_cents) > 0
      ORDER BY ABS(total_cents) DESC
      ''',
      [currentYm, windowMid, windowMid, currencyCode, windowStart, windowEnd],
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
