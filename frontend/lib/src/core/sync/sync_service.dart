import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:pocket_pilot/src/core/sync/scheduled_generation_orchestrator.dart';
import 'package:pocket_pilot/src/core/sync/sync_handler.dart';
import 'package:pocket_pilot/src/core/sync/sync_metadata_store.dart';
import 'package:pocket_pilot/src/core/sync/sync_outbox.dart';
import 'package:pocket_pilot/src/core/sync/sync_status_remote_service.dart';

enum SyncStatus { idle, syncing, error }

class SyncService implements SyncRunner {
  final SyncOutbox _outbox;
  final SyncMetadataStore _metadataStore;
  final SyncStatusRemoteService _statusService;
  final Map<String, SyncHandler> _handlers;

  final ValueNotifier<SyncStatus> status = ValueNotifier(SyncStatus.idle);

  bool _syncRequested = false;
  Future<void>? _activeSyncFuture;

  /// Número de entidades cuyo pull fue saltado en el último ciclo porque el
  /// cursor del servidor no era más reciente que el local. Expuesto para la
  /// pantalla de Sync Status.
  int lastCycleSkippedCount = 0;

  SyncService({
    required SyncOutbox outbox,
    required SyncMetadataStore metadataStore,
    required SyncStatusRemoteService statusService,
    required List<SyncHandler> handlers,
  }) : _outbox = outbox,
       _metadataStore = metadataStore,
       _statusService = statusService,
       _handlers = {for (final h in handlers) h.entityType: h};

  /// Ejecuta un ciclo completo de sync: Pull -> Push para todas las entidades.
  /// Si llega otra petición mientras hay un sync en curso, se agenda una
  /// segunda pasada al terminar la actual (coalescing de solicitudes).
  @override
  Future<void> sync() {
    _syncRequested = true;
    _activeSyncFuture ??= _runSyncLoop();
    return _activeSyncFuture!;
  }

  /// Conteo de entradas pendientes en el outbox (para la UI).
  Future<int> pendingCount() => _outbox.countPending();

  /// Timestamp del último sync exitoso global (para la UI).
  Future<DateTime?> lastSyncedAt() => _metadataStore.getLastSyncedAtGlobal();

  Future<void> _runSyncLoop() async {
    status.value = SyncStatus.syncing;
    bool hadError = false;
    try {
      await _outbox.resetAllRetries();
      final sorted = _handlers.values.toList()
        ..sort((a, b) => a.syncOrder.compareTo(b.syncOrder));
      while (_syncRequested) {
        _syncRequested = false;

        // Preflight: ask the server for per-entity cursors so we can skip
        // pulls where nothing changed. If the call fails (network, 5xx),
        // fall back to pulling every entity.
        Map<String, DateTime>? serverCursors;
        try {
          serverCursors = await _statusService.getSyncStatus();
        } catch (_) {
          serverCursors = null;
        }

        int skipped = 0;
        for (final handler in sorted) {
          final localCursor = await _metadataStore.getLastSyncedAt(
            handler.entityType,
          );
          final serverCursor = serverCursors?[handler.entityType];

          final shouldSkip =
              serverCursors != null &&
              localCursor != null &&
              serverCursor != null &&
              !serverCursor.isAfter(localCursor);

          if (shouldSkip) {
            skipped++;
          } else {
            await _pullEntity(handler);
          }
          await _pushEntity(handler);
        }
        lastCycleSkippedCount = skipped;
      }
    } catch (_) {
      hadError = true;
    } finally {
      status.value = hadError ? SyncStatus.error : SyncStatus.idle;
      _activeSyncFuture = null;
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
