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
}
