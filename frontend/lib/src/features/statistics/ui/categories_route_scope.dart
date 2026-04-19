// features/statistics/ui/categories_route_scope.dart
//
// Providers for the Categorías full-screen view under the Statistics hub.
// Named StatisticsCategoriesRouteScope to avoid collision with the
// existing CategoriesRouteScope under features/categories.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:pocket_pilot/src/core/db/database_helper.dart';
import 'package:pocket_pilot/src/features/budgets/data/budget_local_store.dart';
import 'package:pocket_pilot/src/features/dashboard/ui/dashboard_filter_view_model.dart';
import 'package:pocket_pilot/src/features/statistics/data/statistics_local_store.dart';
import 'package:pocket_pilot/src/features/statistics/data/statistics_repository.dart';
import 'package:pocket_pilot/src/features/statistics/ui/statistics_filter_view_model.dart';
import 'package:pocket_pilot/src/features/statistics/ui/statistics_view_model.dart';

class StatisticsCategoriesRouteScope extends StatelessWidget {
  final Widget child;
  final int initialWindow;
  final String? initialCurrencyCode;

  const StatisticsCategoriesRouteScope({
    super.key,
    required this.child,
    this.initialWindow = 6,
    this.initialCurrencyCode,
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) {
            final vm = DashboardFilterViewModel();
            if (initialCurrencyCode != null) {
              vm.setCurrencyCode(initialCurrencyCode);
            }
            return vm;
          },
        ),
        ChangeNotifierProvider(
          create: (_) =>
              StatisticsFilterViewModel(initialWindow: initialWindow),
        ),
        Provider<StatisticsRepository>(
          create: (ctx) {
            final db = ctx.read<DatabaseHelper>();
            return StatisticsRepository(
              local: StatisticsLocalStore(db: db),
              budgetLocal: BudgetLocalStore(db: db),
            );
          },
        ),
        ChangeNotifierProvider(
          create: (ctx) => StatisticsViewModel(
            repository: ctx.read<StatisticsRepository>(),
            filterViewModel: ctx.read<DashboardFilterViewModel>(),
            statsFilterViewModel: ctx.read<StatisticsFilterViewModel>(),
          )..loadOnAppear(),
        ),
      ],
      child: child,
    );
  }
}
