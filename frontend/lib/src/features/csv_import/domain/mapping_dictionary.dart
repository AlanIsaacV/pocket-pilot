/// Diccionario de mapeo nombre → UUID construido por la UI.
///
/// Después de la extracción, la UI presenta los nombres únicos al usuario
/// para que los resuelva (auto-match o selección manual). El resultado
/// se empaqueta aquí para que [CsvImportService.buildInsertBatch] pueda
/// sustituir cada nombre por su UUID correspondiente.
class MappingDictionary {
  /// "Banamex" → "uuid-...", "BBVA" → "uuid-..."
  final Map<String, String> accountIdMap;

  /// "Comida" → "uuid-...", "Transporte" → "uuid-..."
  final Map<String, String> categoryIdMap;

  /// "Viaje" → "uuid-...", "Urgente" → "uuid-..."
  final Map<String, String> tagIdMap;

  const MappingDictionary({
    required this.accountIdMap,
    required this.categoryIdMap,
    required this.tagIdMap,
  });
}
