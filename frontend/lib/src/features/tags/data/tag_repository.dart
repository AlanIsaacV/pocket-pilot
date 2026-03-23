import 'dart:convert';

import 'package:pocket_pilot/src/core/sync/sync_outbox.dart';
import 'package:pocket_pilot/src/features/tags/data/tag_local_store.dart';
import 'package:pocket_pilot/src/features/tags/domain/tag.dart';

class TagRepository {
  final TagLocalStore _local;
  final SyncOutbox _outbox;

  TagRepository({
    required TagLocalStore local,
    required SyncOutbox outbox,
  })  : _local = local,
        _outbox = outbox;

  Future<List<TagModel>> getTags() => _local.getTags();

  Future<void> createTag({
    required String id,
    required String name,
  }) async {
    final now = DateTime.now().toUtc();
    final model = TagModel(
      id: id,
      name: name,
      createdAt: now,
      updatedAt: now,
    );

    await _local.upsert(model);
    await _outbox.enqueue(
      entityType: 'tag',
      entityId: id,
      operation: 'upsert',
      payload: jsonEncode(model.toServerMap()),
    );
  }

  Future<void> deleteTag(String id) async {
    final now = DateTime.now().toUtc();
    await _local.softDelete(id, now);
    await _outbox.enqueue(
      entityType: 'tag',
      entityId: id,
      operation: 'delete',
      payload: jsonEncode({'deleted_at': now.toIso8601String()}),
    );
  }
}
