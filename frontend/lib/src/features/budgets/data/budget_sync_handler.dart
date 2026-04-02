import 'dart:convert';

import 'package:pocket_pilot/src/core/sync/sync_handler.dart';
import 'package:pocket_pilot/src/features/budgets/data/budget_local_store.dart';
import 'package:pocket_pilot/src/features/budgets/data/budget_remote_service.dart';
import 'package:pocket_pilot/src/features/budgets/domain/budget.dart';

class BudgetSyncHandler implements SyncHandler {
  final BudgetLocalStore _local;
  final BudgetRemoteService _remote;

  BudgetSyncHandler({
    required BudgetLocalStore local,
    required BudgetRemoteService remote,
  }) : _local = local,
       _remote = remote;

  @override
  String get entityType => 'budget';

  @override
  int get syncOrder => 8;

  @override
  Future<SyncPullResult> pull(DateTime? updatedSince) async {
    final response = await _remote.listBudgets(updatedSince: updatedSince);

    final items = response.budgets.map((proto) {
      final model = BudgetModel.fromProto(proto).normalized();
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
    final normalized = BudgetModel.fromMap(data).normalized().toMap();
    await _local.upsertRow(normalized);
  }

  @override
  Future<SyncPushResult> pushUpsert(String payloadJson) async {
    final map = jsonDecode(payloadJson) as Map<String, dynamic>;
    final response = await _remote.upsertBudget(map);

    if (response.conflictResolved) {
      final serverData = BudgetModel.fromProto(
        response.budget,
      ).normalized().toMap();
      return SyncPushResult(conflictResolved: true, serverData: serverData);
    }

    return const SyncPushResult(conflictResolved: false);
  }

  @override
  Future<void> pushDelete(String entityId, DateTime deletedAt) async {
    await _remote.deleteBudget(id: entityId, deletedAt: deletedAt);
  }
}
