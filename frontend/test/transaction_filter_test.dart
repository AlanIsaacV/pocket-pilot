// frontend/test/transaction_filter_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_pilot/src/features/transactions/domain/transaction_filter.dart';

void main() {
  group('TransactionFilter', () {
    test('defaultFilter returns 30D range ending today', () {
      final filter = TransactionFilter.defaultFilter();
      final today = DateTime.now();
      final todayStr =
          '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

      expect(filter.dateTo, todayStr);
      expect(filter.accountId, isNull);
      expect(filter.categoryIds, isEmpty);
      expect(filter.type, isNull);
      expect(filter.status, isNull);
      expect(filter.currencyCode, isNull);
    });

    test('typeValues maps transfer to both transfer types', () {
      final filter = TransactionFilter.defaultFilter().copyWith(type: 'transfer');
      expect(filter.typeValues, containsAll(['transfer_out', 'transfer_in']));
    });

    test('typeValues returns single value for income/expense', () {
      final income = TransactionFilter.defaultFilter().copyWith(type: 'income');
      expect(income.typeValues, ['income']);

      final expense = TransactionFilter.defaultFilter().copyWith(type: 'expense');
      expect(expense.typeValues, ['expense']);
    });

    test('typeValues returns null when type is null', () {
      final filter = TransactionFilter.defaultFilter();
      expect(filter.typeValues, isNull);
    });

    test('copyWith creates new instance with changed fields', () {
      final original = TransactionFilter.defaultFilter();
      final modified = original.copyWith(
        accountId: 'acc-1',
        categoryIds: ['cat-1', 'cat-2'],
        type: 'expense',
      );

      expect(modified.accountId, 'acc-1');
      expect(modified.categoryIds, ['cat-1', 'cat-2']);
      expect(modified.type, 'expense');
      // Unchanged fields
      expect(modified.dateFrom, original.dateFrom);
      expect(modified.dateTo, original.dateTo);
    });

    test('hasAdvancedFilters is false for default filter', () {
      expect(TransactionFilter.defaultFilter().hasAdvancedFilters, isFalse);
    });

    test('hasAdvancedFilters is true when any advanced field is set', () {
      final withAccount =
          TransactionFilter.defaultFilter().copyWith(accountId: 'acc-1');
      expect(withAccount.hasAdvancedFilters, isTrue);

      final withType =
          TransactionFilter.defaultFilter().copyWith(type: 'expense');
      expect(withType.hasAdvancedFilters, isTrue);
    });
  });
}
