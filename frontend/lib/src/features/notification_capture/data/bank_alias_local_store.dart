import 'package:sqflite/sqflite.dart';

import 'package:pocket_pilot/src/core/db/database_helper.dart';
import 'package:pocket_pilot/src/features/notification_capture/domain/bank_alias.dart';

class BankAliasLocalStore {
  final DatabaseHelper _db;

  BankAliasLocalStore({required DatabaseHelper db}) : _db = db;

  Future<List<BankAliasModel>> listActive() async {
    final db = await _db.database;
    final rows = await db.query(
      'bank_aliases',
      where: 'deleted_at IS NULL',
      orderBy: 'updated_at DESC',
    );
    return rows.map(BankAliasModel.fromMap).toList();
  }

  Future<BankAliasModel?> getByPackageName(String packageName) async {
    final db = await _db.database;
    final rows = await db.query(
      'bank_aliases',
      where: 'package_name = ? AND deleted_at IS NULL',
      whereArgs: [packageName],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return BankAliasModel.fromMap(rows.first);
  }

  /// Lookup directo por bank_id — usado por el repository para resolver
  /// `_bankIdForPackage` (ver Fase 8).
  Future<BankAliasModel?> getByPackageNameIncludingDeleted(
      String packageName) async {
    final db = await _db.database;
    final rows = await db.query(
      'bank_aliases',
      where: 'package_name = ?',
      whereArgs: [packageName],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return BankAliasModel.fromMap(rows.first);
  }

  Future<void> upsert(BankAliasModel model) async {
    final db = await _db.database;
    await db.insert(
      'bank_aliases',
      model.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> upsertRow(Map<String, dynamic> row) async {
    final db = await _db.database;
    await db.insert(
      'bank_aliases',
      row,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> softDelete(String id, DateTime deletedAt) async {
    final db = await _db.database;
    await db.update(
      'bank_aliases',
      {
        'deleted_at': deletedAt.toUtc().toIso8601String(),
        'updated_at': deletedAt.toUtc().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
