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
  int get syncOrder => 3;

  @override
  Future<SyncPullResult> pull(DateTime? updatedSince) async {
    final allItems = <SyncItem>[];
    late DateTime syncedAt;
    String? pageToken;

    do {
      final response = await _remote.listTags(
        updatedSince: updatedSince,
        pageToken: pageToken,
      );

      syncedAt = response.syncedAt.toDateTime().toUtc();

      for (final proto in response.tags) {
        final model = TagModel.fromProto(proto);
        allItems.add(SyncItem(
          id: model.id,
          updatedAt: model.updatedAt,
          data: model.toMap(),
        ));
      }

      pageToken = response.hasPage() &&
              response.page.nextPageToken.isNotEmpty
          ? response.page.nextPageToken
          : null;
    } while (pageToken != null);

    return SyncPullResult(items: allItems, syncedAt: syncedAt);
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
