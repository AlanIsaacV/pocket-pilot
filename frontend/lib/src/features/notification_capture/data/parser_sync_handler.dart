import 'package:pocket_pilot/src/core/sync/sync_handler.dart';
import 'package:pocket_pilot/src/features/notification_capture/data/parser_local_store.dart';
import 'package:pocket_pilot/src/features/notification_capture/data/parser_remote_service.dart';

/// Pull-only sync handler para `notification_parsers`. La tabla es global y
/// el cliente nunca empuja: pushUpsert y pushDelete son no-ops porque el
/// repositorio del parser no tiene outbox. Mismo patrón que
/// [MarketPriceSyncHandler].
class ParserSyncHandler implements SyncHandler {
  final ParserLocalStore _local;
  final ParserRemoteService _remote;

  ParserSyncHandler({
    required ParserLocalStore local,
    required ParserRemoteService remote,
  })  : _local = local,
        _remote = remote;

  @override
  String get entityType => 'notification_parser';

  /// Antes de account_card_mapping/transaction_rule (5) y de transactions (6).
  /// El parser no depende de ninguna otra entidad y es necesario para que el
  /// engine procese la inbox después del primer sync.
  @override
  int get syncOrder => 4;

  @override
  Future<SyncPullResult> pull(DateTime? updatedSince) async {
    final allItems = <SyncItem>[];
    late DateTime syncedAt;
    String? pageToken;

    do {
      final response = await _remote.listParsers(
        updatedSince: updatedSince,
        pageToken: pageToken,
      );
      syncedAt = response.syncedAt.toDateTime().toUtc();
      for (final proto in response.parsers) {
        final updatedAt = proto.updatedAt.toDateTime().toUtc();
        final deletedAt = proto.hasDeletedAt()
            ? proto.deletedAt.toDateTime().toUtc()
            : null;
        allItems.add(SyncItem(
          id: proto.bankId,
          updatedAt: updatedAt,
          data: {
            'bank_id': proto.bankId,
            'version': proto.version,
            'definition': proto.definition,
            'updated_at': updatedAt.toIso8601String(),
            'deleted_at': deletedAt?.toIso8601String(),
          },
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
    final deletedRaw = data['deleted_at'] as String?;
    await _local.upsertFromSync(
      bankId: data['bank_id'] as String,
      version: (data['version'] as num).toInt(),
      definitionJson: data['definition'] as String,
      updatedAt: DateTime.parse(data['updated_at'] as String),
      deletedAt: deletedRaw == null ? null : DateTime.parse(deletedRaw),
    );
  }

  @override
  Future<SyncPushResult> pushUpsert(String payloadJson) async {
    // Pull-only: never called.
    return const SyncPushResult(conflictResolved: false);
  }

  @override
  Future<void> pushDelete(String entityId, DateTime deletedAt) async {
    // Pull-only: never called.
  }
}
