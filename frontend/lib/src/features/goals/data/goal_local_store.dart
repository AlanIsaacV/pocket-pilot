import 'package:sqflite/sqflite.dart';

import 'package:pocket_pilot/src/core/db/database_helper.dart';

class GoalLocalStore {
  final DatabaseHelper _db;

  GoalLocalStore({required DatabaseHelper db}) : _db = db;

  Future<List<Map<String, dynamic>>> queryRows() async {
    final db = await _db.database;
    return db.query(
      'goals',
      where: 'deleted_at IS NULL',
      orderBy: 'created_at DESC',
    );
  }

  Future<void> upsertRow(Map<String, dynamic> row) async {
    final db = await _db.database;
    await db.insert('goals', row, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> upsertRows(List<Map<String, dynamic>> rows) async {
    final db = await _db.database;
    final batch = db.batch();
    for (final row in rows) {
      batch.insert('goals', row, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<void> softDelete(String id, DateTime deletedAt) async {
    final db = await _db.database;
    final ts = deletedAt.toUtc().toIso8601String();
    await db.update(
      'goals',
      {'deleted_at': ts, 'updated_at': ts},
      where: 'id = ? AND (deleted_at IS NULL OR deleted_at < ?)',
      whereArgs: [id, ts],
    );
  }

  /// Sum of `bank` + `cash` balances grouped by currency. Uses the same
  /// accounting rules as `DashboardLocalStore.getBalancesPerAccount` so that
  /// goal progress aligns with `liquidAssetsCents`.
  Future<Map<String, int>> getLiquidByCurrency() async {
    final db = await _db.database;
    final rows = await db.rawQuery('''
      SELECT
        a.currency_code AS currency_code,
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
      WHERE a.deleted_at IS NULL AND a.type IN ('bank', 'cash')
      GROUP BY a.currency_code
    ''');

    final result = <String, int>{};
    for (final row in rows) {
      final code = row['currency_code'] as String?;
      if (code == null) continue;
      final raw = row['balance_cents'];
      final cents = raw is int ? raw : (raw as num?)?.toInt() ?? 0;
      result[code] = cents;
    }
    return result;
  }
}
