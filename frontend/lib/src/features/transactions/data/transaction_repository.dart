// ============================================================
// TransactionRepository — orquestación offline-first para transacciones
// ============================================================
//
// Las transacciones dependen de las categorías para saber si son
// ingreso o gasto. El repositorio consulta el tipo de cada categoría
// a través de CategoryLocalStore al construir los modelos de dominio.
//
// Este repositorio no contiene SQL: delega toda persistencia en
// TransactionLocalStore (y CategoryLocalStore para el lookup de tipo)
// y toda comunicación remota en TransactionRemoteService.

import 'dart:async';

import 'package:pocket_pilot/src/features/categories/data/category_local_store.dart';
import 'package:pocket_pilot/src/features/transactions/data/transaction_local_store.dart';
import 'package:pocket_pilot/src/features/transactions/data/transaction_remote_service.dart';
import 'package:pocket_pilot/src/features/transactions/domain/transaction.dart';

class TransactionRepository {
  final TransactionLocalStore _local;
  final TransactionRemoteService _remote;
  final CategoryLocalStore _categoryStore;

  TransactionRepository({
    required TransactionLocalStore local,
    required TransactionRemoteService remote,
    required CategoryLocalStore categoryStore,
  })  : _local = local,
        _remote = remote,
        _categoryStore = categoryStore;

  // ----------------------------------------------------------
  // READ
  // ----------------------------------------------------------

  /// Lee las transacciones almacenadas localmente y las enriquece
  /// con el tipo de categoría de cada una.
  Future<List<TransactionModel>> getTransactions(String userId) async {
    final rows = await _local.queryRows(userId);
    return _rowsToModels(rows);
  }

  /// Descarga transacciones del servidor y las persiste en SQLite.
  /// Propaga errores para que el ViewModel pueda mostrarlos.
  Future<void> syncRemote(String userId) async {
    final remoteTransactions = await _remote.listTransactions(userId);
    final rows = remoteTransactions
        .map((proto) => {
              'id': proto.id,
              'user_id': proto.userId,
              'account_id': proto.accountId,
              'category_id': proto.categoryId,
              'amount':
                  proto.hasAmount() ? proto.amount.amountMinor.toInt() : 0,
              'currency_code':
                  proto.hasAmount() ? proto.amount.currencyCode : 'MXN',
              'description': proto.description,
              'date': proto.date,
              'created_at': proto.createdAt.toDateTime().toIso8601String(),
              'updated_at': proto.updatedAt.toDateTime().toIso8601String(),
            })
        .toList();
    await _local.upsertRows(rows);
  }

  /// Convierte filas de BD a modelos de dominio, enriqueciendo cada
  /// transacción con el tipo de su categoría.
  Future<List<TransactionModel>> _rowsToModels(
    List<Map<String, dynamic>> rows,
  ) async {
    final models = <TransactionModel>[];
    for (final row in rows) {
      // Consultamos el tipo de categoría desde la tabla local.
      // En una app de producción esto se haría con un JOIN SQL para evitar
      // N+1 queries. Para el MVP es aceptable.
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
    required String userId,
    required String accountId,
    required String categoryId,
    required int amountMinor,
    required String currencyCode,
    required String description,
    required String date, // YYYY-MM-DD
  }) async {
    final now = DateTime.now().toUtc();

    await _local.upsertRow({
      'id': id,
      'user_id': userId,
      'account_id': accountId,
      'category_id': categoryId,
      'amount': amountMinor,
      'currency_code': currencyCode,
      'description': description,
      'date': date,
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    });

    unawaited(() async {
      try {
        await _remote.createTransaction(
          userId: userId,
          accountId: accountId,
          categoryId: categoryId,
          amountMinor: amountMinor,
          currencyCode: currencyCode,
          description: description,
          date: date,
        );
      } catch (_) {}
    }());
  }
}
