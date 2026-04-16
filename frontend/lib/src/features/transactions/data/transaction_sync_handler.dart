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
  }) : _local = local,
       _remote = remote;

  @override
  String get entityType => 'transaction';

  @override
  int get syncOrder => 6;

  @override
  Future<SyncPullResult> pull(DateTime? updatedSince) async {
    final allItems = <SyncItem>[];
    late DateTime syncedAt;
    String? pageToken;

    do {
      final response = await _remote.listTransactions(
        updatedSince: updatedSince,
        pageToken: pageToken,
      );

      syncedAt = response.syncedAt.toDateTime().toUtc();

      for (final proto in response.transactions) {
        final model = TransactionModel.fromProto(proto);
        final row = <String, dynamic>{
          ...model.toMap(),
          'deleted_at': proto.hasDeletedAt()
              ? proto.deletedAt.toDateTime().toUtc().toIso8601String()
              : null,
        };
        allItems.add(SyncItem(
          id: proto.id,
          updatedAt: proto.updatedAt.toDateTime().toUtc(),
          data: row,
        ));
      }

      pageToken = response.hasPage() &&
              response.page.nextPageToken.isNotEmpty
          ? response.page.nextPageToken
          : null;
    } while (pageToken != null);

    return SyncPullResult(items: allItems, syncedAt: syncedAt);
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
        'deleted_at': response.transaction.hasDeletedAt()
            ? response.transaction.deletedAt
                  .toDateTime()
                  .toUtc()
                  .toIso8601String()
            : null,
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
