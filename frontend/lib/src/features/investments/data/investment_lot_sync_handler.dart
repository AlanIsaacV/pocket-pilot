import 'dart:convert';

import 'package:pocket_pilot/src/core/sync/sync_handler.dart';
import 'package:pocket_pilot/src/features/investments/data/investment_lot_local_store.dart';
import 'package:pocket_pilot/src/features/investments/data/investment_lot_remote_service.dart';
import 'package:pocket_pilot/src/features/investments/domain/investment_lot.dart';

class InvestmentLotSyncHandler implements SyncHandler {
  final InvestmentLotLocalStore _local;
  final InvestmentLotRemoteService _remote;

  InvestmentLotSyncHandler({
    required InvestmentLotLocalStore local,
    required InvestmentLotRemoteService remote,
  }) : _local = local,
       _remote = remote;

  @override
  String get entityType => 'investment_lot';

  /// After investment_holding (FK), before transaction (the generator derives
  /// transactions from lots after pull; those transactions are pushed in the
  /// transaction step that runs later in the same cycle).
  @override
  int get syncOrder => 7;

  @override
  Future<SyncPullResult> pull(DateTime? updatedSince) async {
    final allItems = <SyncItem>[];
    late DateTime syncedAt;
    String? pageToken;

    do {
      final response = await _remote.listLots(
        updatedSince: updatedSince,
        pageToken: pageToken,
      );
      syncedAt = response.syncedAt.toDateTime().toUtc();
      for (final proto in response.lots) {
        final model = InvestmentLotModel.fromProto(proto).normalized();
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
    final normalized = InvestmentLotModel.fromMap(data).normalized().toMap();
    await _local.upsertRow(normalized);
  }

  @override
  Future<SyncPushResult> pushUpsert(String payloadJson) async {
    final map = jsonDecode(payloadJson) as Map<String, dynamic>;
    final response = await _remote.upsertLot(map);
    if (response.conflictResolved) {
      final serverModel =
          InvestmentLotModel.fromProto(response.lot).normalized();
      return SyncPushResult(
        conflictResolved: true,
        serverData: serverModel.toMap(),
      );
    }
    return const SyncPushResult(conflictResolved: false);
  }

  @override
  Future<void> pushDelete(String entityId, DateTime deletedAt) async {
    await _remote.deleteLot(id: entityId, deletedAt: deletedAt);
  }
}
