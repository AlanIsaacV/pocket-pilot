import 'package:sqflite/sqflite.dart';

import 'package:pocket_pilot/src/core/db/database_helper.dart';
import 'package:pocket_pilot/src/features/user_preferences/domain/user_preference.dart';

class UserPreferenceLocalStore {
  final DatabaseHelper _db;

  UserPreferenceLocalStore({required DatabaseHelper db}) : _db = db;

  Future<List<UserPreferenceModel>> listPreferences() async {
    final db = await _db.database;
    final rows = await db.query(
      'user_preferences',
      where: 'deleted_at IS NULL',
      orderBy: 'pref_key ASC',
    );
    return rows.map(UserPreferenceModel.fromMap).toList();
  }

  Future<UserPreferenceModel?> getByKey(String prefKey) async {
    final db = await _db.database;
    final rows = await db.query(
      'user_preferences',
      where: 'pref_key = ? AND deleted_at IS NULL',
      whereArgs: [prefKey],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return UserPreferenceModel.fromMap(rows.first);
  }

  Future<void> upsert(UserPreferenceModel model) async {
    final db = await _db.database;
    await db.insert(
      'user_preferences',
      model.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> softDelete(String prefKey, DateTime deletedAt) async {
    final db = await _db.database;
    await db.update(
      'user_preferences',
      {
        'deleted_at': deletedAt.toIso8601String(),
        'updated_at': deletedAt.toIso8601String(),
      },
      where: 'pref_key = ? AND (deleted_at IS NULL OR updated_at < ?)',
      whereArgs: [prefKey, deletedAt.toIso8601String()],
    );
  }
}
