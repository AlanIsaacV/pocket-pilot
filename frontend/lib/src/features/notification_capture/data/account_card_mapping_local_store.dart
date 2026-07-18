import 'package:sqflite/sqflite.dart';

import 'package:pocket_pilot/src/core/db/database_helper.dart';
import 'package:pocket_pilot/src/features/notification_capture/domain/account_card_mapping.dart';

class AccountCardMappingLocalStore {
  final DatabaseHelper _db;

  AccountCardMappingLocalStore({required DatabaseHelper db}) : _db = db;

  /// Resolución para el flujo de notification capture: la fila activa más
  /// reciente para (bank_id, last_digits). Si el usuario re-mapeó la misma
  /// tarjeta a otra cuenta, esta query toma la última en ganar.
  Future<AccountCardMappingModel?> findActiveLatest({
    required String bankId,
    required String lastDigits,
  }) async {
    final db = await _db.database;
    final rows = await db.query(
      'account_card_mappings',
      where: 'bank_id = ? AND last_digits = ? AND deleted_at IS NULL',
      whereArgs: [bankId, lastDigits],
      orderBy: 'updated_at DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return AccountCardMappingModel.fromMap(rows.first);
  }

  /// Resolución para notificaciones sin dígitos: la fila activa más reciente
  /// para (bank_id, pattern_id), con la misma semántica LWW que dígitos.
  Future<AccountCardMappingModel?> findByBankAndPattern({
    required String bankId,
    required String patternId,
  }) async {
    final db = await _db.database;
    final rows = await db.query(
      'account_card_mappings',
      where: 'bank_id = ? AND pattern_id = ? AND deleted_at IS NULL',
      whereArgs: [bankId, patternId],
      orderBy: 'updated_at DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return AccountCardMappingModel.fromMap(rows.first);
  }

  Future<void> upsert(AccountCardMappingModel model) async {
    final db = await _db.database;
    await db.insert(
      'account_card_mappings',
      model.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> upsertRow(Map<String, dynamic> row) async {
    final db = await _db.database;
    await db.insert(
      'account_card_mappings',
      row,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
