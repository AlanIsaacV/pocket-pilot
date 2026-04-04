/// Batch listo para inserción atómica en SQLite.
///
/// Contiene los mapas de transacciones (para la tabla `transactions`)
/// y las entradas de outbox (para la tabla `sync_outbox`), ambos
/// preparados para ejecutarse en un solo `db.batch()`.
class CsvInsertBatch {
  final List<Map<String, dynamic>> transactionMaps;
  final List<Map<String, dynamic>> outboxEntries;

  const CsvInsertBatch({
    required this.transactionMaps,
    required this.outboxEntries,
  });
}
