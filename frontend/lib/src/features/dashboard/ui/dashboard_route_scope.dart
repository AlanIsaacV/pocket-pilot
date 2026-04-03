import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:pocket_pilot/src/core/db/database_helper.dart';
import 'package:pocket_pilot/src/features/dashboard/data/dashboard_local_store.dart';
import 'package:pocket_pilot/src/features/dashboard/data/dashboard_repository.dart';
import 'package:pocket_pilot/src/features/dashboard/ui/dashboard_filter_view_model.dart';
import 'package:pocket_pilot/src/features/dashboard/ui/dashboard_view_model.dart';

class DashboardRouteScope extends StatelessWidget {
  final Widget child;

  const DashboardRouteScope({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => DashboardFilterViewModel(),
        ),
        ChangeNotifierProvider(
          create: (ctx) {
            final db = ctx.read<DatabaseHelper>();
            final localStore = DashboardLocalStore(db: db);
            final repository = DashboardRepository(local: localStore);
            final filterVM = ctx.read<DashboardFilterViewModel>();
            return DashboardViewModel(
              repository: repository,
              filterViewModel: filterVM,
            )..loadOnAppear();
          },
        ),
      ],
      child: child,
    );
  }
}
