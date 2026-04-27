import 'dart:convert';

import 'package:pocket_pilot/src/core/sync/sync_handler.dart';
import 'package:pocket_pilot/src/features/notification_capture/data/bank_alias_local_store.dart';
import 'package:pocket_pilot/src/features/notification_capture/data/bank_alias_remote_service.dart';
import 'package:pocket_pilot/src/features/notification_capture/domain/bank_alias.dart';

/// Push+pull sync handler para `bank_aliases`. Mismo patrón que
/// [AccountCardMappingSyncHandler] — alias per-user que sincroniza para
/// que un device del mismo usuario reciba las decisiones de otro como hint.
class BankAliasSyncHandler implements SyncHandler {
  final BankAliasLocalStore _local;
  final BankAliasRemoteService _remote;

  BankAliasSyncHandler({
    required BankAliasLocalStore local,
    required BankAliasRemoteService remote,
  })  : _local = local,
        _remote = remote;

  @override
  String get entityType => 'bank_alias';

  /// Mismo orden que account_card_mapping/transaction_rule (5): user-scoped
  /// y debe aterrizar antes que transactions (6) — aunque hoy no hay FK,
  /// el alias resolution puede consultarse durante el procesamiento.
  @override
  int get syncOrder => 5;

  @override
  Future<SyncPullResult> pull(DateTime? updatedSince) async {
    final allItems = <SyncItem>[];
    late DateTime syncedAt;
    String? pageToken;

    do {
      final response = await _remote.listAliases(
        updatedSince: updatedSince,
        pageToken: pageToken,
      );
      syncedAt = response.syncedAt.toDateTime().toUtc();
      for (final proto in response.aliases) {
        final model = BankAliasModel.fromProto(proto);
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
    final response = await _remote.upsertAlias(map);
    if (response.conflictResolved) {
      final serverModel = BankAliasModel.fromProto(response.alias);
      return SyncPushResult(
        conflictResolved: true,
        serverData: serverModel.toMap(),
      );
    }
    return const SyncPushResult(conflictResolved: false);
  }

  @override
  Future<void> pushDelete(String entityId, DateTime deletedAt) async {
    await _remote.deleteAlias(id: entityId, deletedAt: deletedAt);
  }
}
