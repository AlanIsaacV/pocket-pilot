import 'dart:convert';

import 'package:pocket_pilot/src/core/sync/sync_outbox.dart';
import 'package:pocket_pilot/src/features/user_preferences/data/user_preference_local_store.dart';
import 'package:pocket_pilot/src/features/user_preferences/domain/user_preference.dart';

class UserPreferenceRepository {
  final UserPreferenceLocalStore _local;
  final SyncOutbox _outbox;

  UserPreferenceRepository({
    required UserPreferenceLocalStore local,
    required SyncOutbox outbox,
  }) : _local = local,
       _outbox = outbox;

  Future<List<UserPreferenceModel>> listPreferences() =>
      _local.listPreferences();

  Future<UserPreferenceModel?> getByKey(String prefKey) =>
      _local.getByKey(prefKey);

  Future<void> upsertPreference({
    required String prefKey,
    required String prefValue,
    DateTime? forcedUpdatedAt,
  }) async {
    final now = DateTime.now().toUtc();
    final current = await _local.getByKey(prefKey);
    final seededAt = forcedUpdatedAt?.toUtc();
    final model = UserPreferenceModel(
      prefKey: prefKey,
      prefValue: prefValue,
      createdAt: current?.createdAt ?? seededAt ?? now,
      updatedAt: seededAt ?? now,
      deletedAt: null,
    );

    await _local.upsert(model);
    await _outbox.enqueue(
      entityType: 'user_preference',
      entityId: prefKey,
      operation: 'upsert',
      payload: jsonEncode(model.toServerMap()),
    );
  }

  Future<void> deletePreference(String prefKey) async {
    final now = DateTime.now().toUtc();
    await _local.softDelete(prefKey, now);
    await _outbox.enqueue(
      entityType: 'user_preference',
      entityId: prefKey,
      operation: 'delete',
      payload: jsonEncode({'deleted_at': now.toIso8601String()}),
    );
  }
}
