import 'dart:convert';

import 'package:grpc/grpc.dart';
import 'package:pocket_pilot/src/core/sync/sync_handler.dart';
import 'package:pocket_pilot/src/features/transaction_templates/data/transaction_template_local_store.dart';
import 'package:pocket_pilot/src/features/transaction_templates/data/transaction_template_remote_service.dart';
import 'package:pocket_pilot/src/features/transaction_templates/domain/transaction_template.dart';

class TransactionTemplateSyncHandler implements SyncHandler {
  final TransactionTemplateLocalStore _local;
  final TransactionTemplateRemoteService _remote;

  TransactionTemplateSyncHandler({
    required TransactionTemplateLocalStore local,
    required TransactionTemplateRemoteService remote,
  }) : _local = local,
       _remote = remote;

  @override
  String get entityType => 'transaction_template';

  @override
  int get syncOrder => 4;

  @override
  Future<SyncPullResult> pull(DateTime? updatedSince) async {
    try {
      final allItems = <SyncItem>[];
      late DateTime syncedAt;
      String? pageToken;

      do {
        final response = await _remote.listTemplates(
          updatedSince: updatedSince,
          pageToken: pageToken,
        );

        syncedAt = response.syncedAt.toDateTime().toUtc();

        for (final proto in response.templates) {
          final model = TransactionTemplateModel.fromProto(proto);
          final row = <String, dynamic>{
            ...model.toMap(),
            'deleted_at': proto.hasDeletedAt()
                ? proto.deletedAt.toDateTime().toUtc().toIso8601String()
                : null,
          };
          allItems.add(SyncItem(
            id: proto.id,
            updatedAt: proto.updatedAt.toDateTime().toUtc(),
            data: row,
          ));
        }

        pageToken = response.hasPage() &&
                response.page.nextPageToken.isNotEmpty
            ? response.page.nextPageToken
            : null;
      } while (pageToken != null);

      return SyncPullResult(items: allItems, syncedAt: syncedAt);
    } on GrpcError catch (e) {
      if (_isUnsupportedBackend(e)) {
        throw Exception(
          'transaction_template unsupported by backend: ${e.codeName}',
        );
      }
      rethrow;
    }
  }

  @override
  Future<void> saveLocally(Map<String, dynamic> data) async {
    await _local.upsertRow(data);
  }

  @override
  Future<SyncPushResult> pushUpsert(String payloadJson) async {
    final map = jsonDecode(payloadJson) as Map<String, dynamic>;

    try {
      final response = await _remote.upsertTemplate(map);
      if (response.conflictResolved) {
        final model = TransactionTemplateModel.fromProto(response.template);
        final serverRow = <String, dynamic>{
          ...model.toMap(),
          'deleted_at': response.template.hasDeletedAt()
              ? response.template.deletedAt
                    .toDateTime()
                    .toUtc()
                    .toIso8601String()
              : null,
        };
        return SyncPushResult(conflictResolved: true, serverData: serverRow);
      }

      return const SyncPushResult(conflictResolved: false);
    } on GrpcError catch (e) {
      if (_isUnsupportedBackend(e)) {
        throw Exception(
          'transaction_template unsupported by backend: ${e.codeName}',
        );
      }
      rethrow;
    }
  }

  @override
  Future<void> pushDelete(String entityId, DateTime deletedAt) async {
    try {
      await _remote.deleteTemplate(id: entityId, deletedAt: deletedAt);
    } on GrpcError catch (e) {
      if (_isUnsupportedBackend(e)) {
        throw Exception(
          'transaction_template unsupported by backend: ${e.codeName}',
        );
      }
      rethrow;
    }
  }

  bool _isUnsupportedBackend(GrpcError error) {
    return error.code == StatusCode.unimplemented ||
        error.code == StatusCode.notFound ||
        error.code == StatusCode.failedPrecondition;
  }
}
