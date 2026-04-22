import 'dart:convert';

import 'package:pocket_pilot/src/core/sync/sync_outbox.dart';
import 'package:pocket_pilot/src/features/investments/data/investment_lot_local_store.dart';
import 'package:pocket_pilot/src/features/investments/domain/investment_lot.dart';

class InvestmentLotRepository {
  final InvestmentLotLocalStore _local;
  final SyncOutbox _outbox;

  InvestmentLotRepository({
    required InvestmentLotLocalStore local,
    required SyncOutbox outbox,
  }) : _local = local,
       _outbox = outbox;

  Future<List<InvestmentLotModel>> getAll() async {
    final rows = await _local.queryAll();
    return rows.map(InvestmentLotModel.fromMap).toList();
  }

  Future<List<InvestmentLotModel>> getByHolding(String holdingId) async {
    final rows = await _local.queryByHolding(holdingId);
    return rows.map(InvestmentLotModel.fromMap).toList();
  }

  Future<List<InvestmentLotModel>> getByAccount(String accountId) async {
    final rows = await _local.queryByAccount(accountId);
    return rows.map(InvestmentLotModel.fromMap).toList();
  }

  Future<String?> getLastUsedAccountId() => _local.getLastUsedAccountId();

  Future<InvestmentLotModel?> getById(String id) async {
    final row = await _local.getById(id);
    if (row == null) return null;
    return InvestmentLotModel.fromMap(row);
  }

  Future<void> upsert(InvestmentLotModel model) async {
    final normalized = model.normalized();
    await _local.upsertRow(normalized.toMap());
    await _outbox.enqueue(
      entityType: 'investment_lot',
      entityId: normalized.id,
      operation: 'upsert',
      payload: jsonEncode(normalized.toServerMap()),
    );
  }

  Future<void> delete(String id) async {
    final now = DateTime.now().toUtc();
    await _local.softDelete(id, now);
    await _outbox.enqueue(
      entityType: 'investment_lot',
      entityId: id,
      operation: 'delete',
      payload: jsonEncode({'deleted_at': now.toIso8601String()}),
    );
  }
}
