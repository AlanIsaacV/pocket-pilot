import 'dart:convert';

import 'package:pocket_pilot/src/features/accounts/data/account_local_store.dart';
import 'package:pocket_pilot/src/features/accounts/data/account_remote_service.dart';
import 'package:pocket_pilot/src/features/accounts/domain/account.dart';
import 'package:pocket_pilot/src/core/sync/sync_handler.dart';

class AccountSyncHandler implements SyncHandler {
  final AccountLocalStore _local;
  final AccountRemoteService _remote;

  AccountSyncHandler({
    required AccountLocalStore local,
    required AccountRemoteService remote,
  })  : _local = local,
        _remote = remote;

  @override
  String get entityType => 'account';

  @override
  int get syncOrder => 1;

  @override
  Future<SyncPullResult> pull(DateTime? updatedSince) async {
    final response = await _remote.listAccounts(updatedSince: updatedSince);

    final items = response.accounts.map((proto) {
      final model = AccountModel.fromProto(proto);
      return SyncItem(
        id: model.id,
        updatedAt: model.updatedAt,
        data: model.toMap(),
      );
    }).toList();

    return SyncPullResult(
      items: items,
      syncedAt: response.syncedAt.toDateTime().toUtc(),
    );
  }

  @override
  Future<void> saveLocally(Map<String, dynamic> data) async {
    await _local.upsert(AccountModel.fromMap(data));
  }

  @override
  Future<SyncPushResult> pushUpsert(String payloadJson) async {
    final map = jsonDecode(payloadJson) as Map<String, dynamic>;
    final response = await _remote.upsertAccount(map);

    if (response.conflictResolved) {
      final serverModel = AccountModel.fromProto(response.account);
      return SyncPushResult(
        conflictResolved: true,
        serverData: serverModel.toMap(),
      );
    }
    return const SyncPushResult(conflictResolved: false);
  }

  @override
  Future<void> pushDelete(String entityId, DateTime deletedAt) async {
    await _remote.deleteAccount(id: entityId, deletedAt: deletedAt);
  }
}
