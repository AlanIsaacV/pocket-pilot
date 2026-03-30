import 'dart:convert';

import 'package:pocket_pilot/src/core/sync/sync_handler.dart';
import 'package:pocket_pilot/src/features/yield_configs/data/yield_config_local_store.dart';
import 'package:pocket_pilot/src/features/yield_configs/data/yield_config_remote_service.dart';
import 'package:pocket_pilot/src/features/yield_configs/domain/yield_config.dart';

class YieldConfigSyncHandler implements SyncHandler {
  final YieldConfigLocalStore _local;
  final YieldConfigRemoteService _remote;

  YieldConfigSyncHandler({
    required YieldConfigLocalStore local,
    required YieldConfigRemoteService remote,
  }) : _local = local,
       _remote = remote;

  @override
  String get entityType => 'yield_config';

  @override
  int get syncOrder => 5;

  @override
  Future<SyncPullResult> pull(DateTime? updatedSince) async {
    final response = await _remote.listConfigs(updatedSince: updatedSince);

    final items = response.configs.map((proto) {
      final model = YieldConfigModel.fromProto(proto).normalized();
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
    final normalized = YieldConfigModel.fromMap(data).normalized().toMap();
    await _local.upsertRow(normalized);
  }

  @override
  Future<SyncPushResult> pushUpsert(String payloadJson) async {
    final map = jsonDecode(payloadJson) as Map<String, dynamic>;
    final response = await _remote.upsertConfig(map);

    if (response.conflictResolved) {
      final serverModel = YieldConfigModel.fromProto(
        response.config,
      ).normalized();
      return SyncPushResult(
        conflictResolved: true,
        serverData: serverModel.toMap(),
      );
    }

    return const SyncPushResult(conflictResolved: false);
  }

  @override
  Future<void> pushDelete(String entityId, DateTime deletedAt) async {
    await _remote.deleteConfig(id: entityId, deletedAt: deletedAt);
  }
}
