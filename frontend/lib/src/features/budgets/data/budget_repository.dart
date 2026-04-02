import 'dart:convert';

import 'package:pocket_pilot/src/core/sync/sync_outbox.dart';
import 'package:pocket_pilot/src/features/budgets/data/budget_local_store.dart';
import 'package:pocket_pilot/src/features/budgets/domain/budget.dart';
import 'package:pocket_pilot/src/features/budgets/domain/budget_status.dart';

class BudgetRepository {
  final BudgetLocalStore _local;
  final SyncOutbox _outbox;

  BudgetRepository({required BudgetLocalStore local, required SyncOutbox outbox})
    : _local = local,
      _outbox = outbox;

  Future<List<BudgetModel>> getBudgets() async {
    final rows = await _local.queryRows();
    return rows.map((row) => BudgetModel.fromMap(row)).toList();
  }

  Future<List<BudgetStatus>> getBudgetStatuses() async {
    final budgets = await getBudgets();
    final statuses = <BudgetStatus>[];

    for (final budget in budgets) {
      final spent = await _local.computeSpentCents(
        budget.categoryId,
        budget.period,
      );
      statuses.add(BudgetStatus(budget: budget, spentAmountCents: spent));
    }

    return statuses;
  }

  Future<void> upsertBudget(BudgetModel budget) async {
    final normalized = budget.normalized();
    await _local.upsertRow(normalized.toMap());
    await _outbox.enqueue(
      entityType: 'budget',
      entityId: normalized.id,
      operation: 'upsert',
      payload: jsonEncode(normalized.toServerMap()),
    );
  }

  Future<void> deleteBudget(String id) async {
    final now = DateTime.now().toUtc();
    await _local.softDelete(id, now);
    await _outbox.enqueue(
      entityType: 'budget',
      entityId: id,
      operation: 'delete',
      payload: jsonEncode({'deleted_at': now.toIso8601String()}),
    );
  }
}
