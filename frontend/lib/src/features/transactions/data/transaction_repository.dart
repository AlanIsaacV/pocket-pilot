// ============================================================
// TransactionRepository — orquestación offline-first para transacciones
// ============================================================
//
// Las transacciones dependen de las categorías para saber si son
// ingreso o gasto. El repositorio consulta el tipo de cada categoría
// a través de CategoryLocalStore al construir los modelos de dominio.
//
// Patrón outbox: escribe en SQLite local de forma inmediata y encola
// la operación en sync_outbox para que SyncService la envíe al servidor.

import 'dart:convert';

import 'package:pocket_pilot/src/core/sync/sync_outbox.dart';
import 'package:pocket_pilot/src/features/transactions/data/transaction_local_store.dart';
import 'package:pocket_pilot/src/features/transactions/domain/transaction.dart';

class TransactionRepository {
  final TransactionLocalStore _local;
  final SyncOutbox _outbox;

  TransactionRepository({
    required TransactionLocalStore local,
    required SyncOutbox outbox,
  }) : _local = local,
       _outbox = outbox;

  // ----------------------------------------------------------
  // READ
  // ----------------------------------------------------------

  /// Lee las transacciones almacenadas localmente y las enriquece
  /// con el tipo de categoría de cada una.
  Future<List<TransactionModel>> getTransactions() async {
    final rows = await _local.queryRows();
    return _rowsToModels(rows);
  }

  /// Convierte filas de BD a modelos de dominio, enriqueciendo cada
  /// transacción con el tipo de su categoría.
  Future<List<TransactionModel>> _rowsToModels(
    List<Map<String, dynamic>> rows,
  ) async {
    final models = <TransactionModel>[];
    for (final row in rows) {
      models.add(TransactionModel.fromMap(row));
    }
    return models;
  }

  // ----------------------------------------------------------
  // WRITE
  // ----------------------------------------------------------

  Future<void> createTransaction({
    required String id,
    required String accountId,
    required String categoryId,
    required int amountMinor,
    required String currencyCode,
    required String description,
    required String date, // YYYY-MM-DD
    required String type,
    required String status, // 'pending' o 'cleared'
  }) async {
    final now = DateTime.now().toUtc();
    final model = TransactionModel(
      id: id,
      accountId: accountId,
      categoryId: categoryId,
      amount: amountMinor,
      currencyCode: currencyCode,
      description: description,
      date: date,
      type: type,
      status: status,
      createdAt: now,
      updatedAt: now,
    );

    await _local.upsertRow(model.toMap());
    await _outbox.enqueue(
      entityType: 'transaction',
      entityId: id,
      operation: 'upsert',
      payload: jsonEncode(model.toServerMap()),
    );
  }

  Future<void> updateTransaction({
    required String id,
    required String accountId,
    required String categoryId,
    required int amountMinor,
    required String currencyCode,
    required String description,
    required String date, // YYYY-MM-DD
    required String type,
    required String status,
    required DateTime createdAt,
  }) async {
    final model = TransactionModel(
      id: id,
      accountId: accountId,
      categoryId: categoryId,
      amount: amountMinor,
      currencyCode: currencyCode,
      description: description,
      date: date,
      type: type,
      status: status,
      createdAt: createdAt,
      updatedAt: DateTime.now().toUtc(),
    );

    await _local.upsertRow(model.toMap());
    await _outbox.enqueue(
      entityType: 'transaction',
      entityId: id,
      operation: 'upsert',
      payload: jsonEncode(model.toServerMap()),
    );
  }

  Future<void> deleteTransaction(String id) async {
    final now = DateTime.now().toUtc();
    await _local.softDelete(id, now);
    await _outbox.enqueue(
      entityType: 'transaction',
      entityId: id,
      operation: 'delete',
      payload: jsonEncode({'deleted_at': now.toIso8601String()}),
    );
  }
}
