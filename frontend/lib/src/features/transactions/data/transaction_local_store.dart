// ============================================================
// TransactionLocalStore (DAO) — todas las queries SQLite de transacciones
// ============================================================
//
// Responsabilidad única: ejecutar operaciones de base de datos sobre la
// tabla `transactions`. No contiene lógica de negocio ni llamadas remotas.
//
// Nota: las transacciones almacenadas en SQLite no llevan `category_type`
// (ese campo es derivado). El repositorio enriquece las filas crudas
// consultando CategoryLocalStore antes de construir los modelos de dominio.

import 'package:sqflite/sqflite.dart';

import 'package:pocket_pilot/src/core/db/database_helper.dart';

class TransactionLocalStore {
  final DatabaseHelper _db;

  TransactionLocalStore({required DatabaseHelper db}) : _db = db;

  // ----------------------------------------------------------
  // READ
  // ----------------------------------------------------------

  /// Retorna las filas crudas de transacciones activas, ordenadas
  /// por fecha descendente (más recientes primero).
  ///
  /// Devuelve Map en lugar de TransactionModel porque el modelo requiere
  /// `categoryType`, un campo derivado que el repositorio debe enriquecer
  /// consultando la tabla de categorías.
  Future<List<Map<String, dynamic>>> queryRows() async {
    final db = await _db.database;
    return db.query(
      'transactions',
      where: 'deleted_at IS NULL',
      orderBy: 'date DESC',
    );
  }

  /// Retorna el account_id de la transacción más recientemente usada
  /// (según updated_at), ignorando registros eliminados.
  Future<String?> getLastUsedAccountId() async {
    final db = await _db.database;
    final rows = await db.query(
      'transactions',
      columns: ['account_id'],
      where: 'deleted_at IS NULL',
      orderBy: 'updated_at DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['account_id'] as String?;
  }

  // ----------------------------------------------------------
  // WRITE
  // ----------------------------------------------------------

  /// Inserta o reemplaza una lista de filas en un solo batch.
  /// Usado para sincronizar la respuesta del servidor.
  Future<void> upsertRows(List<Map<String, dynamic>> rows) async {
    final db = await _db.database;
    final batch = db.batch();
    for (final row in rows) {
      batch.insert(
        'transactions',
        row,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  /// Inserta o reemplaza una fila individual.
  /// Usado para la escritura local inmediata al crear una transacción.
  Future<void> upsertRow(Map<String, dynamic> row) async {
    final db = await _db.database;
    await db.insert(
      'transactions',
      row,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Marca una transacción como eliminada (soft delete con LWW).
  /// Cuando [linkedId] no es null, elimina ambas transacciones en un batch
  /// atómico (usado para transferencias).
  Future<void> softDelete(String id, DateTime deletedAt, {String? linkedId}) async {
    final db = await _db.database;
    final values = {
      'deleted_at': deletedAt.toIso8601String(),
      'updated_at': deletedAt.toIso8601String(),
    };
    const where = 'id = ? AND (deleted_at IS NULL OR deleted_at < ?)';
    final ts = deletedAt.toIso8601String();

    if (linkedId != null) {
      final batch = db.batch();
      batch.update('transactions', values, where: where, whereArgs: [id, ts]);
      batch.update('transactions', values, where: where, whereArgs: [linkedId, ts]);
      await batch.commit(noResult: true);
    } else {
      await db.update('transactions', values, where: where, whereArgs: [id, ts]);
    }
  }
}
