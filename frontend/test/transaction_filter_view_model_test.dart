// frontend/test/transaction_filter_view_model_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_pilot/src/features/transactions/ui/transaction_filter_view_model.dart';

void main() {
  late TransactionFilterViewModel vm;

  setUp(() {
    vm = TransactionFilterViewModel();
  });

  group('TransactionFilterViewModel', () {
    test('initial state is Quick page with 30d selected', () {
      expect(vm.activePageIndex, 0);
      expect(vm.quickSelection, QuickRange.d30);
      expect(vm.resolvedFilter.type, isNull);
      expect(vm.resolvedFilter.accountId, isNull);
    });

    test('setQuickSelection updates filter and notifies', () {
      var notified = false;
      vm.addListener(() => notified = true);

      vm.setQuickSelection(QuickRange.d7);
      expect(vm.quickSelection, QuickRange.d7);
      expect(notified, isTrue);
    });

    test('setPeriodGranularity resets offset to 0', () {
      vm.setActivePageIndex(1);
      vm.navigatePeriod(-1); // go back one
      expect(vm.periodOffset, -1);

      vm.setPeriodGranularity(PeriodGranularity.year);
      expect(vm.periodOffset, 0);
      expect(vm.periodGranularity, PeriodGranularity.year);
    });

    test('navigatePeriod cannot go forward past 0', () {
      vm.setActivePageIndex(1);
      vm.navigatePeriod(1); // try to go forward from 0
      expect(vm.periodOffset, 0);
    });

    test('navigatePeriod can go back', () {
      vm.setActivePageIndex(1);
      vm.navigatePeriod(-1);
      expect(vm.periodOffset, -1);
      vm.navigatePeriod(-1);
      expect(vm.periodOffset, -2);
    });

    test('setCustomRange updates from and to', () {
      final from = DateTime(2026, 1, 1);
      final to = DateTime(2026, 1, 31);
      vm.setCustomRange(from, to);
      expect(vm.customFrom, from);
      expect(vm.customTo, to);
    });

    test('setAccountId updates resolvedFilter', () {
      vm.setAccountId('acc-1');
      expect(vm.resolvedFilter.accountId, 'acc-1');
    });

    test('setAccountId with null clears it', () {
      vm.setAccountId('acc-1');
      vm.setAccountId(null);
      expect(vm.resolvedFilter.accountId, isNull);
    });

    test('toggleCategory adds and removes', () {
      vm.toggleCategory('cat-1');
      expect(vm.resolvedFilter.categoryIds, ['cat-1']);

      vm.toggleCategory('cat-2');
      expect(vm.resolvedFilter.categoryIds, containsAll(['cat-1', 'cat-2']));

      vm.toggleCategory('cat-1');
      expect(vm.resolvedFilter.categoryIds, ['cat-2']);
    });

    test('clearAll resets to defaults', () {
      vm.setAccountId('acc-1');
      vm.setType('expense');
      vm.toggleCategory('cat-1');
      vm.setActivePageIndex(2);

      vm.clearAll();

      expect(vm.activePageIndex, 0);
      expect(vm.quickSelection, QuickRange.d30);
      expect(vm.resolvedFilter.accountId, isNull);
      expect(vm.resolvedFilter.type, isNull);
      expect(vm.resolvedFilter.categoryIds, isEmpty);
    });

    test('periodLabel returns correct label for month offset', () {
      vm.setActivePageIndex(1);
      vm.setPeriodGranularity(PeriodGranularity.month);
      // offset 0 = current month
      expect(vm.periodLabel, isNotEmpty);
    });
  });
}
