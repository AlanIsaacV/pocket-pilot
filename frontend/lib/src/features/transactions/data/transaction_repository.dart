// ============================================================
// TransactionRepository — orquestación offline-first para transacciones
// ============================================================
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

  Future<List<TransactionModel>> getTransactions() async {
    final rows = await _local.queryRows();
    return rows.map((r) => TransactionModel.fromMap(r)).toList();
  }

  Future<String?> getLastUsedAccountId() => _local.getLastUsedAccountId();

  // ----------------------------------------------------------
  // WRITE — income/expense
  // ----------------------------------------------------------

  Future<void> createTransaction({
    required String id,
    required String accountId,
    required String categoryId,
    required int amountMinor,
    required String currencyCode,
    required String description,
    required String date,
    required String type,
    required String status,
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
    required String date,
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

  // ----------------------------------------------------------
  // WRITE — transfers (two linked legs)
  // ----------------------------------------------------------

  Future<void> createTransfer({
    required String outId,
    required String inId,
    required String fromAccountId,
    required String toAccountId,
    required int amountOutCents,
    required String currencyOut,
    required int amountInCents,
    required String currencyIn,
    required String date,
    String? dateIn,
    required String description,
    required List<String> tags,
  }) async {
    final now = DateTime.now().toUtc();

    final outModel = TransactionModel(
      id: outId,
      accountId: fromAccountId,
      linkedTransactionId: inId,
      amount: amountOutCents,
      currencyCode: currencyOut,
      description: description,
      date: date,
      type: 'transfer_out',
      status: 'cleared',
      createdAt: now,
      updatedAt: now,
    );

    final inModel = TransactionModel(
      id: inId,
      accountId: toAccountId,
      linkedTransactionId: outId,
      amount: amountInCents,
      currencyCode: currencyIn,
      description: description,
      date: dateIn ?? date,
      type: 'transfer_in',
      status: 'cleared',
      createdAt: now,
      updatedAt: now,
    );

    await _local.upsertRow(outModel.toMap());
    await _local.upsertRow(inModel.toMap());
    await _outbox.enqueue(
      entityType: 'transaction',
      entityId: outId,
      operation: 'upsert',
      payload: jsonEncode(outModel.toServerMap()),
    );
    await _outbox.enqueue(
      entityType: 'transaction',
      entityId: inId,
      operation: 'upsert',
      payload: jsonEncode(inModel.toServerMap()),
    );
  }

  Future<void> updateTransfer({
    required String outId,
    required String inId,
    required String fromAccountId,
    required String toAccountId,
    required int amountOutCents,
    required String currencyOut,
    required int amountInCents,
    required String currencyIn,
    required String date,
    String? dateIn,
    required String description,
    required List<String> tags,
    required DateTime createdAt,
  }) async {
    final now = DateTime.now().toUtc();

    final outModel = TransactionModel(
      id: outId,
      accountId: fromAccountId,
      linkedTransactionId: inId,
      amount: amountOutCents,
      currencyCode: currencyOut,
      description: description,
      date: date,
      type: 'transfer_out',
      status: 'cleared',
      createdAt: createdAt,
      updatedAt: now,
    );

    final inModel = TransactionModel(
      id: inId,
      accountId: toAccountId,
      linkedTransactionId: outId,
      amount: amountInCents,
      currencyCode: currencyIn,
      description: description,
      date: dateIn ?? date,
      type: 'transfer_in',
      status: 'cleared',
      createdAt: createdAt,
      updatedAt: now,
    );

    await _local.upsertRow(outModel.toMap());
    await _local.upsertRow(inModel.toMap());
    await _outbox.enqueue(
      entityType: 'transaction',
      entityId: outId,
      operation: 'upsert',
      payload: jsonEncode(outModel.toServerMap()),
    );
    await _outbox.enqueue(
      entityType: 'transaction',
      entityId: inId,
      operation: 'upsert',
      payload: jsonEncode(inModel.toServerMap()),
    );
  }

  // ----------------------------------------------------------
  // DELETE (with optional cascade for transfers)
  // ----------------------------------------------------------

  Future<void> deleteTransaction(String id, {String? linkedTransactionId}) async {
    final now = DateTime.now().toUtc();
    await _local.softDelete(id, now, linkedId: linkedTransactionId);
    await _outbox.enqueue(
      entityType: 'transaction',
      entityId: id,
      operation: 'delete',
      payload: jsonEncode({'deleted_at': now.toIso8601String()}),
    );
    if (linkedTransactionId != null) {
      await _outbox.enqueue(
        entityType: 'transaction',
        entityId: linkedTransactionId,
        operation: 'delete',
        payload: jsonEncode({'deleted_at': now.toIso8601String()}),
      );
    }
  }
}
