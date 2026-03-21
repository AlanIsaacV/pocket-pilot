// ============================================================
// AccountLocalStore (DAO) — todas las queries SQLite de cuentas
// ============================================================
//
// Responsabilidad única: ejecutar operaciones de base de datos
// sobre la tabla `accounts`. No contiene lógica de negocio ni
// llama a servicios remotos.
//
// El Repository llama a este store; el store NO conoce al Repository.

import 'package:sqflite/sqflite.dart';

import 'package:pocket_pilot/src/core/db/database_helper.dart';
import 'package:pocket_pilot/src/features/accounts/domain/account.dart';

class AccountLocalStore {
  final DatabaseHelper _db;

  AccountLocalStore({required DatabaseHelper db}) : _db = db;

  // ----------------------------------------------------------
  // READ
  // ----------------------------------------------------------

  /// Retorna todas las cuentas no eliminadas del usuario, ordenadas
  /// por fecha de creación descendente (más recientes primero).
  Future<List<AccountModel>> getAccounts(String userId) async {
    final db = await _db.database;
    final rows = await db.query(
      'accounts',
      where: 'user_id = ? AND deleted_at IS NULL',
      whereArgs: [userId],
      orderBy: 'created_at DESC',
    );
    return rows.map(AccountModel.fromMap).toList();
  }

  // ----------------------------------------------------------
  // WRITE
  // ----------------------------------------------------------

  /// Inserta o reemplaza una lista de cuentas en un solo batch.
  /// Usado para sincronizar la respuesta del servidor.
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
  /// Usado para la escritura local inmediata al crear una cuenta.
  Future<void> upsert(AccountModel model) async {
    final db = await _db.database;
    await db.insert(
      'accounts',
      model.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
