// ============================================================
// PendingTransactionLocalStore — DAO de pending_transactions
// ============================================================

import 'package:sqflite/sqflite.dart';

import 'package:pocket_pilot/src/core/db/database_helper.dart';
import 'package:pocket_pilot/src/features/notification_capture/domain/pending_transaction.dart';

class PendingTransactionLocalStore {
  final DatabaseHelper _db;

  PendingTransactionLocalStore({required DatabaseHelper db}) : _db = db;

  Future<List<PendingTransactionModel>> listPending({int limit = 100}) async {
    final db = await _db.database;
    final rows = await db.query(
      'pending_transactions',
      where: "status = 'pending'",
      orderBy: 'created_at DESC',
      limit: limit,
    );
    return rows.map(PendingTransactionModel.fromMap).toList();
  }

  Future<PendingTransactionModel?> getById(String id) async {
    final db = await _db.database;
    final rows = await db.query(
      'pending_transactions',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return PendingTransactionModel.fromMap(rows.first);
  }

  Future<void> insert(PendingTransactionModel model) async {
    final db = await _db.database;
    await db.insert(
      'pending_transactions',
      model.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> updateStatus(String id, String status) async {
    final db = await _db.database;
    await db.update(
      'pending_transactions',
      {'status': status},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> update(PendingTransactionModel model) async {
    final db = await _db.database;
    await db.update(
      'pending_transactions',
      model.toMap(),
      where: 'id = ?',
      whereArgs: [model.id],
    );
  }
}
