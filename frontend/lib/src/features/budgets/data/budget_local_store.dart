import 'package:sqflite/sqflite.dart';

import 'package:pocket_pilot/src/core/db/database_helper.dart';

class BudgetLocalStore {
  final DatabaseHelper _db;

  BudgetLocalStore({required DatabaseHelper db}) : _db = db;

  Future<List<Map<String, dynamic>>> queryRows() async {
    final db = await _db.database;
    return db.query(
      'budgets',
      where: 'deleted_at IS NULL',
      orderBy: 'created_at DESC',
    );
  }

  Future<void> upsertRow(Map<String, dynamic> row) async {
    final db = await _db.database;
    await db.insert(
      'budgets',
      row,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> upsertRows(List<Map<String, dynamic>> rows) async {
    final db = await _db.database;
    final batch = db.batch();
    for (final row in rows) {
      batch.insert('budgets', row, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<void> softDelete(String id, DateTime deletedAt) async {
    final db = await _db.database;
    final ts = deletedAt.toUtc().toIso8601String();
    await db.update(
      'budgets',
      {'deleted_at': ts, 'updated_at': ts},
      where: 'id = ? AND (deleted_at IS NULL OR deleted_at < ?)',
      whereArgs: [id, ts],
    );
  }

  Future<int> computeSpentCents(String categoryId, String period) async {
    final db = await _db.database;
    final now = DateTime.now();

    String startDate;
    String endDate;

    if (period == 'MONTHLY') {
      startDate =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-01';
      final lastDay = DateTime(now.year, now.month + 1, 0).day;
      endDate =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${lastDay.toString().padLeft(2, '0')}';
    } else {
      // YEARLY
      startDate = '${now.year}-01-01';
      endDate = '${now.year}-12-31';
    }

    final result = await db.rawQuery('''
      SELECT COALESCE(SUM(
        CASE
          WHEN type = 'expense' THEN amount_cents
          WHEN type = 'income' THEN -amount_cents
          ELSE 0
        END
      ), 0) as spent
      FROM transactions
      WHERE category_id = ?
        AND date >= ?
        AND date <= ?
        AND deleted_at IS NULL
    ''', [categoryId, startDate, endDate]);

    return (result.first['spent'] as num?)?.toInt() ?? 0;
  }
}
