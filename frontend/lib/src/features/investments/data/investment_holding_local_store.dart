import 'package:sqflite/sqflite.dart';

import 'package:pocket_pilot/src/core/db/database_helper.dart';

class InvestmentHoldingLocalStore {
  final DatabaseHelper _db;

  InvestmentHoldingLocalStore({required DatabaseHelper db}) : _db = db;

  Future<List<Map<String, dynamic>>> queryRows() async {
    final db = await _db.database;
    return db.query(
      'investment_holdings',
      where: 'deleted_at IS NULL',
      orderBy: 'created_at DESC',
    );
  }

  Future<Map<String, dynamic>?> getById(String id) async {
    final db = await _db.database;
    final rows = await db.query(
      'investment_holdings',
      where: 'id = ? AND deleted_at IS NULL',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first;
  }

  Future<Map<String, dynamic>?> getByIdIncludingArchived(String id) async {
    final db = await _db.database;
    final rows = await db.query(
      'investment_holdings',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first;
  }

  Future<void> upsertRow(Map<String, dynamic> row) async {
    final db = await _db.database;
    await db.insert(
      'investment_holdings',
      row,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> softDelete(String id, DateTime deletedAt) async {
    final db = await _db.database;
    final ts = deletedAt.toUtc().toIso8601String();
    await db.update(
      'investment_holdings',
      {'deleted_at': ts, 'updated_at': ts},
      where: 'id = ? AND (deleted_at IS NULL OR deleted_at < ?)',
      whereArgs: [id, ts],
    );
  }
}
