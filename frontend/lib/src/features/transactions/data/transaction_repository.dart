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
import 'package:pocket_pilot/src/features/categories/data/category_local_store.dart';
import 'package:pocket_pilot/src/features/transactions/data/transaction_local_store.dart';
import 'package:pocket_pilot/src/features/transactions/domain/transaction.dart';

class TransactionRepository {
  final TransactionLocalStore _local;
  final SyncOutbox _outbox;
  final CategoryLocalStore _categoryStore;

  TransactionRepository({
    required TransactionLocalStore local,
    required SyncOutbox outbox,
    required CategoryLocalStore categoryStore,
  })  : _local = local,
        _outbox = outbox,
        _categoryStore = categoryStore;

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
      final categoryType =
          await _categoryStore.getCategoryType(row['category_id'] as String);
      models.add(TransactionModel.fromMap(row, categoryType: categoryType));
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
      createdAt: now,
      updatedAt: now,
      categoryType: await _categoryStore.getCategoryType(categoryId),
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
