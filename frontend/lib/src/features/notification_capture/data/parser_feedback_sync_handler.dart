import 'dart:convert';

import 'package:pocket_pilot/src/core/sync/sync_handler.dart';
import 'package:pocket_pilot/src/features/notification_capture/data/parser_feedback_local_store.dart';
import 'package:pocket_pilot/src/features/notification_capture/data/parser_feedback_remote_service.dart';
import 'package:pocket_pilot/src/features/notification_capture/domain/parser_feedback.dart';

/// Push-only sync handler para `parser_feedback`. El cliente nunca hace pull
/// de feedback hacia local: `pull` y `pushDelete` son no-ops. Solo
/// `pushUpsert` envía al backend; si el server resuelve un conflicto LWW
/// reescribimos el row local con la versión que ganó.
///
/// Patrón inverso al de [ParserSyncHandler] (que es pull-only).
class ParserFeedbackSyncHandler implements SyncHandler {
  final ParserFeedbackLocalStore _local;
  final ParserFeedbackRemoteService _remote;

  ParserFeedbackSyncHandler({
    required ParserFeedbackLocalStore local,
    required ParserFeedbackRemoteService remote,
  })  : _local = local,
        _remote = remote;

  @override
  String get entityType => 'parser_feedback';

  /// Después de transactions (6): coherente que la transacción aprobada esté
  /// server-side antes que su feedback (no hay FK pero ayuda al admin a
  /// inspeccionarlas en orden).
  @override
  int get syncOrder => 7;

  @override
  Future<SyncPullResult> pull(DateTime? updatedSince) async {
    return SyncPullResult(items: const [], syncedAt: DateTime.now().toUtc());
  }

  @override
  Future<void> saveLocally(Map<String, dynamic> data) async {
    // Push-only: pull retorna lista vacía, así que esto rara vez se invoca.
    // Si alguna vez el handler pasara a pull (e.g. pantalla admin server-side
    // que distribuya feedback), el local store ya queda enchufado.
    await _local.upsertRow(data);
  }

  @override
  Future<SyncPushResult> pushUpsert(String payloadJson) async {
    final map = jsonDecode(payloadJson) as Map<String, dynamic>;
    final response = await _remote.upsertFeedback(map);
    if (response.conflictResolved) {
      final serverModel = ParserFeedbackModel.fromProto(response.feedback);
      return SyncPushResult(
        conflictResolved: true,
        serverData: serverModel.toMap(),
      );
    }
    return const SyncPushResult(conflictResolved: false);
  }

  @override
  Future<void> pushDelete(String entityId, DateTime deletedAt) async {
    // Push-only sin Delete: el cliente nunca borra feedback.
  }
}
