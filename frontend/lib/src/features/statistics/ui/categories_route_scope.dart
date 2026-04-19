// features/statistics/ui/categories_route_scope.dart
//
// Providers para la vista full-screen Categorías dentro del hub de Stats.
// Hereda DashboardFilterViewModel del DashboardRouteScope padre (el shell
// mantiene ese scope vivo al navegar a subrutas), por lo que el estado del
// filtro se preserva.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:pocket_pilot/src/core/db/database_helper.dart';
import 'package:pocket_pilot/src/features/budgets/data/budget_local_store.dart';
import 'package:pocket_pilot/src/features/dashboard/ui/dashboard_filter_view_model.dart';
import 'package:pocket_pilot/src/features/statistics/data/statistics_local_store.dart';
import 'package:pocket_pilot/src/features/statistics/data/statistics_repository.dart';
import 'package:pocket_pilot/src/features/statistics/ui/statistics_view_model.dart';

class StatisticsCategoriesRouteScope extends StatelessWidget {
  final Widget child;

  const StatisticsCategoriesRouteScope({
    super.key,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
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
          )..loadOnAppear(),
        ),
      ],
      child: child,
    );
  }
}
