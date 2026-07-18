import 'csv_transaction_row.dart';

/// A CSV row after its account name has been resolved to a local account ID.
class CsvDuplicateCandidate {
  final int rowIndex;
  final CsvTransactionRow row;
  final String accountId;

  const CsvDuplicateCandidate({
    required this.rowIndex,
    required this.row,
    required this.accountId,
  });
}

/// The transaction fields needed for statement reconciliation.
///
/// [deletedAt] is retained here even though the local query filters deleted
/// rows, so the pure matcher remains safe for every caller.
class CsvExistingTransaction {
  final String id;
  final String accountId;
  final int amountCents;
  final String date;
  final DateTime? deletedAt;

  const CsvExistingTransaction({
    required this.id,
    required this.accountId,
    required this.amountCents,
    required this.date,
    this.deletedAt,
  });
}

/// A one-to-one pairing between a CSV row and an existing transaction.
class CsvDuplicateMatch {
  final int rowIndex;
  final String existingTransactionId;

  const CsvDuplicateMatch({
    required this.rowIndex,
    required this.existingTransactionId,
  });
}

/// Finds likely duplicate statement rows using account, amount, and date.
///
/// Candidate pairs are considered globally by closest date first. This makes
/// matching deterministic and ensures an existing transaction is absorbed by
/// at most one CSV row.
List<CsvDuplicateMatch> findCsvDuplicateMatches({
  required List<CsvDuplicateCandidate> csvRows,
  required List<CsvExistingTransaction> existingTransactions,
}) {
  final candidates =
      <({int rowIndex, String transactionId, int dateDistance})>[];

  for (final csvRow in csvRows) {
    final csvDate = DateTime.tryParse(csvRow.row.date);
    if (csvDate == null) continue;
    final amountCents = (csvRow.row.amount * 100).round();

    for (final transaction in existingTransactions) {
      if (transaction.deletedAt != null ||
          transaction.accountId != csvRow.accountId ||
          transaction.amountCents != amountCents) {
        continue;
      }

      final transactionDate = DateTime.tryParse(transaction.date);
      if (transactionDate == null) continue;
      final dateDistance = _dateDistanceInDays(csvDate, transactionDate);
      if (dateDistance <= 3) {
        candidates.add((
          rowIndex: csvRow.rowIndex,
          transactionId: transaction.id,
          dateDistance: dateDistance,
        ));
      }
    }
  }

  candidates.sort((a, b) {
    final byDistance = a.dateDistance.compareTo(b.dateDistance);
    if (byDistance != 0) return byDistance;
    final byRow = a.rowIndex.compareTo(b.rowIndex);
    if (byRow != 0) return byRow;
    return a.transactionId.compareTo(b.transactionId);
  });

  final matchedRows = <int>{};
  final matchedTransactions = <String>{};
  final matches = <CsvDuplicateMatch>[];
  for (final candidate in candidates) {
    if (matchedRows.contains(candidate.rowIndex) ||
        matchedTransactions.contains(candidate.transactionId)) {
      continue;
    }
    matchedRows.add(candidate.rowIndex);
    matchedTransactions.add(candidate.transactionId);
    matches.add(
      CsvDuplicateMatch(
        rowIndex: candidate.rowIndex,
        existingTransactionId: candidate.transactionId,
      ),
    );
  }

  matches.sort((a, b) => a.rowIndex.compareTo(b.rowIndex));
  return matches;
}

int _dateDistanceInDays(DateTime a, DateTime b) {
  final aDate = DateTime.utc(a.year, a.month, a.day);
  final bDate = DateTime.utc(b.year, b.month, b.day);
  return aDate.difference(bDate).inDays.abs();
}
