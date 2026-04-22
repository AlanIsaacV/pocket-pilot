import 'package:pocket_pilot/src/core/sync/sync_handler.dart';
import 'package:pocket_pilot/src/features/investments/data/market_price_local_store.dart';
import 'package:pocket_pilot/src/features/investments/data/market_price_remote_service.dart';
import 'package:pocket_pilot/src/features/investments/domain/market_price.dart';

/// Read-only sync handler for market_prices. The app never pushes prices
/// back to the server — the backend cron is the sole writer. pushUpsert and
/// pushDelete are no-ops because the MarketPriceRepository never enqueues
/// outbox entries for this entity type.
class MarketPriceSyncHandler implements SyncHandler {
  final MarketPriceLocalStore _local;
  final MarketPriceRemoteService _remote;

  MarketPriceSyncHandler({
    required MarketPriceLocalStore local,
    required MarketPriceRemoteService remote,
  }) : _local = local,
       _remote = remote;

  @override
  String get entityType => 'market_price';

  /// After lots so UI that reads prices can resolve them after a fresh pull,
  /// and before transaction to keep the order stable.
  @override
  int get syncOrder => 8;

  @override
  Future<SyncPullResult> pull(DateTime? updatedSince) async {
    final allItems = <SyncItem>[];
    late DateTime syncedAt;
    String? pageToken;

    do {
      final response = await _remote.listPrices(
        updatedSince: updatedSince,
        pageToken: pageToken,
      );
      syncedAt = response.syncedAt.toDateTime().toUtc();
      for (final proto in response.prices) {
        final model = MarketPriceModel.fromProto(proto);
        allItems.add(SyncItem(
          id: model.syntheticId,
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
    await _local.upsertRow(MarketPriceModel.fromMap(data).toMap());
  }

  @override
  Future<SyncPushResult> pushUpsert(String payloadJson) async {
    // Read-only: never called because MarketPrice has no repository/outbox.
    return const SyncPushResult(conflictResolved: false);
  }

  @override
  Future<void> pushDelete(String entityId, DateTime deletedAt) async {
    // Read-only: never called.
  }
}
