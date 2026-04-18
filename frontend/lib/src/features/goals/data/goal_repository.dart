import 'dart:convert';

import 'package:pocket_pilot/src/core/sync/sync_outbox.dart';
import 'package:pocket_pilot/src/features/goals/data/goal_local_store.dart';
import 'package:pocket_pilot/src/features/goals/domain/goal.dart';

class GoalRepository {
  final GoalLocalStore _local;
  final SyncOutbox _outbox;

  GoalRepository({required GoalLocalStore local, required SyncOutbox outbox})
    : _local = local,
      _outbox = outbox;

  Future<List<GoalModel>> getGoals() async {
    final rows = await _local.queryRows();
    return rows.map((row) => GoalModel.fromMap(row)).toList();
  }

  Future<Map<String, int>> getLiquidByCurrency() =>
      _local.getLiquidByCurrency();

  Future<void> upsertGoal(GoalModel goal) async {
    final normalized = goal.normalized();
    await _local.upsertRow(normalized.toMap());
    await _outbox.enqueue(
      entityType: 'goal',
      entityId: normalized.id,
      operation: 'upsert',
      payload: jsonEncode(normalized.toServerMap()),
    );
  }

  Future<void> deleteGoal(String id) async {
    final now = DateTime.now().toUtc();
    await _local.softDelete(id, now);
    await _outbox.enqueue(
      entityType: 'goal',
      entityId: id,
      operation: 'delete',
      payload: jsonEncode({'deleted_at': now.toIso8601String()}),
    );
  }
}
