import 'package:sqflite/sqflite.dart';

import 'package:pocket_pilot/src/core/db/database_helper.dart';
import 'package:pocket_pilot/src/features/tags/domain/tag.dart';

class TagLocalStore {
  final DatabaseHelper _db;

  TagLocalStore({required DatabaseHelper db}) : _db = db;

  Future<List<TagModel>> getTags() async {
    final db = await _db.database;
    final rows = await db.query(
      'tags',
      where: 'deleted_at IS NULL',
      orderBy: 'created_at ASC',
    );
    return rows.map(TagModel.fromMap).toList();
  }

  Future<void> upsert(TagModel model) async {
    final db = await _db.database;
    await db.insert(
      'tags',
      model.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> softDelete(String id, DateTime deletedAt) async {
    final db = await _db.database;
    await db.update(
      'tags',
      {
        'deleted_at': deletedAt.toIso8601String(),
        'updated_at': deletedAt.toIso8601String(),
      },
      where: 'id = ? AND (deleted_at IS NULL OR deleted_at < ?)',
      whereArgs: [id, deletedAt.toIso8601String()],
    );
  }
}
