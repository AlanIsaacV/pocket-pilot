import 'dart:convert';

import 'package:pocket_pilot/src/core/sync/sync_outbox.dart';
import 'package:pocket_pilot/src/features/investments/data/investment_split_local_store.dart';
import 'package:pocket_pilot/src/features/investments/domain/investment_split.dart';

class InvestmentSplitRepository {
  final InvestmentSplitLocalStore _local;
  final SyncOutbox _outbox;

  InvestmentSplitRepository({
    required InvestmentSplitLocalStore local,
    required SyncOutbox outbox,
  }) : _local = local,
       _outbox = outbox;

  Future<List<InvestmentSplitModel>> getAll() async {
    final rows = await _local.queryAll();
    return rows.map(InvestmentSplitModel.fromMap).toList();
  }

  Future<List<InvestmentSplitModel>> getByHolding(String holdingId) async {
    final rows = await _local.queryByHolding(holdingId);
    return rows.map(InvestmentSplitModel.fromMap).toList();
  }

  Future<InvestmentSplitModel?> getById(String id) async {
    final row = await _local.getById(id);
    if (row == null) return null;
    return InvestmentSplitModel.fromMap(row);
  }

  Future<void> upsert(InvestmentSplitModel model) async {
    final normalized = model.normalized();
    await _local.upsertRow(normalized.toMap());
    await _outbox.enqueue(
      entityType: 'investment_split',
      entityId: normalized.id,
      operation: 'upsert',
      payload: jsonEncode(normalized.toServerMap()),
    );
  }

  Future<void> delete(String id) async {
    final now = DateTime.now().toUtc();
    await _local.softDelete(id, now);
    await _outbox.enqueue(
      entityType: 'investment_split',
      entityId: id,
      operation: 'delete',
      payload: jsonEncode({'deleted_at': now.toIso8601String()}),
    );
  }
}
