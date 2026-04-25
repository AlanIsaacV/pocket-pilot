import 'dart:convert';

import 'package:pocket_pilot/src/core/sync/sync_handler.dart';
import 'package:pocket_pilot/src/features/investments/data/investment_split_local_store.dart';
import 'package:pocket_pilot/src/features/investments/data/investment_split_remote_service.dart';
import 'package:pocket_pilot/src/features/investments/domain/investment_split.dart';

class InvestmentSplitSyncHandler implements SyncHandler {
  final InvestmentSplitLocalStore _local;
  final InvestmentSplitRemoteService _remote;

  InvestmentSplitSyncHandler({
    required InvestmentSplitLocalStore local,
    required InvestmentSplitRemoteService remote,
  }) : _local = local,
       _remote = remote;

  @override
  String get entityType => 'investment_split';

  /// After investment_lot (7), before market_price (9). Splits depend on
  /// holdings and lots existing locally, but market_price pulls are independent.
  @override
  int get syncOrder => 8;

  @override
  Future<SyncPullResult> pull(DateTime? updatedSince) async {
    final allItems = <SyncItem>[];
    late DateTime syncedAt;
    String? pageToken;

    do {
      final response = await _remote.listSplits(
        updatedSince: updatedSince,
        pageToken: pageToken,
      );
      syncedAt = response.syncedAt.toDateTime().toUtc();
      for (final proto in response.splits) {
        final model = InvestmentSplitModel.fromProto(proto).normalized();
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
    final normalized = InvestmentSplitModel.fromMap(data).normalized().toMap();
    await _local.upsertRow(normalized);
  }

  @override
  Future<SyncPushResult> pushUpsert(String payloadJson) async {
    final map = jsonDecode(payloadJson) as Map<String, dynamic>;
    final response = await _remote.upsertSplit(map);
    if (response.conflictResolved) {
      final serverModel =
          InvestmentSplitModel.fromProto(response.split).normalized();
      return SyncPushResult(
        conflictResolved: true,
        serverData: serverModel.toMap(),
      );
    }
    return const SyncPushResult(conflictResolved: false);
  }

  @override
  Future<void> pushDelete(String entityId, DateTime deletedAt) async {
    await _remote.deleteSplit(id: entityId, deletedAt: deletedAt);
  }
}
