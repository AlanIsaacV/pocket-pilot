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

import 'package:pocket_pilot/src/features/statistics/ui/statistics_tab.dart';
import 'package:pocket_pilot/src/ui/screens/dashboard/dashboard_summary_tab.dart';
import 'package:pocket_pilot/src/ui/widgets/notification_bell.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
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
          actions: const [
            NotificationBell(),
            SizedBox(width: 8),
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
