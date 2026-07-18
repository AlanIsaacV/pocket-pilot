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
import 'package:pocket_pilot/src/features/transactions/domain/transaction_filter.dart';

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

  Future<List<TransactionModel>> getTransactions({
    TransactionFilter? filter,
  }) async {
    final rows = filter != null
        ? await _local.queryRowsFiltered(filter)
        : await _local.queryRows();
    return rows.map((r) => TransactionModel.fromMap(r)).toList();
  }

  Future<String?> getLastUsedAccountId() => _local.getLastUsedAccountId();

  Future<List<String>> getTopCategoryIdsForAccount(
    String accountId, {
    int limit = 5,
  }) => _local.queryTopCategoryIds(accountId: accountId, limit: limit);

  Future<({String fromAccountId, String toAccountId})?>
  getLastTransferAccountIds() => _local.queryLastTransferPair();

  Future<TransactionModel?> getInitialBalanceTransaction({
    required String accountId,
    required String type,
  }) async {
    final row = await _local.queryInitialBalanceRow(
      accountId: accountId,
      type: type,
    );
    if (row == null) return null;
    return TransactionModel.fromMap(row);
  }

  Future<TransactionModel?> getTransactionById(String id) async {
    final row = await _local.findRowById(id);
    if (row == null) return null;
    return TransactionModel.fromMap(row);
  }

  /// Confirma una transacción pendiente: cambia status a 'cleared' y
  /// preserva todos los demás campos (incluida la fecha). Idempotente:
  /// no hace nada si la transacción no existe o ya está cleared.
  ///
  /// No delega en `updateTransaction` porque esa signature no acepta
  /// `linkedTransactionId`/`yieldId`/`holdingId`/`lotId` y `upsertRow`
  /// reemplaza la fila completa, borrando esos campos en transfers,
  /// yields e inversiones.
  Future<void> confirmTransaction(String id) async {
    final current = await getTransactionById(id);
    if (current == null || current.status == 'cleared') return;

    final updated = TransactionModel(
      id: current.id,
      accountId: current.accountId,
      categoryId: current.categoryId,
      linkedTransactionId: current.linkedTransactionId,
      templateId: current.templateId,
      yieldId: current.yieldId,
      holdingId: current.holdingId,
      lotId: current.lotId,
      amount: current.amount,
      installmentsCount: current.installmentsCount,
      currencyCode: current.currencyCode,
      description: current.description,
      nature: current.nature,
      date: current.date,
      type: current.type,
      status: 'cleared',
      tags: current.tags,
      createdAt: current.createdAt,
      updatedAt: DateTime.now().toUtc(),
    );

    await _local.upsertRow(updated.toMap());
    await _outbox.enqueue(
      entityType: 'transaction',
      entityId: id,
      operation: 'upsert',
      payload: jsonEncode(updated.toServerMap()),
    );
  }

  // ----------------------------------------------------------
  // WRITE — income/expense
  // ----------------------------------------------------------

  Future<void> createTransaction({
    required String id,
    required String accountId,
    required String? categoryId,
    String? templateId,
    required int amountMinor,
    int installmentsCount = 1,
    required String currencyCode,
    required String description,
    String nature = '',
    required String date,
    required String type,
    required String status,
    required List<String> tags,
  }) async {
    final now = DateTime.now().toUtc();
    final model = TransactionModel(
      id: id,
      accountId: accountId,
      categoryId: categoryId,
      templateId: templateId,
      amount: amountMinor,
      installmentsCount: installmentsCount,
      currencyCode: currencyCode,
      description: description,
      nature: nature,
      date: date,
      type: type,
      status: status,
      tags: tags,
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
    required String? categoryId,
    String? templateId,
    required int amountMinor,
    int installmentsCount = 1,
    required String currencyCode,
    required String description,
    String nature = '',
    required String date,
    required String type,
    required String status,
    required List<String> tags,
    required DateTime createdAt,
  }) async {
    final model = TransactionModel(
      id: id,
      accountId: accountId,
      categoryId: categoryId,
      templateId: templateId,
      amount: amountMinor,
      installmentsCount: installmentsCount,
      currencyCode: currencyCode,
      description: description,
      nature: nature,
      date: date,
      type: type,
      status: status,
      tags: tags,
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
    required String descriptionOut,
    required String descriptionIn,
    required List<String> tags,
  }) async {
    final now = DateTime.now().toUtc();

    final outModel = TransactionModel(
      id: outId,
      accountId: fromAccountId,
      linkedTransactionId: inId,
      amount: amountOutCents,
      installmentsCount: 1,
      currencyCode: currencyOut,
      description: descriptionOut,
      date: date,
      type: 'transfer_out',
      status: 'cleared',
      tags: tags,
      createdAt: now,
      updatedAt: now,
    );

    final inModel = TransactionModel(
      id: inId,
      accountId: toAccountId,
      linkedTransactionId: outId,
      amount: amountInCents,
      installmentsCount: 1,
      currencyCode: currencyIn,
      description: descriptionIn,
      date: dateIn ?? date,
      type: 'transfer_in',
      status: 'cleared',
      tags: tags,
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
    required String descriptionOut,
    required String descriptionIn,
    required List<String> tags,
    required DateTime createdAt,
  }) async {
    final now = DateTime.now().toUtc();

    final outModel = TransactionModel(
      id: outId,
      accountId: fromAccountId,
      linkedTransactionId: inId,
      amount: amountOutCents,
      installmentsCount: 1,
      currencyCode: currencyOut,
      description: descriptionOut,
      date: date,
      type: 'transfer_out',
      status: 'cleared',
      tags: tags,
      createdAt: createdAt,
      updatedAt: now,
    );

    final inModel = TransactionModel(
      id: inId,
      accountId: toAccountId,
      linkedTransactionId: outId,
      amount: amountInCents,
      installmentsCount: 1,
      currencyCode: currencyIn,
      description: descriptionIn,
      date: dateIn ?? date,
      type: 'transfer_in',
      status: 'cleared',
      tags: tags,
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

  Future<void> deleteTransaction(
    String id, {
    String? linkedTransactionId,
  }) async {
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
