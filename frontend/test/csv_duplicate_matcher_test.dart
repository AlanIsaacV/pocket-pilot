import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_pilot/src/features/csv_import/domain/csv_duplicate_matcher.dart';
import 'package:pocket_pilot/src/features/csv_import/domain/csv_transaction_row.dart';

void main() {
  CsvDuplicateCandidate csvRow({
    required int index,
    required String accountId,
    required String date,
    double amount = 123.45,
  }) => CsvDuplicateCandidate(
    rowIndex: index,
    accountId: accountId,
    row: CsvTransactionRow(
      date: date,
      type: 'EXPENSE',
      amount: amount,
      currencyCode: 'MXN',
      accountName: 'RappiCard',
      tagNames: const [],
      notes: '',
    ),
  );

  CsvExistingTransaction transaction({
    required String id,
    required String accountId,
    required String date,
    int amountCents = 12345,
    DateTime? deletedAt,
  }) => CsvExistingTransaction(
    id: id,
    accountId: accountId,
    amountCents: amountCents,
    date: date,
    deletedAt: deletedAt,
  );

  test(
    'flags exactly rows matching account, cents, and a three-day window',
    () {
      final matches = findCsvDuplicateMatches(
        csvRows: [
          csvRow(index: 0, accountId: 'rappi', date: '2026-07-10'),
          csvRow(index: 1, accountId: 'rappi', date: '2026-07-11', amount: 80),
          csvRow(index: 2, accountId: 'other', date: '2026-07-10'),
          csvRow(index: 3, accountId: 'rappi', date: '2026-07-14'),
        ],
        existingTransactions: [
          transaction(
            id: 'within-window',
            accountId: 'rappi',
            date: '2026-07-07',
          ),
          transaction(
            id: 'wrong-account',
            accountId: 'other',
            date: '2026-07-10',
          ),
          transaction(id: 'too-far', accountId: 'rappi', date: '2026-07-18'),
        ],
      );

      expect(matches.map((match) => match.rowIndex), [0, 2]);
    },
  );

  test('matches one existing transaction to only one identical CSV row', () {
    final matches = findCsvDuplicateMatches(
      csvRows: [
        csvRow(index: 0, accountId: 'rappi', date: '2026-07-10'),
        csvRow(index: 1, accountId: 'rappi', date: '2026-07-10'),
      ],
      existingTransactions: [
        transaction(id: 'existing', accountId: 'rappi', date: '2026-07-10'),
      ],
    );

    expect(matches, hasLength(1));
    expect(matches.single.rowIndex, 0);
    expect(matches.single.existingTransactionId, 'existing');
  });

  test('gives a contested transaction to the closest CSV date', () {
    final matches = findCsvDuplicateMatches(
      csvRows: [
        csvRow(index: 0, accountId: 'rappi', date: '2026-07-08'),
        csvRow(index: 1, accountId: 'rappi', date: '2026-07-10'),
      ],
      existingTransactions: [
        transaction(id: 'existing', accountId: 'rappi', date: '2026-07-10'),
      ],
    );

    expect(matches.single.rowIndex, 1);
  });

  test('does not match soft-deleted transactions', () {
    final matches = findCsvDuplicateMatches(
      csvRows: [csvRow(index: 0, accountId: 'rappi', date: '2026-07-10')],
      existingTransactions: [
        transaction(
          id: 'deleted',
          accountId: 'rappi',
          date: '2026-07-10',
          deletedAt: DateTime.utc(2026, 7, 11),
        ),
      ],
    );

    expect(matches, isEmpty);
  });
}
