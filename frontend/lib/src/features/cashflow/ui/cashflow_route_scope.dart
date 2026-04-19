// features/cashflow/ui/cashflow_route_scope.dart
//
// Provides repository + ViewModels for the Cashflow full-screen view.
// Standalone: creates a fresh DashboardFilterViewModel (seeded from the
// `?currency=` query param) and StatisticsFilterViewModel (seeded from
// `?window=`). Mirrors the shape of StatisticsCategoriesRouteScope.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:pocket_pilot/src/core/db/database_helper.dart';
import 'package:pocket_pilot/src/features/cashflow/data/cashflow_local_store.dart';
import 'package:pocket_pilot/src/features/cashflow/data/cashflow_repository.dart';
import 'package:pocket_pilot/src/features/cashflow/ui/cashflow_view_model.dart';
import 'package:pocket_pilot/src/features/dashboard/ui/dashboard_filter_view_model.dart';
import 'package:pocket_pilot/src/features/statistics/ui/statistics_filter_view_model.dart';

class CashflowRouteScope extends StatelessWidget {
  final Widget child;
  final int initialWindow;
  final String? initialCurrencyCode;

  const CashflowRouteScope({
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
        Provider<CashflowRepository>(
          create: (ctx) => CashflowRepository(
            local: CashflowLocalStore(db: ctx.read<DatabaseHelper>()),
          ),
        ),
        ChangeNotifierProvider(
          create: (ctx) => CashflowViewModel(
            repository: ctx.read<CashflowRepository>(),
            filterViewModel: ctx.read<DashboardFilterViewModel>(),
            statsFilterViewModel: ctx.read<StatisticsFilterViewModel>(),
          )..loadOnAppear(),
        ),
      ],
      child: child,
    );
  }
}
