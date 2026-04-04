import 'package:pocket_pilot/src/features/csv_import/domain/csv_transaction_row.dart';

/// Resultado de la Fase 1 (extracción).
///
/// Contiene las filas parseadas del CSV y los conjuntos de nombres
/// únicos de entidades que la UI necesita resolver a UUIDs.
class CsvExtractionResult {
  final List<CsvTransactionRow> rows;
  final Set<String> uniqueAccountNames;
  final Set<String> uniqueCategoryNames;
  final Set<String> uniqueTagNames;

  const CsvExtractionResult({
    required this.rows,
    required this.uniqueAccountNames,
    required this.uniqueCategoryNames,
    required this.uniqueTagNames,
  });
}
