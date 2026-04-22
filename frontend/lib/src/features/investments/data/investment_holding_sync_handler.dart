import 'dart:convert';

import 'package:pocket_pilot/src/core/sync/sync_handler.dart';
import 'package:pocket_pilot/src/features/investments/data/investment_holding_local_store.dart';
import 'package:pocket_pilot/src/features/investments/data/investment_holding_remote_service.dart';
import 'package:pocket_pilot/src/features/investments/domain/investment_holding.dart';

class InvestmentHoldingSyncHandler implements SyncHandler {
  final InvestmentHoldingLocalStore _local;
  final InvestmentHoldingRemoteService _remote;

  InvestmentHoldingSyncHandler({
    required InvestmentHoldingLocalStore local,
    required InvestmentHoldingRemoteService remote,
  }) : _local = local,
       _remote = remote;

  @override
  String get entityType => 'investment_holding';

  /// Must run before investment_lot and transaction (lots and generated txs
  /// reference holdings), and after account (holding references an account).
  @override
  int get syncOrder => 6;

  @override
  Future<SyncPullResult> pull(DateTime? updatedSince) async {
    final allItems = <SyncItem>[];
    late DateTime syncedAt;
    String? pageToken;

    do {
      final response = await _remote.listHoldings(
        updatedSince: updatedSince,
        pageToken: pageToken,
      );
      syncedAt = response.syncedAt.toDateTime().toUtc();
      for (final proto in response.holdings) {
        final model = InvestmentHoldingModel.fromProto(proto).normalized();
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
    final normalized =
        InvestmentHoldingModel.fromMap(data).normalized().toMap();
    await _local.upsertRow(normalized);
  }

  @override
  Future<SyncPushResult> pushUpsert(String payloadJson) async {
    final map = jsonDecode(payloadJson) as Map<String, dynamic>;
    final response = await _remote.upsertHolding(map);
    if (response.conflictResolved) {
      final serverModel =
          InvestmentHoldingModel.fromProto(response.holding).normalized();
      return SyncPushResult(
        conflictResolved: true,
        serverData: serverModel.toMap(),
      );
    }
    return const SyncPushResult(conflictResolved: false);
  }

  @override
  Future<void> pushDelete(String entityId, DateTime deletedAt) async {
    await _remote.deleteHolding(id: entityId, deletedAt: deletedAt);
  }
}
