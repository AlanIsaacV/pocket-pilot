// ============================================================
// SyncOutbox — DAO para la cola de operaciones pendientes
// ============================================================
//
// Cada operación local (create/update/delete) que aún no se ha
// enviado al servidor se registra aquí como una entrada pendiente.
// SyncService lee esta tabla durante la fase PUSH del sync.
//
// El índice UNIQUE en (entity_type, entity_id) garantiza que solo
// exista una entrada pendiente por registro: si el usuario edita el
// mismo registro dos veces offline, solo se envía el estado final.

import 'package:sqflite/sqflite.dart';

import 'package:pocket_pilot/src/core/db/database_helper.dart';

class OutboxEntry {
  final int id;
  final String entityType;
  final String entityId;
  final String operation; // 'upsert' | 'delete'
  final String payload; // JSON con los campos del registro
  final int retryCount;
  final String? lastError;

  const OutboxEntry({
    required this.id,
    required this.entityType,
    required this.entityId,
    required this.operation,
    required this.payload,
    required this.retryCount,
    this.lastError,
  });

  factory OutboxEntry.fromMap(Map<String, dynamic> map) {
    return OutboxEntry(
      id: map['id'] as int,
      entityType: map['entity_type'] as String,
      entityId: map['entity_id'] as String,
      operation: map['operation'] as String,
      payload: map['payload'] as String,
      retryCount: map['retry_count'] as int,
      lastError: map['last_error'] as String?,
    );
  }
}

class SyncOutbox {
  final DatabaseHelper _db;

  // Máximo de reintentos antes de abandonar una entrada.
  // Superado este límite, getPending() la ignorará.
  static const int _maxRetries = 3;

  SyncOutbox({required DatabaseHelper db}) : _db = db;

  // ----------------------------------------------------------
  // WRITE
  // ----------------------------------------------------------

  /// Encola una operación pendiente.
  ///
  /// Si ya existía una entrada para (entityType, entityId), la reemplaza
  /// con el estado más reciente (garantizado por el índice UNIQUE +
  /// ConflictAlgorithm.replace).
  Future<void> enqueue({
    required String entityType,
    required String entityId,
    required String operation,
    required String payload,
  }) async {
    final db = await _db.database;
    await db.insert(
      'sync_outbox',
      {
        'entity_type': entityType,
        'entity_id': entityId,
        'operation': operation,
        'payload': payload,
        'retry_count': 0,
        'last_error': null,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Elimina la entrada: operación enviada al servidor exitosamente.
  Future<void> markSuccess(int id) async {
    final db = await _db.database;
    await db.delete('sync_outbox', where: 'id = ?', whereArgs: [id]);
  }

  /// Incrementa retry_count y guarda el mensaje de error.
  Future<void> markFailed(int id, String error) async {
    final db = await _db.database;
    await db.rawUpdate(
      'UPDATE sync_outbox SET retry_count = retry_count + 1, last_error = ? WHERE id = ?',
      [error, id],
    );
  }

  // ----------------------------------------------------------
  // READ
  // ----------------------------------------------------------

  /// Retorna las entradas pendientes de un tipo de entidad,
  /// ordenadas por id (FIFO). Excluye las que superaron _maxRetries.
  Future<List<OutboxEntry>> getPending(String entityType) async {
    final db = await _db.database;
    final rows = await db.query(
      'sync_outbox',
      where: 'entity_type = ? AND retry_count < ?',
      whereArgs: [entityType, _maxRetries],
      orderBy: 'id ASC',
    );
    return rows.map(OutboxEntry.fromMap).toList();
  }

  /// Busca una entrada pendiente para un registro específico.
  /// Retorna null si no hay operación pendiente para ese registro.
  Future<OutboxEntry?> findByEntityId(
      String entityType, String entityId) async {
    final db = await _db.database;
    final rows = await db.query(
      'sync_outbox',
      where: 'entity_type = ? AND entity_id = ?',
      whereArgs: [entityType, entityId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return OutboxEntry.fromMap(rows.first);
  }
}
