import 'package:sqflite/sqflite.dart';

import 'package:pocket_pilot/src/core/db/database_helper.dart';
import 'package:pocket_pilot/src/features/notification_capture/domain/transaction_rule.dart';

class TransactionRuleLocalStore {
  final DatabaseHelper _db;

  TransactionRuleLocalStore({required DatabaseHelper db}) : _db = db;

  /// Devuelve la categoría sugerida para una description dada.
  /// Match: substring case-insensitive de match_text en description.
  /// Prefiere el texto coincidente más largo; empate: mayor priority, luego
  /// más reciente.
  Future<TransactionRuleModel?> findRuleForDescription(
    String description,
  ) async {
    if (description.trim().isEmpty) return null;
    final db = await _db.database;
    final rows = await db.query(
      'transaction_rules',
      where:
          "deleted_at IS NULL AND lower(?) LIKE '%' || lower(match_text) || '%'",
      whereArgs: [description],
      orderBy: 'LENGTH(match_text) DESC, priority DESC, updated_at DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return TransactionRuleModel.fromMap(rows.first);
  }

  /// Busca una regla activa con el mismo match_text exacto (case-insensitive).
  /// Usado al aprender: si ya existe la regla, la actualizamos en lugar de
  /// duplicar.
  Future<TransactionRuleModel?> findByExactMatchText(String matchText) async {
    final db = await _db.database;
    final rows = await db.query(
      'transaction_rules',
      where: 'lower(match_text) = lower(?) AND deleted_at IS NULL',
      whereArgs: [matchText],
      orderBy: 'updated_at DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return TransactionRuleModel.fromMap(rows.first);
  }

  Future<void> upsert(TransactionRuleModel model) async {
    final db = await _db.database;
    await db.insert(
      'transaction_rules',
      model.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> upsertRow(Map<String, dynamic> row) async {
    final db = await _db.database;
    await db.insert(
      'transaction_rules',
      row,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> incrementMatchCount(String id) async {
    final db = await _db.database;
    await db.rawUpdate(
      'UPDATE transaction_rules SET match_count = match_count + 1 WHERE id = ?',
      [id],
    );
  }
}
