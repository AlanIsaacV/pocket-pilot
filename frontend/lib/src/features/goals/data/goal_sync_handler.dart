import 'dart:convert';

import 'package:pocket_pilot/src/core/sync/sync_handler.dart';
import 'package:pocket_pilot/src/features/goals/data/goal_local_store.dart';
import 'package:pocket_pilot/src/features/goals/data/goal_remote_service.dart';
import 'package:pocket_pilot/src/features/goals/domain/goal.dart';

class GoalSyncHandler implements SyncHandler {
  final GoalLocalStore _local;
  final GoalRemoteService _remote;

  GoalSyncHandler({
    required GoalLocalStore local,
    required GoalRemoteService remote,
  }) : _local = local,
       _remote = remote;

  @override
  String get entityType => 'goal';

  @override
  int get syncOrder => 7;

  @override
  Future<SyncPullResult> pull(DateTime? updatedSince) async {
    final response = await _remote.listGoals(updatedSince: updatedSince);

    final items = response.goals.map((proto) {
      final model = GoalModel.fromProto(proto).normalized();
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
    final normalized = GoalModel.fromMap(data).normalized().toMap();
    await _local.upsertRow(normalized);
  }

  @override
  Future<SyncPushResult> pushUpsert(String payloadJson) async {
    final map = jsonDecode(payloadJson) as Map<String, dynamic>;
    final response = await _remote.upsertGoal(map);

    if (response.conflictResolved) {
      final serverData = GoalModel.fromProto(
        response.goal,
      ).normalized().toMap();
      return SyncPushResult(conflictResolved: true, serverData: serverData);
    }

    return const SyncPushResult(conflictResolved: false);
  }

  @override
  Future<void> pushDelete(String entityId, DateTime deletedAt) async {
    await _remote.deleteGoal(id: entityId, deletedAt: deletedAt);
  }
}
