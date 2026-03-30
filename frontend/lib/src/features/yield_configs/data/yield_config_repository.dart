import 'dart:convert';

import 'package:pocket_pilot/src/core/sync/sync_outbox.dart';
import 'package:pocket_pilot/src/features/yield_configs/data/yield_config_local_store.dart';
import 'package:pocket_pilot/src/features/yield_configs/domain/yield_config.dart';

class YieldConfigRepository {
  final YieldConfigLocalStore _local;
  final SyncOutbox _outbox;

  YieldConfigRepository({
    required YieldConfigLocalStore local,
    required SyncOutbox outbox,
  }) : _local = local,
       _outbox = outbox;

  Future<List<YieldConfigModel>> getConfigs() async {
    final rows = await _local.queryRows();
    return rows.map((row) => YieldConfigModel.fromMap(row)).toList();
  }

  Future<List<YieldConfigModel>> getSchedulableConfigs({
    required String horizonDate,
  }) async {
    final rows = await _local.querySchedulableRows(horizonDate: horizonDate);
    return rows.map((row) => YieldConfigModel.fromMap(row)).toList();
  }

  Future<void> upsertConfig(YieldConfigModel model) async {
    final normalized = model.normalized();
    await _local.upsertRow(normalized.toMap());
    await _outbox.enqueue(
      entityType: 'yield_config',
      entityId: normalized.id,
      operation: 'upsert',
      payload: jsonEncode(normalized.toServerMap()),
    );
  }

  Future<void> deleteConfig(String id) async {
    final now = DateTime.now().toUtc();
    await _local.softDelete(id, now);
    await _outbox.enqueue(
      entityType: 'yield_config',
      entityId: id,
      operation: 'delete',
      payload: jsonEncode({'deleted_at': now.toIso8601String()}),
    );
  }
}
