import 'dart:convert';

import 'package:pocket_pilot/src/core/sync/sync_outbox.dart';
import 'package:pocket_pilot/src/features/investments/data/investment_holding_local_store.dart';
import 'package:pocket_pilot/src/features/investments/data/investment_lot_local_store.dart';
import 'package:pocket_pilot/src/features/investments/domain/investment_holding.dart';

class InvestmentHoldingRepository {
  final InvestmentHoldingLocalStore _local;
  final InvestmentLotLocalStore? _lotLocal;
  final SyncOutbox _outbox;

  InvestmentHoldingRepository({
    required InvestmentHoldingLocalStore local,
    required SyncOutbox outbox,
    InvestmentLotLocalStore? lotLocal,
  }) : _local = local,
       _lotLocal = lotLocal,
       _outbox = outbox;

  Future<List<InvestmentHoldingModel>> getAll() async {
    final rows = await _local.queryRows();
    return rows.map(InvestmentHoldingModel.fromMap).toList();
  }

  Future<InvestmentHoldingModel?> getById(String id) async {
    final row = await _local.getById(id);
    if (row == null) return null;
    return InvestmentHoldingModel.fromMap(row);
  }

  Future<void> upsert(InvestmentHoldingModel model) async {
    final normalized = model.normalized();
    await _local.upsertRow(normalized.toMap());
    await _outbox.enqueue(
      entityType: 'investment_holding',
      entityId: normalized.id,
      operation: 'upsert',
      payload: jsonEncode(normalized.toServerMap()),
    );
  }

  /// Archiva el holding y en cascada soft-deleta todos sus lots activos.
  /// El generator en el próximo tick soft-deleta las transacciones derivadas.
  Future<void> archive(String id) async {
    final now = DateTime.now().toUtc();

    final lotStore = _lotLocal;
    if (lotStore != null) {
      final lotRows = await lotStore.queryByHolding(id);
      for (final row in lotRows) {
        final lotId = row['id'] as String;
        await lotStore.softDelete(lotId, now);
        await _outbox.enqueue(
          entityType: 'investment_lot',
          entityId: lotId,
          operation: 'delete',
          payload: jsonEncode({'deleted_at': now.toIso8601String()}),
        );
      }
    }

    await _local.softDelete(id, now);
    await _outbox.enqueue(
      entityType: 'investment_holding',
      entityId: id,
      operation: 'delete',
      payload: jsonEncode({'deleted_at': now.toIso8601String()}),
    );
  }
}
