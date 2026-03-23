import 'dart:convert';

import 'package:pocket_pilot/src/features/tags/data/tag_local_store.dart';
import 'package:pocket_pilot/src/features/tags/data/tag_remote_service.dart';
import 'package:pocket_pilot/src/features/tags/domain/tag.dart';
import 'package:pocket_pilot/src/core/sync/sync_handler.dart';

class TagSyncHandler implements SyncHandler {
  final TagLocalStore _local;
  final TagRemoteService _remote;

  TagSyncHandler({
    required TagLocalStore local,
    required TagRemoteService remote,
  })  : _local = local,
        _remote = remote;

  @override
  String get entityType => 'tag';

  @override
  Future<SyncPullResult> pull(DateTime? updatedSince) async {
    final response = await _remote.listTags(updatedSince: updatedSince);

    final items = response.tags.map((proto) {
      final model = TagModel.fromProto(proto);
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
    await _local.upsert(TagModel.fromMap(data));
  }

  @override
  Future<SyncPushResult> pushUpsert(String payloadJson) async {
    final map = jsonDecode(payloadJson) as Map<String, dynamic>;
    final response = await _remote.upsertTag(map);

    if (response.conflictResolved) {
      final serverModel = TagModel.fromProto(response.tag);
      return SyncPushResult(
        conflictResolved: true,
        serverData: serverModel.toMap(),
      );
    }
    return const SyncPushResult(conflictResolved: false);
  }

  @override
  Future<void> pushDelete(String entityId, DateTime deletedAt) async {
    await _remote.deleteTag(id: entityId, deletedAt: deletedAt);
  }
}
