// ============================================================
// CsvImportLocalStore (DAO) — inserción masiva para CSV import
// ============================================================
//
// Ejecuta un solo db.batch() atómico que inserta transacciones
// y entradas de outbox en una misma operación.
//
// NOTA: Este es el único código que escribe directamente a sync_outbox
// sin pasar por SyncOutbox.enqueue(). Esto es intencional para lograr
// atomicidad en el batch. Si el esquema de sync_outbox cambia,
// este código debe actualizarse.

import 'package:sqflite/sqflite.dart';

import 'package:pocket_pilot/src/core/db/database_helper.dart';
import 'package:pocket_pilot/src/features/csv_import/domain/csv_duplicate_matcher.dart';
import 'package:pocket_pilot/src/features/csv_import/domain/csv_insert_batch.dart';

class CsvImportLocalStore {
  final DatabaseHelper _db;

  CsvImportLocalStore({required DatabaseHelper db}) : _db = db;

  /// Loads active transactions for the mapped CSV accounts.
  Future<List<CsvExistingTransaction>> getTransactionsForAccounts(
    Set<String> accountIds,
  ) async {
    if (accountIds.isEmpty) return const [];

    final db = await _db.database;
    final placeholders = List.filled(accountIds.length, '?').join(', ');
    final rows = await db.query(
      'transactions',
      columns: ['id', 'account_id', 'amount_cents', 'date', 'deleted_at'],
      where: 'account_id IN ($placeholders) AND deleted_at IS NULL',
      whereArgs: accountIds.toList(),
    );
    return rows
        .map(
          (row) => CsvExistingTransaction(
            id: row['id'] as String,
            accountId: row['account_id'] as String,
            amountCents: row['amount_cents'] as int,
            date: row['date'] as String,
            deletedAt: row['deleted_at'] == null
                ? null
                : DateTime.parse(row['deleted_at'] as String),
          ),
        )
        .toList();
  }

  /// Inserta todas las transacciones y entradas de outbox en un
  /// solo batch atómico.
  Future<void> insertBatch(CsvInsertBatch batch) async {
    final db = await _db.database;
    final dbBatch = db.batch();

    for (final txMap in batch.transactionMaps) {
      dbBatch.insert(
        'transactions',
        txMap,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    for (final entry in batch.outboxEntries) {
      dbBatch.insert(
        'sync_outbox',
        entry,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    await dbBatch.commit(noResult: true);
  }
}
