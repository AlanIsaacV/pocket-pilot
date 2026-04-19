// features/cashflow/ui/cashflow_route_scope.dart
//
// Providers para la vista full-screen Cashflow. Hereda
// DashboardFilterViewModel del DashboardRouteScope padre — el shell
// mantiene ese scope vivo al navegar a subrutas.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:pocket_pilot/src/core/db/database_helper.dart';
import 'package:pocket_pilot/src/features/cashflow/data/cashflow_local_store.dart';
import 'package:pocket_pilot/src/features/cashflow/data/cashflow_repository.dart';
import 'package:pocket_pilot/src/features/cashflow/ui/cashflow_view_model.dart';
import 'package:pocket_pilot/src/features/dashboard/ui/dashboard_filter_view_model.dart';

class CashflowRouteScope extends StatelessWidget {
  final Widget child;

  const CashflowRouteScope({
    super.key,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<CashflowRepository>(
          create: (ctx) => CashflowRepository(
            local: CashflowLocalStore(db: ctx.read<DatabaseHelper>()),
          ),
        ),
        ChangeNotifierProvider(
          create: (ctx) => CashflowViewModel(
            repository: ctx.read<CashflowRepository>(),
            filterViewModel: ctx.read<DashboardFilterViewModel>(),
          )..loadOnAppear(),
        ),
      ],
      child: child,
    );
  }
}
