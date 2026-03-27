import 'dart:convert';

import 'package:pocket_pilot/src/core/sync/sync_handler.dart';
import 'package:pocket_pilot/src/core/sync/sync_metadata_store.dart';
import 'package:pocket_pilot/src/core/sync/sync_outbox.dart';

class SyncService {
  final SyncOutbox _outbox;
  final SyncMetadataStore _metadataStore;
  final Map<String, SyncHandler> _handlers;

  bool _isSyncing = false;

  SyncService({
    required SyncOutbox outbox,
    required SyncMetadataStore metadataStore,
    required List<SyncHandler> handlers,
  }) : _outbox = outbox,
       _metadataStore = metadataStore,
       _handlers = {for (final h in handlers) h.entityType: h};

  /// Ejecuta un ciclo completo de sync: Pull -> Push para todas las entidades.
  /// Si ya hay un sync en curso, este llamado retorna inmediatamente.
  Future<void> sync() async {
    if (_isSyncing) return;
    _isSyncing = true;
    try {
      for (final handler in _handlers.values) {
        await _pullEntity(handler);
        await _pushEntity(handler);
      }
    } finally {
      _isSyncing = false;
    }
  }

  Future<void> _pullEntity(SyncHandler handler) async {
    try {
      final lastSyncedAt = await _metadataStore.getLastSyncedAt(
        handler.entityType,
      );
      final result = await handler.pull(lastSyncedAt);

      for (final item in result.items) {
        final outboxEntry = await _outbox.findByEntityId(
          handler.entityType,
          item.id,
        );

        if (outboxEntry == null) {
          await handler.saveLocally(item.data);
        } else {
          // Conflicto: Last Write Wins por updated_at.
          final outboxUpdatedAt = _extractUpdatedAt(outboxEntry.payload);
          if (item.updatedAt.isAfter(outboxUpdatedAt)) {
            await handler.saveLocally(item.data);
            await _outbox.markSuccess(outboxEntry.id);
          }
          // else: versión local más reciente → mantener outbox entry para push.
        }
      }

      await _metadataStore.updateLastSyncedAt(
        handler.entityType,
        result.syncedAt,
      );
    } catch (_) {
      // Pull falló (sin conexión, error de servidor, etc.).
      // No actualizamos last_synced_at: el próximo sync reintentará desde el mismo punto.
    }
  }

  Future<void> _pushEntity(SyncHandler handler) async {
    final pending = await _outbox.getPending(handler.entityType);
    for (final entry in pending) {
      try {
        if (entry.operation == 'upsert') {
          final result = await handler.pushUpsert(entry.payload);
          if (result.conflictResolved && result.serverData != null) {
            await handler.saveLocally(result.serverData!);
          }
        } else if (entry.operation == 'delete') {
          final map = jsonDecode(entry.payload) as Map<String, dynamic>;
          final deletedAt = DateTime.parse(map['deleted_at'] as String);
          await handler.pushDelete(entry.entityId, deletedAt);
        }
        await _outbox.markSuccess(entry.id);
      } catch (e) {
        await _outbox.markFailed(entry.id, e.toString());
      }
    }
  }

  DateTime _extractUpdatedAt(String payloadJson) {
    final map = jsonDecode(payloadJson) as Map<String, dynamic>;
    return DateTime.parse(map['updated_at'] as String).toUtc();
  }
}
