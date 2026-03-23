// ============================================================
// SyncService — orquestador central del sync offline-first
// ============================================================
//
// Flujo de sync para cada tipo de entidad:
//
//   FASE 1 — PULL (delta):
//     1. Lee last_synced_at de SyncMetadataStore.
//     2. Pide al servidor solo los registros con updated_at > last_synced_at.
//     3. Para cada item del servidor:
//        - Si NO hay entrada pendiente en el outbox → guarda localmente.
//        - Si HAY entrada pendiente → aplica LWW por updated_at:
//            servidor más nuevo → guarda servidor, elimina outbox entry.
//            local más nuevo    → mantiene outbox entry para el push.
//     4. Actualiza last_synced_at con el synced_at del servidor.
//
//   FASE 2 — PUSH (outbox):
//     5. Para cada entrada pendiente en sync_outbox:
//        - 'upsert' → envía al servidor, aplica versión aceptada localmente.
//        - 'delete' → envía soft-delete al servidor.
//        - En error de red → incrementa retry_count (máx 3 intentos).
//
// El flag _isSyncing evita ejecuciones concurrentes.
// Los errores de red en pull abortan esa entidad pero no detienen otras.

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
  })  : _outbox = outbox,
        _metadataStore = metadataStore,
        _handlers = {for (final h in handlers) h.entityType: h};

  /// Ejecuta un ciclo completo de sync: Pull → Push para todas las entidades.
  ///
  /// Si ya hay un sync en curso, este llamado retorna inmediatamente.
  /// [userId] es el ID del usuario autenticado (actualmente hardcodeado en el MVP).
  Future<void> sync(String userId) async {
    if (_isSyncing) return;
    _isSyncing = true;
    try {
      for (final handler in _handlers.values) {
        await _pullEntity(handler, userId);
        await _pushEntity(handler);
      }
    } finally {
      _isSyncing = false;
    }
  }

  // ----------------------------------------------------------
  // Implementación interna
  // ----------------------------------------------------------

  Future<void> _pullEntity(SyncHandler handler, String userId) async {
    try {
      final lastSyncedAt =
          await _metadataStore.getLastSyncedAt(handler.entityType);
      final result = await handler.pull(userId, lastSyncedAt);

      for (final item in result.items) {
        final outboxEntry =
            await _outbox.findByEntityId(handler.entityType, item.id);

        if (outboxEntry == null) {
          // Sin conflicto: guardar versión del servidor directamente.
          await handler.saveLocally(item.data);
        } else {
          // Conflicto: Last Write Wins por updated_at.
          final outboxUpdatedAt = _extractUpdatedAt(outboxEntry.payload);
          if (item.updatedAt.isAfter(outboxUpdatedAt)) {
            // El servidor tiene la versión más reciente.
            await handler.saveLocally(item.data);
            await _outbox.markSuccess(outboxEntry.id);
          }
          // else: la versión local es más reciente → mantener outbox entry para push.
        }
      }

      // Avanzar el cursor solo si el pull fue exitoso.
      await _metadataStore.updateLastSyncedAt(
          handler.entityType, result.syncedAt);
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
            // El servidor tenía la versión más reciente (race condition post-pull).
            await handler.saveLocally(result.serverData!);
          }
        } else if (entry.operation == 'delete') {
          final map = jsonDecode(entry.payload) as Map<String, dynamic>;
          final userId = map['user_id'] as String? ?? '';
          final deletedAt = DateTime.parse(map['deleted_at'] as String);
          await handler.pushDelete(entry.entityId, userId, deletedAt);
        }
        await _outbox.markSuccess(entry.id);
      } catch (e) {
        // Error de red o servidor: incrementar retry_count.
        await _outbox.markFailed(entry.id, e.toString());
      }
    }
  }

  /// Extrae updated_at del JSON del payload para la comparación LWW.
  DateTime _extractUpdatedAt(String payloadJson) {
    final map = jsonDecode(payloadJson) as Map<String, dynamic>;
    return DateTime.parse(map['updated_at'] as String).toUtc();
  }
}
