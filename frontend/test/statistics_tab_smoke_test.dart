import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:pocket_pilot/src/core/db/database_helper.dart';
import 'package:pocket_pilot/src/features/budgets/data/budget_local_store.dart';
import 'package:pocket_pilot/src/features/dashboard/ui/dashboard_filter_view_model.dart';
import 'package:pocket_pilot/src/features/statistics/data/statistics_local_store.dart';
import 'package:pocket_pilot/src/features/statistics/data/statistics_repository.dart';
import 'package:pocket_pilot/src/features/statistics/domain/category_series_dto.dart';
import 'package:pocket_pilot/src/features/statistics/domain/trend.dart';
import 'package:pocket_pilot/src/features/statistics/ui/statistics_tab.dart';
import 'package:pocket_pilot/src/features/statistics/ui/statistics_view_model.dart';

class _FakeRepo extends StatisticsRepository {
  final List<CategorySeriesDTO> data;
  final bool shouldThrow;

  _FakeRepo({this.data = const [], this.shouldThrow = false})
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
    if (shouldThrow) throw StateError('db down');
    return data;
  }
}

Widget _wrap({required _FakeRepo repo}) {
  final filter = DashboardFilterViewModel()..setCurrencyCode('MXN');
  return MaterialApp(
    home: MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: filter),
        ChangeNotifierProvider(
          create: (_) => StatisticsViewModel(
            repository: repo,
            filterViewModel: filter,
            now: () => DateTime.utc(2026, 4, 17),
          )..loadOnAppear(),
        ),
      ],
      child: const Scaffold(body: StatisticsTab()),
    ),
  );
}

void main() {
  testWidgets(
    'shows expense + income sections when data present',
    (tester) async {
      await tester.pumpWidget(_wrap(
        repo: _FakeRepo(data: const [
          CategorySeriesDTO(
            categoryId: 'c1',
            name: 'Comida',
            color: '',
            icon: '',
            kind: 'expense',
            currencyCode: 'MXN',
            totalCents: 600000,
            avgMonthlyCents: 100000,
            currentMonthCents: 120000,
            trend: Trend.up,
          ),
          CategorySeriesDTO(
            categoryId: 'c2',
            name: 'Salario',
            color: '',
            icon: '',
            kind: 'income',
            currencyCode: 'MXN',
            totalCents: 1200000,
            avgMonthlyCents: 200000,
            currentMonthCents: 200000,
            trend: Trend.flat,
          ),
        ]),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Gastos'), findsOneWidget);
      expect(find.text('Ingresos'), findsOneWidget);
      expect(find.text('Comida'), findsOneWidget);
      expect(find.text('Salario'), findsOneWidget);
    },
  );

  testWidgets('empty state when repository returns nothing', (tester) async {
    await tester.pumpWidget(_wrap(repo: _FakeRepo()));
    await tester.pumpAndSettle();

    expect(find.text('Aún no hay suficiente historial'), findsOneWidget);
  });

  testWidgets('error state shows retry button', (tester) async {
    await tester.pumpWidget(_wrap(repo: _FakeRepo(shouldThrow: true)));
    await tester.pumpAndSettle();

    expect(find.text('Reintentar'), findsOneWidget);
  });
}
