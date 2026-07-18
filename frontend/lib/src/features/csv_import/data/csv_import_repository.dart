// ============================================================
// CsvImportRepository — orquestación para importación de CSV
// ============================================================
//
// Capa de orquestación que delega al LocalStore.
// En esta primera iteración es thin; punto de extensión para
// agregar validaciones, logging, o progreso en el futuro.

import 'package:pocket_pilot/src/features/csv_import/data/csv_import_local_store.dart';
import 'package:pocket_pilot/src/features/csv_import/domain/csv_duplicate_matcher.dart';
import 'package:pocket_pilot/src/features/csv_import/domain/csv_insert_batch.dart';

class CsvImportRepository {
  final CsvImportLocalStore _local;

  CsvImportRepository({required CsvImportLocalStore local}) : _local = local;

  /// Importa un batch de transacciones preparado por [CsvImportService].
  Future<void> importTransactions(CsvInsertBatch batch) async {
    await _local.insertBatch(batch);
  }

  Future<List<CsvExistingTransaction>> getTransactionsForAccounts(
    Set<String> accountIds,
  ) => _local.getTransactionsForAccounts(accountIds);
}
