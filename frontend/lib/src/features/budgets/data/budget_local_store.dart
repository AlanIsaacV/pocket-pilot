import 'package:flutter/foundation.dart';
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
      batch.insert(
        'budgets',
        row,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
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

  @visibleForTesting
  static int proratedAmountForPeriod({
    required int amountCents,
    required int installmentsCount,
    required int purchaseMonthIndex,
    required int periodStartMonthIndex,
    required int periodEndMonthIndex,
  }) {
    if (installmentsCount < 1) {
      throw ArgumentError.value(
        installmentsCount,
        'installmentsCount',
        'installmentsCount must be >= 1',
      );
    }

    final txStart = purchaseMonthIndex;
    final txEnd = purchaseMonthIndex + installmentsCount - 1;
    final overlapStart = txStart > periodStartMonthIndex
        ? txStart
        : periodStartMonthIndex;
    final overlapEnd = txEnd < periodEndMonthIndex
        ? txEnd
        : periodEndMonthIndex;
    final overlapMonths = overlapEnd >= overlapStart
        ? (overlapEnd - overlapStart + 1)
        : 0;
    if (overlapMonths == 0) return 0;

    final base = amountCents ~/ installmentsCount;
    final residual = amountCents % installmentsCount;
    final firstInstallmentInPeriod =
        purchaseMonthIndex >= periodStartMonthIndex &&
        purchaseMonthIndex <= periodEndMonthIndex;

    return (base * overlapMonths) + (firstInstallmentInPeriod ? residual : 0);
  }

  Future<int> computeSpentCents(String categoryId, String period) async {
    final db = await _db.database;
    final now = DateTime.now();

    final periodStartIdx = period == 'MONTHLY'
        ? (now.year * 12 + (now.month - 1))
        : (now.year * 12);
    final periodEndIdx = period == 'MONTHLY'
        ? periodStartIdx
        : (now.year * 12 + 11);

    final result = await db.rawQuery(
      '''
      WITH tx AS (
        SELECT
          type,
          amount_cents,
          installments_count,
          (CAST(strftime('%Y', date) AS INTEGER) * 12 + CAST(strftime('%m', date) AS INTEGER) - 1) AS purchase_idx
        FROM transactions
        WHERE category_id = ?
          AND deleted_at IS NULL
          AND installments_count >= 1
      )
      SELECT COALESCE(SUM(
        CASE
          WHEN type = 'expense' THEN
            (
              CAST(amount_cents / installments_count AS INTEGER) *
              MAX(0, MIN(purchase_idx + installments_count - 1, ?) - MAX(purchase_idx, ?) + 1)
            ) + CASE
                  WHEN purchase_idx BETWEEN ? AND ? THEN (amount_cents % installments_count)
                  ELSE 0
                END
          WHEN type = 'income' THEN
            -(
              (
                CAST(amount_cents / installments_count AS INTEGER) *
                MAX(0, MIN(purchase_idx + installments_count - 1, ?) - MAX(purchase_idx, ?) + 1)
              ) + CASE
                    WHEN purchase_idx BETWEEN ? AND ? THEN (amount_cents % installments_count)
                    ELSE 0
                  END
            )
          ELSE 0
        END
      ), 0) as spent
      FROM tx
      WHERE purchase_idx <= ?
        AND (purchase_idx + installments_count - 1) >= ?
    ''',
      [
        categoryId,
        periodEndIdx,
        periodStartIdx,
        periodStartIdx,
        periodEndIdx,
        periodEndIdx,
        periodStartIdx,
        periodStartIdx,
        periodEndIdx,
        periodEndIdx,
        periodStartIdx,
      ],
    );

    return (result.first['spent'] as num?)?.toInt() ?? 0;
  }
}
