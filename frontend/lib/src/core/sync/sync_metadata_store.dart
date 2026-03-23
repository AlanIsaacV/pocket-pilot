// ============================================================
// SyncMetadataStore — DAO para el cursor de sync por entidad
// ============================================================
//
// Guarda el timestamp del último sync exitoso por tipo de entidad.
// SyncService usa este valor como cursor para el delta pull:
//   - Si last_synced_at es null → primer sync, trae todos los registros.
//   - Si last_synced_at está definido → delta sync, trae solo los
//     registros con updated_at > last_synced_at.
//
// El servidor retorna synced_at (su timestamp al momento de la query).
// Guardamos ese valor (no el timestamp local) para evitar problemas
// de drift de reloj entre dispositivo y servidor.

import 'package:sqflite/sqflite.dart';

import 'package:pocket_pilot/src/core/db/database_helper.dart';

class SyncMetadataStore {
  final DatabaseHelper _db;

  SyncMetadataStore({required DatabaseHelper db}) : _db = db;

  /// Retorna el timestamp del último sync exitoso, o null si nunca sincronizó.
  Future<DateTime?> getLastSyncedAt(String entityType) async {
    final db = await _db.database;
    final rows = await db.query(
      'sync_metadata',
      where: 'entity_type = ?',
      whereArgs: [entityType],
      limit: 1,
    );
    if (rows.isEmpty || rows.first['last_synced_at'] == null) return null;
    return DateTime.parse(rows.first['last_synced_at'] as String);
  }

  /// Actualiza (o inserta) el timestamp del último sync exitoso.
  Future<void> updateLastSyncedAt(String entityType, DateTime syncedAt) async {
    final db = await _db.database;
    await db.insert(
      'sync_metadata',
      {
        'entity_type': entityType,
        'last_synced_at': syncedAt.toUtc().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
