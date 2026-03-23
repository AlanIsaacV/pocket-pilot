// ============================================================
// AccountLocalStore (DAO) — todas las queries SQLite de cuentas
// ============================================================
//
// Responsabilidad única: ejecutar operaciones de base de datos
// sobre la tabla `accounts`. No contiene lógica de negocio.
//
// La tabla local es single-user (sin columna user_id).
// El filtro por usuario vive en el servidor; localmente se asume
// que toda la DB pertenece al usuario activo del dispositivo.

import 'package:sqflite/sqflite.dart';

import 'package:pocket_pilot/src/core/db/database_helper.dart';
import 'package:pocket_pilot/src/features/accounts/domain/account.dart';

class AccountLocalStore {
  final DatabaseHelper _db;

  AccountLocalStore({required DatabaseHelper db}) : _db = db;

  // ----------------------------------------------------------
  // READ
  // ----------------------------------------------------------

  /// Retorna todas las cuentas activas (no eliminadas), ordenadas
  /// por fecha de creación descendente.
  Future<List<AccountModel>> getAccounts() async {
    final db = await _db.database;
    final rows = await db.query(
      'accounts',
      where: 'deleted_at IS NULL',
      orderBy: 'created_at DESC',
    );
    return rows.map(AccountModel.fromMap).toList();
  }

  // ----------------------------------------------------------
  // WRITE
  // ----------------------------------------------------------

  /// Inserta o reemplaza una lista de cuentas en un solo batch.
  Future<void> upsertAll(List<AccountModel> accounts) async {
    final db = await _db.database;
    final batch = db.batch();
    for (final model in accounts) {
      batch.insert(
        'accounts',
        model.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  /// Inserta o reemplaza una cuenta individual.
  Future<void> upsert(AccountModel model) async {
    final db = await _db.database;
    await db.insert(
      'accounts',
      model.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Marca una cuenta como eliminada (soft delete) actualizando deleted_at.
  Future<void> softDelete(String id, DateTime deletedAt) async {
    final db = await _db.database;
    await db.update(
      'accounts',
      {'deleted_at': deletedAt.toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
