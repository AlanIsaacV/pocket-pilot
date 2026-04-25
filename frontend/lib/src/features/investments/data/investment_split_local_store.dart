import 'package:sqflite/sqflite.dart';

import 'package:pocket_pilot/src/core/db/database_helper.dart';

class InvestmentSplitLocalStore {
  final DatabaseHelper _db;

  InvestmentSplitLocalStore({required DatabaseHelper db}) : _db = db;

  Future<List<Map<String, dynamic>>> queryAll() async {
    final db = await _db.database;
    return db.query(
      'investment_splits',
      where: 'deleted_at IS NULL',
      orderBy: 'occurred_at DESC, created_at DESC',
    );
  }

  Future<List<Map<String, dynamic>>> queryAllIncludingDeleted() async {
    final db = await _db.database;
    return db.query(
      'investment_splits',
      orderBy: 'occurred_at ASC, created_at ASC',
    );
  }

  Future<List<Map<String, dynamic>>> queryByHolding(String holdingId) async {
    final db = await _db.database;
    return db.query(
      'investment_splits',
      where: 'holding_id = ? AND deleted_at IS NULL',
      whereArgs: [holdingId],
      orderBy: 'occurred_at ASC, created_at ASC',
    );
  }

  Future<Map<String, dynamic>?> getById(String id) async {
    final db = await _db.database;
    final rows = await db.query(
      'investment_splits',
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
      'investment_splits',
      row,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> softDelete(String id, DateTime deletedAt) async {
    final db = await _db.database;
    final ts = deletedAt.toUtc().toIso8601String();
    await db.update(
      'investment_splits',
      {'deleted_at': ts, 'updated_at': ts},
      where: 'id = ? AND (deleted_at IS NULL OR deleted_at < ?)',
      whereArgs: [id, ts],
    );
  }
}
