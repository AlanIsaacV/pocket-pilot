// ============================================================
// DashboardScreen — shell with TabBar (Resumen / Estadísticas)
// ============================================================
//
// The actual body widgets live in:
//   - dashboard_summary_tab.dart  (Resumen)
//   - features/statistics/ui/statistics_tab.dart  (Estadísticas)

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'package:pocket_pilot/src/features/dashboard/ui/dashboard_filter_view_model.dart';
import 'package:pocket_pilot/src/features/dashboard/ui/dashboard_view_model.dart';
import 'package:pocket_pilot/src/features/dashboard/ui/widgets/dashboard_filter_sheet.dart';
import 'package:pocket_pilot/src/features/statistics/ui/statistics_tab.dart';
import 'package:pocket_pilot/src/ui/screens/dashboard/dashboard_summary_tab.dart';
import 'package:pocket_pilot/src/ui/widgets/notification_bell.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final filterVM = context.watch<DashboardFilterViewModel>();

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        floatingActionButton: FloatingActionButton(
          onPressed: () => context.go('/transactions/new'),
          tooltip: 'Nueva transacción',
          child: const Icon(Icons.add),
        ),
        appBar: AppBar(
          title: Text(
            'Dashboard',
            style: GoogleFonts.ibmPlexSans(
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
          ),
          actions: [
            const NotificationBell(),
            _FilterButton(hasFilters: filterVM.hasFilters),
            const SizedBox(width: 8),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Resumen'),
              Tab(text: 'Estadísticas'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            DashboardSummaryTab(),
            StatisticsTab(),
          ],
        ),
      ),
    );
  }
}

class _FilterButton extends StatelessWidget {
  final bool hasFilters;

  const _FilterButton({required this.hasFilters});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Stack(
      children: [
        IconButton(
          icon: Icon(
            Icons.tune_outlined,
            color: hasFilters ? cs.primary : cs.onSurfaceVariant,
          ),
          onPressed: () {
            showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              backgroundColor: Theme.of(context).scaffoldBackgroundColor,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              ),
              builder: (_) {
                return MultiProvider(
                  providers: [
                    ChangeNotifierProvider.value(
                      value: context.read<DashboardFilterViewModel>(),
                    ),
                    ChangeNotifierProvider.value(
                      value: context.read<DashboardViewModel>(),
                    ),
                  ],
                  child: const DashboardFilterSheet(),
                );
              },
            );
          },
        ),
        if (hasFilters)
          Positioned(
            top: 8,
            right: 8,
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: cs.primary,
                shape: BoxShape.circle,
              ),
            ),
          ),
      ],
    );
  }
}
