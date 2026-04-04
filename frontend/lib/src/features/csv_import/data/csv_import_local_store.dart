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
import 'package:pocket_pilot/src/features/csv_import/domain/csv_insert_batch.dart';

class CsvImportLocalStore {
  final DatabaseHelper _db;

  CsvImportLocalStore({required DatabaseHelper db}) : _db = db;

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
