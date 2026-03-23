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
  Future<void> softDelete(String id, DateTime deletedAt) async {
    final db = await _db.database;
    await db.update(
      'transactions',
      {
        'deleted_at': deletedAt.toIso8601String(),
        'updated_at': deletedAt.toIso8601String(),
      },
      where: 'id = ? AND (deleted_at IS NULL OR deleted_at < ?)',
      whereArgs: [id, deletedAt.toIso8601String()],
    );
  }
}
