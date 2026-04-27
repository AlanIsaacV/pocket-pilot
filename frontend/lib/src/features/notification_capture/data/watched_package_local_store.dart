// ============================================================
// WatchedPackageLocalStore — DAO de watched_packages (local-only)
// ============================================================
//
// El NLS Kotlin lee esta tabla en `onListenerConnected()` para refrescar
// su set en memoria. Dart lo escribe desde el picker "Mis bancos".

import 'package:sqflite/sqflite.dart';

import 'package:pocket_pilot/src/core/db/database_helper.dart';
import 'package:pocket_pilot/src/features/notification_capture/domain/watched_package.dart';

class WatchedPackageLocalStore {
  final DatabaseHelper _db;

  WatchedPackageLocalStore({required DatabaseHelper db}) : _db = db;

  Future<List<WatchedPackageModel>> listAll() async {
    final db = await _db.database;
    final rows = await db.query(
      'watched_packages',
      orderBy: 'updated_at DESC',
    );
    return rows.map(WatchedPackageModel.fromMap).toList();
  }

  /// Set de package_names actualmente capturando. Útil para Dart-side
  /// resolución y para tests; el NLS Kotlin tiene su propia query
  /// (NotificationDb.getEnabledWatchedPackages).
  Future<Set<String>> listEnabledPackageNames() async {
    final db = await _db.database;
    final rows = await db.query(
      'watched_packages',
      columns: ['package_name'],
      where: 'enabled = 1',
    );
    return rows.map((r) => r['package_name'] as String).toSet();
  }

  Future<WatchedPackageModel?> getByPackageName(String packageName) async {
    final db = await _db.database;
    final rows = await db.query(
      'watched_packages',
      where: 'package_name = ?',
      whereArgs: [packageName],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return WatchedPackageModel.fromMap(rows.first);
  }

  Future<void> upsert(WatchedPackageModel model) async {
    final db = await _db.database;
    await db.insert(
      'watched_packages',
      model.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Cambia el toggle sin reemplazar todo el row. Si no existe, no hace
  /// nada — el llamador debería usar `upsert` para crear filas nuevas.
  Future<void> setEnabled({
    required String packageName,
    required bool enabled,
  }) async {
    final db = await _db.database;
    await db.update(
      'watched_packages',
      {
        'enabled': enabled ? 1 : 0,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'package_name = ?',
      whereArgs: [packageName],
    );
  }
}
