import 'package:flutter_test/flutter_test.dart';

import 'package:pocket_pilot/src/core/db/database_helper.dart';
import 'package:pocket_pilot/src/features/budgets/data/budget_local_store.dart';
import 'package:pocket_pilot/src/features/dashboard/ui/dashboard_filter_view_model.dart';
import 'package:pocket_pilot/src/features/statistics/data/statistics_local_store.dart';
import 'package:pocket_pilot/src/features/statistics/data/statistics_repository.dart';
import 'package:pocket_pilot/src/features/statistics/domain/category_series_dto.dart';
import 'package:pocket_pilot/src/features/statistics/domain/trend.dart';
import 'package:pocket_pilot/src/features/statistics/ui/statistics_view_model.dart';

void main() {
  test('initial load with no currency emits empty list', () async {
    final filter = DashboardFilterViewModel();
    final vm = StatisticsViewModel(
      repository: _FakeRepo(rowsByCurrency: const {}),
      filterViewModel: filter,
      now: () => DateTime.utc(2026, 4, 17),
    );

    await vm.refresh();

    expect(vm.isLoading, false);
    expect(vm.series, isEmpty);
    expect(vm.errorMessage, isNull);
  });

  test('window change triggers reload', () async {
    final filter = DashboardFilterViewModel()..setCurrencyCode('MXN');
    final repo = _FakeRepo(
      rowsByCurrency: {
        'MXN': 1,
      },
    );
    final vm = StatisticsViewModel(
      repository: repo,
      filterViewModel: filter,
      now: () => DateTime.utc(2026, 4, 17),
    );
    await vm.refresh();
    final priorCalls = repo.callsByMonths[12] ?? 0;

    vm.setWindow(12);
    // Allow the unawaited refresh to complete.
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(vm.months, 12);
    expect(repo.callsByMonths[12], priorCalls + 1);
  });

  test('currency change triggers reload', () async {
    final filter = DashboardFilterViewModel()..setCurrencyCode('MXN');
    final repo = _FakeRepo(rowsByCurrency: const {'MXN': 1, 'USD': 1});
    final vm = StatisticsViewModel(
      repository: repo,
      filterViewModel: filter,
      now: () => DateTime.utc(2026, 4, 17),
    );
    await vm.refresh();
    expect(repo.lastCurrency, 'MXN');

    filter.setCurrencyCode('USD');
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(repo.lastCurrency, 'USD');
  });

  test('repository failure surfaces errorMessage', () async {
    final filter = DashboardFilterViewModel()..setCurrencyCode('MXN');
    final vm = StatisticsViewModel(
      repository: _ThrowingRepo(),
      filterViewModel: filter,
      now: () => DateTime.utc(2026, 4, 17),
    );

    await vm.refresh();

    expect(vm.errorMessage, isNotNull);
    expect(vm.series, isEmpty);
  });
}

class _FakeRepo extends StatisticsRepository {
  final Map<String, int> rowsByCurrency;
  final Map<int, int> callsByMonths = {};
  String? lastCurrency;

  _FakeRepo({required this.rowsByCurrency})
      : super(
          local: StatisticsLocalStore(db: DatabaseHelper()),
          budgetLocal: BudgetLocalStore(db: DatabaseHelper()),
        );

  @override
  Future<List<CategorySeriesDTO>> getSeriesList({
    required String currencyCode,
    required String windowStart,
    required String windowEnd,
    required String windowMid,
    required String currentYm,
    required int months,
  }) async {
    lastCurrency = currencyCode;
    callsByMonths[months] = (callsByMonths[months] ?? 0) + 1;
    final count = rowsByCurrency[currencyCode] ?? 0;
    return List.generate(
      count,
      (i) => CategorySeriesDTO(
        categoryId: 'c$i',
        name: 'Cat $i',
        color: '',
        icon: '',
        kind: 'expense',
        currencyCode: currencyCode,
        totalCents: 100,
        avgMonthlyCents: 100 ~/ months,
        currentMonthCents: 10,
        trend: Trend.flat,
      ),
    );
  }
}

class _ThrowingRepo extends _FakeRepo {
  _ThrowingRepo() : super(rowsByCurrency: const {});

  @override
  Future<List<CategorySeriesDTO>> getSeriesList({
    required String currencyCode,
    required String windowStart,
    required String windowEnd,
    required String windowMid,
    required String currentYm,
    required int months,
  }) async {
    throw StateError('db down');
  }
}
