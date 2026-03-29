import 'dart:convert';

import 'package:pocket_pilot/src/features/transactions/data/transaction_local_store.dart';
import 'package:pocket_pilot/src/features/transactions/data/transaction_remote_service.dart';
import 'package:pocket_pilot/src/features/transactions/domain/transaction.dart';
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
  int get syncOrder => 4;

  @override
  Future<SyncPullResult> pull(DateTime? updatedSince) async {
    final response = await _remote.listTransactions(updatedSince: updatedSince);

    final items = response.transactions.map((proto) {
      final model = TransactionModel.fromProto(proto);
      final row = <String, dynamic>{
        ...model.toMap(),
        // fromProto/toMap doesn't carry deleted_at — add it from the proto.
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
      final model = TransactionModel.fromProto(response.transaction);
      final serverRow = <String, dynamic>{
        ...model.toMap(),
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
