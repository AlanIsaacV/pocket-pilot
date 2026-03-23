// ============================================================
// SyncHandler — interfaz que cada entidad debe implementar
// ============================================================
//
// SyncService no conoce los detalles de cada entidad. En su lugar,
// trabaja con una lista de SyncHandler, uno por tipo de entidad.
// Cada handler sabe cómo:
//   - Hacer un pull delta desde el servidor.
//   - Guardar un item del servidor en SQLite local.
//   - Hacer push de una entrada pendiente del outbox al servidor.
//   - Enviar un soft-delete al servidor.

/// Resultado del pull: lista de items del servidor + timestamp del servidor.
class SyncPullResult {
  final List<SyncItem> items;

  /// Timestamp del servidor al momento de la query.
  /// Se guarda como last_synced_at para el próximo delta pull.
  final DateTime syncedAt;

  const SyncPullResult({required this.items, required this.syncedAt});
}

/// Un item retornado por el servidor durante el pull.
class SyncItem {
  final String id;

  /// updated_at del servidor, usado para la resolución de conflictos LWW.
  final DateTime updatedAt;

  /// Datos del item en formato Map (sin user_id, para guardar en SQLite local).
  final Map<String, dynamic> data;

  const SyncItem({
    required this.id,
    required this.updatedAt,
    required this.data,
  });
}

/// Resultado del push de un upsert al servidor.
class SyncPushResult {
  /// true si el servidor tenía una versión más reciente (conflicto LWW resuelto).
  /// En ese caso, [serverData] contiene la versión aceptada.
  final bool conflictResolved;

  /// Datos del servidor (para guardar localmente) cuando hay conflicto.
  final Map<String, dynamic>? serverData;

  const SyncPushResult({required this.conflictResolved, this.serverData});
}

/// Contrato que cada entidad implementa para participar en el ciclo de sync.
abstract class SyncHandler {
  /// Identificador del tipo de entidad: 'account', 'category', 'tag', 'transaction'.
  String get entityType;

  /// Pull delta: trae registros del servidor.
  ///
  /// Si [updatedSince] es null → primer sync (trae todos los registros activos).
  /// Si [updatedSince] está definido → delta sync (solo registros más recientes).
  Future<SyncPullResult> pull(String userId, DateTime? updatedSince);

  /// Guarda un item del servidor en SQLite local.
  /// [data] es el Map retornado por [SyncItem.data] o [SyncPushResult.serverData].
  Future<void> saveLocally(Map<String, dynamic> data);

  /// Push de un upsert pendiente al servidor.
  ///
  /// [payloadJson] es el JSON guardado en sync_outbox (incluye user_id).
  /// Retorna el resultado con conflict_resolved y, si aplica, la versión del servidor.
  Future<SyncPushResult> pushUpsert(String payloadJson);

  /// Push de un soft-delete pendiente al servidor.
  Future<void> pushDelete(String entityId, String userId, DateTime deletedAt);
}
