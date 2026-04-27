// ============================================================
// PackageObservationLocalStore — DAO de package_observations
// ============================================================
//
// El NLS Kotlin escribe directo a esta tabla (vía NotificationDb.kt). Dart
// lee para poblar el picker "Mis bancos". También incluye `purgeOlderThan`
// para integrarse con el sweeper de retención (Fase 6 extendida).

import 'package:pocket_pilot/src/core/db/database_helper.dart';
import 'package:pocket_pilot/src/features/notification_capture/domain/package_observation.dart';

class PackageObservationLocalStore {
  final DatabaseHelper _db;

  PackageObservationLocalStore({required DatabaseHelper db}) : _db = db;

  /// UPSERT manual (Dart-side). El NLS Kotlin tiene su propio path análogo
  /// en NotificationDb.kt. Útil para tests y debug menu.
  Future<void> upsertObservation({
    required String packageName,
    required DateTime postedAt,
  }) async {
    final db = await _db.database;
    final iso = postedAt.toUtc().toIso8601String();
    await db.rawInsert(
      '''INSERT INTO package_observations
              (package_name, first_seen_at, last_seen_at, noti_count)
            VALUES (?, ?, ?, 1)
         ON CONFLICT(package_name) DO UPDATE SET
              last_seen_at = MAX(last_seen_at, excluded.last_seen_at),
              noti_count   = noti_count + 1''',
      [packageName, iso, iso],
    );
  }

  /// Lista los packages observados ordenados por last_seen_at desc.
  /// Filtra purged_at IS NULL para ocultar anonimizadas.
  Future<List<PackageObservationModel>> listActive({int limit = 200}) async {
    final db = await _db.database;
    final rows = await db.query(
      'package_observations',
      where: 'purged_at IS NULL',
      orderBy: 'last_seen_at DESC',
      limit: limit,
    );
    return rows.map(PackageObservationModel.fromMap).toList();
  }

  Future<PackageObservationModel?> getByPackageName(String packageName) async {
    final db = await _db.database;
    final rows = await db.query(
      'package_observations',
      where: 'package_name = ?',
      whereArgs: [packageName],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return PackageObservationModel.fromMap(rows.first);
  }

  /// Anonimización 90d. Marca purged_at en filas con last_seen_at < cutoff.
  /// El package_name se preserva por si vuelve a notificarse (futura
  /// observación re-activa la fila vía MAX en upsert). Devuelve cuántas
  /// filas se afectaron. Usado por CapturedNotificationsRetentionSweeper.
  Future<int> purgeOlderThan({
    required String cutoffIso,
    required String purgedAtIso,
  }) async {
    final db = await _db.database;
    return db.rawUpdate(
      '''UPDATE package_observations
            SET purged_at = ?
          WHERE last_seen_at < ?
            AND purged_at IS NULL''',
      [purgedAtIso, cutoffIso],
    );
  }
}
