import 'package:flutter_test/flutter_test.dart';

import 'package:pocket_pilot/src/core/db/database_helper.dart';
import 'package:pocket_pilot/src/features/budgets/data/budget_local_store.dart';
import 'package:pocket_pilot/src/features/statistics/data/statistics_local_store.dart';
import 'package:pocket_pilot/src/features/statistics/data/statistics_repository.dart';
import 'package:pocket_pilot/src/features/statistics/domain/category_series_dto.dart';
import 'package:pocket_pilot/src/features/statistics/domain/trend.dart';
import 'package:pocket_pilot/src/features/statistics/ui/statistics_view_model.dart';
import 'package:pocket_pilot/src/ui/widgets/dashboard_filter_view_model.dart';
import 'package:pocket_pilot/src/ui/widgets/temporal_page_view.dart';

void main() {
  test('initial load with no currency emits empty list', () async {
    final filter = DashboardFilterViewModel();
    final vm = StatisticsViewModel(
      repository: _FakeRepo(rowsByCurrency: const {}),
      filterViewModel: filter,
    );

    await vm.refresh();

    expect(vm.isLoading, false);
    expect(vm.series, isEmpty);
    expect(vm.errorMessage, isNull);
  });

  test('temporal change (Quick 1Y) triggers reload with ~12 months', () async {
    final filter = DashboardFilterViewModel()..setCurrencyCode('MXN');
    final repo = _FakeRepo(
      rowsByCurrency: {
        'MXN': 1,
      },
    );
    final vm = StatisticsViewModel(
      repository: repo,
      filterViewModel: filter,
    );
    await vm.refresh();
    final priorCallCount = repo.calls;

    filter.setQuickSelection(QuickRange.y1);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    // 365 days back can span 12 or 13 calendar months depending on `now`.
    expect(vm.months, inInclusiveRange(12, 13));
    expect(repo.calls, priorCallCount + 1);
  });

  test('currency change triggers reload', () async {
    final filter = DashboardFilterViewModel()..setCurrencyCode('MXN');
    final repo = _FakeRepo(rowsByCurrency: const {'MXN': 1, 'USD': 1});
    final vm = StatisticsViewModel(
      repository: repo,
      filterViewModel: filter,
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
    );

    await vm.refresh();

    expect(vm.errorMessage, isNotNull);
    expect(vm.series, isEmpty);
  });
}

class _FakeRepo extends StatisticsRepository {
  final Map<String, int> rowsByCurrency;
  int calls = 0;
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
    Set<String>? accountIds,
  }) async {
    lastCurrency = currencyCode;
    calls++;
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
    Set<String>? accountIds,
  }) async {
    throw StateError('db down');
  }
}
