import 'dart:convert';

import 'package:pocket_pilot/src/core/sync/sync_handler.dart';
import 'package:pocket_pilot/src/features/notification_capture/data/transaction_rule_local_store.dart';
import 'package:pocket_pilot/src/features/notification_capture/data/transaction_rule_remote_service.dart';
import 'package:pocket_pilot/src/features/notification_capture/domain/transaction_rule.dart';

class TransactionRuleSyncHandler implements SyncHandler {
  final TransactionRuleLocalStore _local;
  final TransactionRuleRemoteService _remote;

  TransactionRuleSyncHandler({
    required TransactionRuleLocalStore local,
    required TransactionRuleRemoteService remote,
  })  : _local = local,
        _remote = remote;

  @override
  String get entityType => 'transaction_rule';

  /// Después de categories (2) — las reglas dependen de categorías. Antes de
  /// transactions (6) para que el lookup en notification capture vea las
  /// reglas más recientes.
  @override
  int get syncOrder => 5;

  @override
  Future<SyncPullResult> pull(DateTime? updatedSince) async {
    final allItems = <SyncItem>[];
    late DateTime syncedAt;
    String? pageToken;

    do {
      final response = await _remote.listRules(
        updatedSince: updatedSince,
        pageToken: pageToken,
      );
      syncedAt = response.syncedAt.toDateTime().toUtc();
      for (final proto in response.rules) {
        final model = TransactionRuleModel.fromProto(proto);
        allItems.add(SyncItem(
          id: model.id,
          updatedAt: model.updatedAt,
          data: model.toMap(),
        ));
      }
      pageToken = response.hasPage() && response.page.nextPageToken.isNotEmpty
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
    final response = await _remote.upsertRule(map);
    if (response.conflictResolved) {
      final serverModel = TransactionRuleModel.fromProto(response.rule);
      return SyncPushResult(
        conflictResolved: true,
        serverData: serverModel.toMap(),
      );
    }
    return const SyncPushResult(conflictResolved: false);
  }

  @override
  Future<void> pushDelete(String entityId, DateTime deletedAt) async {
    await _remote.deleteRule(id: entityId, deletedAt: deletedAt);
  }
}
