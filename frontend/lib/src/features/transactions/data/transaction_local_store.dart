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
import 'package:pocket_pilot/src/features/transactions/domain/transaction_filter.dart';

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

  /// Busca la transaccion inicial de una cuenta usando filtros estructurales:
  /// - misma cuenta,
  /// - mismo tipo esperado segun la cuenta,
  /// - sin categoria,
  /// - no es transferencia (linked_transaction_id NULL),
  /// - activa (deleted_at IS NULL).
  ///
  /// Si hay mas de una candidata, retorna la mas antigua.
  Future<Map<String, dynamic>?> queryInitialBalanceRow({
    required String accountId,
    required String type,
  }) async {
    final db = await _db.database;
    final rows = await db.query(
      'transactions',
      where:
          'account_id = ? AND type = ? AND category_id IS NULL AND linked_transaction_id IS NULL AND deleted_at IS NULL',
      whereArgs: [accountId, type],
      orderBy: 'created_at ASC, id ASC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first;
  }

  /// Retorna los account IDs de la última transferencia realizada,
  /// o null si no existe ninguna.
  Future<({String fromAccountId, String toAccountId})?> queryLastTransferPair() async {
    final db = await _db.database;

    final outRows = await db.query(
      'transactions',
      columns: ['account_id', 'linked_transaction_id'],
      where: "type = 'transfer_out' AND deleted_at IS NULL",
      orderBy: 'date DESC, created_at DESC',
      limit: 1,
    );
    if (outRows.isEmpty) return null;

    final fromAccountId = outRows.first['account_id'] as String?;
    final linkedId = outRows.first['linked_transaction_id'] as String?;
    if (fromAccountId == null || linkedId == null) return null;

    final inRows = await db.query(
      'transactions',
      columns: ['account_id'],
      where: "id = ? AND deleted_at IS NULL",
      whereArgs: [linkedId],
      limit: 1,
    );
    if (inRows.isEmpty) return null;

    final toAccountId = inRows.first['account_id'] as String?;
    if (toAccountId == null) return null;

    return (fromAccountId: fromAccountId, toAccountId: toAccountId);
  }

  /// Queries transactions matching [filter] with a dynamic WHERE clause.
  /// Returns raw maps (repository enriches with category type).
  Future<List<Map<String, dynamic>>> queryRowsFiltered(
    TransactionFilter filter,
  ) async {
    final db = await _db.database;
    final where = StringBuffer('deleted_at IS NULL');
    final args = <dynamic>[];

    // Date range (always present)
    where.write(' AND date BETWEEN ? AND ?');
    args.addAll([filter.dateFrom, filter.dateTo]);

    // Account
    if (filter.accountId != null) {
      where.write(' AND account_id = ?');
      args.add(filter.accountId);
    }

    // Categories
    if (filter.categoryIds.isNotEmpty) {
      final placeholders = List.filled(filter.categoryIds.length, '?').join(',');
      where.write(' AND category_id IN ($placeholders)');
      args.addAll(filter.categoryIds);
    }

    // Type
    final typeValues = filter.typeValues;
    if (typeValues != null) {
      final placeholders = List.filled(typeValues.length, '?').join(',');
      where.write(' AND type IN ($placeholders)');
      args.addAll(typeValues);
    }

    // Status
    if (filter.status != null) {
      where.write(' AND status = ?');
      args.add(filter.status);
    }

    // Currency
    if (filter.currencyCode != null) {
      where.write(' AND currency_code = ?');
      args.add(filter.currencyCode);
    }

    return db.query(
      'transactions',
      where: where.toString(),
      whereArgs: args,
      orderBy: 'date DESC',
    );
  }

  /// Returns the IDs of the N most frequently used categories.
  Future<List<String>> queryTopCategoryIds({int limit = 5}) async {
    final db = await _db.database;
    final rows = await db.rawQuery(
      'SELECT category_id, COUNT(*) as cnt '
      'FROM transactions '
      'WHERE deleted_at IS NULL AND category_id IS NOT NULL '
      'GROUP BY category_id '
      'ORDER BY cnt DESC '
      'LIMIT ?',
      [limit],
    );
    return rows.map((r) => r['category_id'] as String).toList();
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
  Future<void> softDelete(
    String id,
    DateTime deletedAt, {
    String? linkedId,
  }) async {
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
      batch.update(
        'transactions',
        values,
        where: where,
        whereArgs: [linkedId, ts],
      );
      await batch.commit(noResult: true);
    } else {
      await db.update(
        'transactions',
        values,
        where: where,
        whereArgs: [id, ts],
      );
    }
  }
}
