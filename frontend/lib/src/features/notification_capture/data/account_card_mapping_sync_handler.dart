import 'dart:convert';

import 'package:pocket_pilot/src/core/sync/sync_handler.dart';
import 'package:pocket_pilot/src/features/notification_capture/data/account_card_mapping_local_store.dart';
import 'package:pocket_pilot/src/features/notification_capture/data/account_card_mapping_remote_service.dart';
import 'package:pocket_pilot/src/features/notification_capture/domain/account_card_mapping.dart';

class AccountCardMappingSyncHandler implements SyncHandler {
  final AccountCardMappingLocalStore _local;
  final AccountCardMappingRemoteService _remote;

  AccountCardMappingSyncHandler({
    required AccountCardMappingLocalStore local,
    required AccountCardMappingRemoteService remote,
  })  : _local = local,
        _remote = remote;

  @override
  String get entityType => 'account_card_mapping';

  /// Después de accounts (1) y antes de transactions (6): los mappings
  /// referencian account_id y deben aterrizar localmente antes de que el
  /// engine de notificaciones intente resolverlos.
  @override
  int get syncOrder => 5;

  @override
  Future<SyncPullResult> pull(DateTime? updatedSince) async {
    final allItems = <SyncItem>[];
    late DateTime syncedAt;
    String? pageToken;

    do {
      final response = await _remote.listMappings(
        updatedSince: updatedSince,
        pageToken: pageToken,
      );
      syncedAt = response.syncedAt.toDateTime().toUtc();
      for (final proto in response.mappings) {
        final model = AccountCardMappingModel.fromProto(proto);
        allItems.add(SyncItem(
          id: model.id,
          updatedAt: model.updatedAt,
          data: model.toMap(),
        ));
      }
      pageToken = response.hasPage() && response.page.nextPageToken.isNotEmpty
          ? response.page.nextPageToken
          : null;
    } while (pageToken != null);

    return SyncPullResult(items: allItems, syncedAt: syncedAt);
  }

  @override
  Future<void> saveLocally(Map<String, dynamic> data) async {
    await _local.upsertRow(data);
  }

  @override
  Future<SyncPushResult> pushUpsert(String payloadJson) async {
    final map = jsonDecode(payloadJson) as Map<String, dynamic>;
    final response = await _remote.upsertMapping(map);
    if (response.conflictResolved) {
      final serverModel =
          AccountCardMappingModel.fromProto(response.mapping);
      return SyncPushResult(
        conflictResolved: true,
        serverData: serverModel.toMap(),
      );
    }
    return const SyncPushResult(conflictResolved: false);
  }

  @override
  Future<void> pushDelete(String entityId, DateTime deletedAt) async {
    await _remote.deleteMapping(id: entityId, deletedAt: deletedAt);
  }
}
