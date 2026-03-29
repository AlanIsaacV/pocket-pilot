import 'dart:convert';

import 'package:pocket_pilot/src/features/categories/data/category_local_store.dart';
import 'package:pocket_pilot/src/features/categories/data/category_remote_service.dart';
import 'package:pocket_pilot/src/features/categories/domain/category.dart';
import 'package:pocket_pilot/src/core/sync/sync_handler.dart';

class CategorySyncHandler implements SyncHandler {
  final CategoryLocalStore _local;
  final CategoryRemoteService _remote;

  CategorySyncHandler({
    required CategoryLocalStore local,
    required CategoryRemoteService remote,
  })  : _local = local,
        _remote = remote;

  @override
  String get entityType => 'category';

  @override
  int get syncOrder => 2;

  @override
  Future<SyncPullResult> pull(DateTime? updatedSince) async {
    final response = await _remote.listCategories(updatedSince: updatedSince);

    final items = response.categories.map((proto) {
      final model = CategoryModel.fromProto(proto);
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
    await _local.upsert(CategoryModel.fromMap(data));
  }

  @override
  Future<SyncPushResult> pushUpsert(String payloadJson) async {
    final map = jsonDecode(payloadJson) as Map<String, dynamic>;
    final response = await _remote.upsertCategory(map);

    if (response.conflictResolved) {
      final serverModel = CategoryModel.fromProto(response.category);
      return SyncPushResult(
        conflictResolved: true,
        serverData: serverModel.toMap(),
      );
    }
    return const SyncPushResult(conflictResolved: false);
  }

  @override
  Future<void> pushDelete(String entityId, DateTime deletedAt) async {
    await _remote.deleteCategory(id: entityId, deletedAt: deletedAt);
  }
}
