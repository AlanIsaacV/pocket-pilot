import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_pilot/src/features/csv_import/data/csv_import_service.dart';
import 'package:pocket_pilot/src/features/csv_import/domain/csv_transaction_row.dart';
import 'package:pocket_pilot/src/features/csv_import/domain/mapping_dictionary.dart';
import 'package:pocket_pilot/src/features/csv_import/ui/csv_import_view_model.dart';
import 'package:uuid/uuid.dart';

void main() {
  test('buildInsertBatch stamps imported transactions and outbox payloads', () {
    final service = CsvImportService(uuid: const Uuid());
    final batch = service.buildInsertBatch(
      [
        const CsvTransactionRow(
          date: '2026-07-10',
          type: 'EXPENSE',
          amount: 123.45,
          currencyCode: 'MXN',
          accountName: 'RappiCard',
          tagNames: [],
          notes: 'Coffee',
        ),
      ],
      const MappingDictionary(
        accountIdMap: {'RappiCard': 'account-1'},
        categoryIdMap: {},
        tagIdMap: {},
      ),
    );

    expect(batch.transactionMaps.single['source'], 'import_csv');
    final payload =
        jsonDecode(batch.outboxEntries.single['payload'] as String)
            as Map<String, dynamic>;
    expect(payload['source'], 'import_csv');
  });

  test('buildInsertBatch includes only non-duplicate selected rows', () {
    const rows = [
      CsvTransactionRow(
        date: '2026-07-10',
        type: 'EXPENSE',
        amount: 10,
        currencyCode: 'MXN',
        accountName: 'Cuenta',
        tagNames: [],
        notes: '',
      ),
      CsvTransactionRow(
        date: '2026-07-11',
        type: 'EXPENSE',
        amount: 20,
        currencyCode: 'MXN',
        accountName: 'Cuenta',
        tagNames: [],
        notes: '',
      ),
      CsvTransactionRow(
        date: '2026-07-12',
        type: 'EXPENSE',
        amount: 30,
        currencyCode: 'MXN',
        accountName: 'Cuenta',
        tagNames: [],
        notes: '',
      ),
    ];
    const flaggedDuplicateRowIndices = {1};
    final includedRowIndices = Set<int>.from({0, 1, 2})
      ..removeAll(flaggedDuplicateRowIndices);
    final batch = CsvImportService(uuid: const Uuid()).buildInsertBatch(
      rowsIncludedForImport(rows, includedRowIndices),
      const MappingDictionary(
        accountIdMap: {'Cuenta': 'account-1'},
        categoryIdMap: {},
        tagIdMap: {},
      ),
    );

    expect(batch.transactionMaps, hasLength(2));
    expect(batch.transactionMaps.map((row) => row['amount_cents']), [
      1000,
      3000,
    ]);
  });

  test(
    'manual exclusion of every row survives duplicate refresh reconciliation',
    () {
      expect(
        reconcileIncludedRowIndices(
          includedRowIndices: const {},
          previousDuplicateRowIndices: const {0, 1},
          matchedRowIndices: const {0, 1},
          rowCount: 2,
          initializeIncludedRows: false,
        ),
        isEmpty,
      );
    },
  );
}
