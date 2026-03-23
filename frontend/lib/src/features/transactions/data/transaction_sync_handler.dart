import 'dart:convert';

import 'package:pocket_pilot/src/features/transactions/data/transaction_local_store.dart';
import 'package:pocket_pilot/src/features/transactions/data/transaction_remote_service.dart';
import 'package:pocket_pilot/src/core/sync/sync_handler.dart';

class TransactionSyncHandler implements SyncHandler {
  final TransactionLocalStore _local;
  final TransactionRemoteService _remote;

  TransactionSyncHandler({
    required TransactionLocalStore local,
    required TransactionRemoteService remote,
  })  : _local = local,
        _remote = remote;

  @override
  String get entityType => 'transaction';

  @override
  Future<SyncPullResult> pull(DateTime? updatedSince) async {
    final response = await _remote.listTransactions(updatedSince: updatedSince);

    final items = response.transactions.map((proto) {
      final row = {
        'id': proto.id,
        'account_id': proto.accountId,
        'category_id': proto.categoryId,
        'type': proto.type.name,
        'amount': proto.amountCents.toInt(),
        'currency_code': proto.currencyCode,
        'status': proto.status,
        'description': proto.description,
        'date': proto.date.toDateTime().toIso8601String().substring(0, 10),
        'created_at': proto.createdAt.toDateTime().toUtc().toIso8601String(),
        'updated_at': proto.updatedAt.toDateTime().toUtc().toIso8601String(),
        'deleted_at': proto.hasDeletedAt()
            ? proto.deletedAt.toDateTime().toUtc().toIso8601String()
            : null,
      };
      return SyncItem(
        id: proto.id,
        updatedAt: proto.updatedAt.toDateTime().toUtc(),
        data: row,
      );
    }).toList();

    return SyncPullResult(
      items: items,
      syncedAt: response.syncedAt.toDateTime().toUtc(),
    );
  }

  @override
  Future<void> saveLocally(Map<String, dynamic> data) async {
    await _local.upsertRow(data);
  }

  @override
  Future<SyncPushResult> pushUpsert(String payloadJson) async {
    final map = jsonDecode(payloadJson) as Map<String, dynamic>;
    final response = await _remote.upsertTransaction(map);

    if (response.conflictResolved) {
      final proto = response.transaction;
      final serverRow = {
        'id': proto.id,
        'account_id': proto.accountId,
        'category_id': proto.categoryId,
        'type': proto.type.name,
        'amount': proto.amountCents.toInt(),
        'currency_code': proto.currencyCode,
        'status': proto.status,
        'description': proto.description,
        'date': proto.date.toDateTime().toIso8601String().substring(0, 10),
        'created_at': proto.createdAt.toDateTime().toUtc().toIso8601String(),
        'updated_at': proto.updatedAt.toDateTime().toUtc().toIso8601String(),
        'deleted_at': null,
      };
      return SyncPushResult(conflictResolved: true, serverData: serverRow);
    }
    return const SyncPushResult(conflictResolved: false);
  }

  @override
  Future<void> pushDelete(String entityId, DateTime deletedAt) async {
    await _remote.deleteTransaction(id: entityId, deletedAt: deletedAt);
  }
}
