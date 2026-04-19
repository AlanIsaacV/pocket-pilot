// features/cashflow/data/cashflow_local_store.dart
//
// Read-only SQL for aggregate cashflow totals across a time window.
// Follows the same conventions as StatisticsLocalStore:
//   - Transfers excluded (only type IN ('expense','income'))
//   - Soft-deleted rows excluded (t.deleted_at IS NULL, c.deleted_at IS NULL)
//   - amount_cents stored as absolute magnitude; sign inferred from type
//   - Dates compared as 'YYYY-MM-DD' strings (lexicographic)

import 'package:pocket_pilot/src/core/db/database_helper.dart';

class CashflowLocalStore {
  final DatabaseHelper _db;

  CashflowLocalStore({required DatabaseHelper db}) : _db = db;

  /// Aggregate per-category sums (one row per category with activity in
  /// the window). `kind` = 'income' | 'expense' mirrors categories.type.
  Future<List<Map<String, dynamic>>> getCategoryTotals({
    required String currencyCode,
    required String windowStart,
    required String windowEnd,
  }) async {
    final db = await _db.database;
    return db.rawQuery(
      '''
      SELECT
        c.id AS category_id,
        c.name AS name,
        c.color AS color,
        c.type AS kind,
        COALESCE(SUM(t.amount_cents), 0) AS total_cents
      FROM categories c
      INNER JOIN transactions t
        ON t.category_id    = c.id
        AND t.currency_code = ?
        AND t.date         >= ?
        AND t.date         <  ?
        AND t.deleted_at   IS NULL
        AND t.type         IN ('expense', 'income')
      WHERE c.deleted_at IS NULL
      GROUP BY c.id
      HAVING total_cents > 0
      ORDER BY total_cents DESC
      ''',
      [currencyCode, windowStart, windowEnd],
    );
  }

  /// Aggregate per-financial-nature sums. Skips transactions whose
  /// `nature` column is empty (legacy rows) so they don't pollute the
  /// chart with an "unspecified" wedge; those still count toward totals.
  Future<List<Map<String, dynamic>>> getNatureTotals({
    required String currencyCode,
    required String windowStart,
    required String windowEnd,
  }) async {
    final db = await _db.database;
    return db.rawQuery(
      '''
      SELECT
        t.nature AS nature,
        t.type   AS kind,
        COALESCE(SUM(t.amount_cents), 0) AS total_cents
      FROM transactions t
      WHERE t.currency_code = ?
        AND t.date         >= ?
        AND t.date         <  ?
        AND t.deleted_at   IS NULL
        AND t.type         IN ('expense', 'income')
        AND t.nature       IS NOT NULL
        AND t.nature       <> ''
      GROUP BY t.nature, t.type
      HAVING total_cents > 0
      ORDER BY total_cents DESC
      ''',
      [currencyCode, windowStart, windowEnd],
    );
  }

  /// Grand totals (in vs out) so UI cards match the breakdown without
  /// recomputing client-side — avoids drift if "Otros" fold shifts.
  Future<Map<String, int>> getTotals({
    required String currencyCode,
    required String windowStart,
    required String windowEnd,
  }) async {
    final db = await _db.database;
    final rows = await db.rawQuery(
      '''
      SELECT
        t.type AS kind,
        COALESCE(SUM(t.amount_cents), 0) AS total_cents
      FROM transactions t
      WHERE t.currency_code = ?
        AND t.date         >= ?
        AND t.date         <  ?
        AND t.deleted_at   IS NULL
        AND t.type         IN ('expense', 'income')
      GROUP BY t.type
      ''',
      [currencyCode, windowStart, windowEnd],
    );
    var income = 0;
    var expense = 0;
    for (final r in rows) {
      final kind = r['kind'] as String;
      final total = _asInt(r['total_cents']);
      if (kind == 'income') income = total;
      if (kind == 'expense') expense = total;
    }
    return {'income': income, 'expense': expense};
  }

  static int _asInt(Object? raw) {
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    if (raw == null) return 0;
    return int.parse(raw.toString());
  }
}
