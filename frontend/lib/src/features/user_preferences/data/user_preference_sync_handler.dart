import 'dart:convert';

import 'package:pocket_pilot/src/core/sync/sync_handler.dart';
import 'package:pocket_pilot/src/features/user_preferences/data/user_preference_local_store.dart';
import 'package:pocket_pilot/src/features/user_preferences/data/user_preference_remote_service.dart';
import 'package:pocket_pilot/src/features/user_preferences/domain/user_preference.dart';

class UserPreferenceSyncHandler implements SyncHandler {
  final UserPreferenceLocalStore _local;
  final UserPreferenceRemoteService _remote;

  UserPreferenceSyncHandler({
    required UserPreferenceLocalStore local,
    required UserPreferenceRemoteService remote,
  }) : _local = local,
       _remote = remote;

  @override
  String get entityType => 'user_preference';

  @override
  int get syncOrder => 5;

  @override
  Future<SyncPullResult> pull(DateTime? updatedSince) async {
    final allItems = <SyncItem>[];
    late DateTime syncedAt;
    String? pageToken;

    do {
      final response = await _remote.listPreferences(
        updatedSince: updatedSince,
        pageToken: pageToken,
      );

      syncedAt = response.syncedAt.toDateTime().toUtc();

      for (final proto in response.preferences) {
        final model = UserPreferenceModel.fromProto(proto);
        allItems.add(SyncItem(
          id: model.prefKey,
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
    await _local.upsert(UserPreferenceModel.fromMap(data));
  }

  @override
  Future<SyncPushResult> pushUpsert(String payloadJson) async {
    final map = jsonDecode(payloadJson) as Map<String, dynamic>;
    final response = await _remote.upsertPreference(map);

    if (response.conflictResolved) {
      final serverModel = UserPreferenceModel.fromProto(response.preference);
      return SyncPushResult(
        conflictResolved: true,
        serverData: serverModel.toMap(),
      );
    }
    return const SyncPushResult(conflictResolved: false);
  }

  @override
  Future<void> pushDelete(String entityId, DateTime deletedAt) async {
    await _remote.deletePreference(prefKey: entityId, deletedAt: deletedAt);
  }
}
