import 'package:pocket_pilot/src/core/sync/sync_handler.dart';
import 'package:pocket_pilot/src/features/notification_capture/data/bank_package_local_store.dart';
import 'package:pocket_pilot/src/features/notification_capture/data/bank_package_remote_service.dart';

/// Pull-only sync handler para `bank_packages`. La tabla es global y el
/// cliente nunca empuja entradas al catálogo: pushUpsert/pushDelete son
/// no-ops. Mismo patrón que [ParserSyncHandler].
class BankPackageSyncHandler implements SyncHandler {
  final BankPackageLocalStore _local;
  final BankPackageRemoteService _remote;

  BankPackageSyncHandler({
    required BankPackageLocalStore local,
    required BankPackageRemoteService remote,
  })  : _local = local,
        _remote = remote;

  @override
  String get entityType => 'bank_package';

  /// Mismo orden que notification_parser (4): ambos son globals pull-only
  /// y deberían aterrizar antes que las entidades user-scoped que los
  /// referencian (account_card_mapping/transaction_rule en 5).
  @override
  int get syncOrder => 4;

  @override
  Future<SyncPullResult> pull(DateTime? updatedSince) async {
    final allItems = <SyncItem>[];
    late DateTime syncedAt;
    String? pageToken;

    do {
      final response = await _remote.listBankPackages(
        updatedSince: updatedSince,
        pageToken: pageToken,
      );
      syncedAt = response.syncedAt.toDateTime().toUtc();
      for (final proto in response.packages) {
        final updatedAt = proto.updatedAt.toDateTime().toUtc();
        final deletedAt = proto.hasDeletedAt()
            ? proto.deletedAt.toDateTime().toUtc()
            : null;
        allItems.add(SyncItem(
          id: proto.packageName,
          updatedAt: updatedAt,
          data: {
            'package_name': proto.packageName,
            'bank_id': proto.bankId,
            'default_label': proto.defaultLabel,
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
      packageName: data['package_name'] as String,
      bankId: data['bank_id'] as String,
      defaultLabel: data['default_label'] as String,
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
