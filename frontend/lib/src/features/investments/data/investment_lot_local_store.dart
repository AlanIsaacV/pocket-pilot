import 'package:sqflite/sqflite.dart';

import 'package:pocket_pilot/src/core/db/database_helper.dart';

class InvestmentLotLocalStore {
  final DatabaseHelper _db;

  InvestmentLotLocalStore({required DatabaseHelper db}) : _db = db;

  Future<List<Map<String, dynamic>>> queryAll() async {
    final db = await _db.database;
    return db.query(
      'investment_lots',
      where: 'deleted_at IS NULL',
      orderBy: 'occurred_at DESC, created_at DESC',
    );
  }

  /// All lots (including deleted) so the generator can reconcile transactions
  /// when a lot is soft-deleted.
  Future<List<Map<String, dynamic>>> queryAllIncludingDeleted() async {
    final db = await _db.database;
    return db.query(
      'investment_lots',
      orderBy: 'occurred_at ASC, created_at ASC',
    );
  }

  Future<List<Map<String, dynamic>>> queryByHolding(String holdingId) async {
    final db = await _db.database;
    return db.query(
      'investment_lots',
      where: 'holding_id = ? AND deleted_at IS NULL',
      whereArgs: [holdingId],
      orderBy: 'occurred_at ASC, created_at ASC',
    );
  }

  Future<List<Map<String, dynamic>>> queryByAccount(String accountId) async {
    final db = await _db.database;
    return db.query(
      'investment_lots',
      where: 'account_id = ? AND deleted_at IS NULL',
      whereArgs: [accountId],
      orderBy: 'occurred_at DESC, created_at DESC',
    );
  }

  /// Returns the account_id of the most-recently-updated active lot for the
  /// user (used as "last used" default in the lot form).
  Future<String?> getLastUsedAccountId() async {
    final db = await _db.database;
    final rows = await db.query(
      'investment_lots',
      columns: ['account_id'],
      where: 'account_id IS NOT NULL',
      orderBy: 'updated_at DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['account_id'] as String?;
  }

  Future<Map<String, dynamic>?> getById(String id) async {
    final db = await _db.database;
    final rows = await db.query(
      'investment_lots',
      where: 'id = ? AND deleted_at IS NULL',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first;
  }

  Future<void> upsertRow(Map<String, dynamic> row) async {
    final db = await _db.database;
    await db.insert(
      'investment_lots',
      row,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> softDelete(String id, DateTime deletedAt) async {
    final db = await _db.database;
    final ts = deletedAt.toUtc().toIso8601String();
    await db.update(
      'investment_lots',
      {'deleted_at': ts, 'updated_at': ts},
      where: 'id = ? AND (deleted_at IS NULL OR deleted_at < ?)',
      whereArgs: [id, ts],
    );
  }
}
