import 'package:sqflite/sqflite.dart';

import 'package:pocket_pilot/src/core/db/database_helper.dart';
import 'package:pocket_pilot/src/features/notification_capture/domain/parser_feedback.dart';

class ParserFeedbackLocalStore {
  final DatabaseHelper _db;

  ParserFeedbackLocalStore({required DatabaseHelper db}) : _db = db;

  Future<void> upsert(ParserFeedbackModel model) async {
    final db = await _db.database;
    await db.insert(
      'parser_feedback',
      model.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Para escribir el row que devuelve el server cuando hay LWW resolution.
  Future<void> upsertRow(Map<String, dynamic> row) async {
    final db = await _db.database;
    await db.insert(
      'parser_feedback',
      row,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Idempotencia/tests: confirmar que ya hay feedback para una sugerencia.
  Future<ParserFeedbackModel?> findByPendingTransactionId(
    String pendingTransactionId,
  ) async {
    final db = await _db.database;
    final rows = await db.query(
      'parser_feedback',
      where: 'pending_transaction_id = ?',
      whereArgs: [pendingTransactionId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return ParserFeedbackModel.fromMap(rows.first);
  }
}
