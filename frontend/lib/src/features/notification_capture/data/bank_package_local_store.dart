// ============================================================
// BankPackageLocalStore — cache SQLite del catálogo global pull-only
// ============================================================

import 'package:sqflite/sqflite.dart';

import 'package:pocket_pilot/src/core/db/database_helper.dart';
import 'package:pocket_pilot/src/features/notification_capture/domain/bank_package.dart';

class BankPackageLocalStore {
  final DatabaseHelper _db;

  BankPackageLocalStore({required DatabaseHelper db}) : _db = db;

  Future<List<BankPackageModel>> listActive() async {
    final db = await _db.database;
    final rows = await db.query(
      'bank_packages',
      where: 'deleted_at IS NULL AND is_active = 1',
      orderBy: 'default_label ASC',
    );
    return rows.map(BankPackageModel.fromMap).toList();
  }

  Future<BankPackageModel?> getByPackageName(String packageName) async {
    final db = await _db.database;
    final rows = await db.query(
      'bank_packages',
      where: 'package_name = ? AND deleted_at IS NULL AND is_active = 1',
      whereArgs: [packageName],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return BankPackageModel.fromMap(rows.first);
  }

  /// Upsert desde sync delta-pull. La fila remota gana siempre — el cliente
  /// no edita estas entradas localmente.
  Future<void> upsertFromSync({
    required String packageName,
    required String bankId,
    required String defaultLabel,
    required DateTime updatedAt,
    DateTime? deletedAt,
  }) async {
    final db = await _db.database;
    await db.insert(
      'bank_packages',
      {
        'package_name': packageName,
        'bank_id': bankId,
        'default_label': defaultLabel,
        'is_active': 1,
        'updated_at': updatedAt.toUtc().toIso8601String(),
        'deleted_at': deletedAt?.toUtc().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
