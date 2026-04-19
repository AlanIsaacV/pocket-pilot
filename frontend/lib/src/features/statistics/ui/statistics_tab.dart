// features/statistics/ui/statistics_tab.dart
//
// The Statistics dashboard tab is now a HUB: a small menu of available
// visualizations. Each entry navigates to its own screen with scroll
// vertical and filters seeded from here. The shared window lives in
// StatisticsFilterViewModel (see dashboard_route_scope.dart). Moneda is
// already shared via DashboardFilterViewModel on the AppBar.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'package:pocket_pilot/src/core/theme/app_theme.dart';
import 'package:pocket_pilot/src/features/dashboard/ui/dashboard_filter_view_model.dart';
import 'package:pocket_pilot/src/features/statistics/ui/statistics_filter_view_model.dart';
import 'package:pocket_pilot/src/features/statistics/ui/widgets/time_window_chips.dart';

class StatisticsTab extends StatelessWidget {
  const StatisticsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final statsFilter = context.watch<StatisticsFilterViewModel>();

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 96),
      children: [
        Center(
          child: TimeWindowChips(
            selectedMonths: statsFilter.window,
            onChanged: statsFilter.setWindow,
          ),
        ),
        const SizedBox(height: 20),
        _HubEntry(
          icon: Icons.donut_small_outlined,
          title: 'Categorías',
          subtitle: 'Gastos e ingresos por categoría',
          onTap: () => _open(context, 'categories'),
        ),
        const SizedBox(height: 10),
        _HubEntry(
          icon: Icons.swap_vert,
          title: 'Flujo',
          subtitle: 'Ingresos vs gastos y neto del periodo',
          onTap: () => _open(context, 'cashflow'),
        ),
        const SizedBox(height: 20),
        Text(
          'Próximamente se agregarán más visualizaciones aquí.',
          style: GoogleFonts.ibmPlexSans(
            fontSize: 12,
            color: cs.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  void _open(BuildContext context, String view) {
    final window = context.read<StatisticsFilterViewModel>().window;
    final currency = context.read<DashboardFilterViewModel>().currencyCode;
    final params = <String, String>{'window': '$window'};
    if (currency != null) params['currency'] = currency;
    final qs = params.entries
        .map((e) =>
            '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}')
        .join('&');
    context.push('/dashboard/statistics/$view?$qs');
  }
}

class _HubEntry extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _HubEntry({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: AppTheme.radiusMedium,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: cs.surfaceContainer,
          borderRadius: AppTheme.radiusMedium,
          border: Border.all(color: cs.surfaceContainerHigh, width: 1),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.12),
                borderRadius: AppTheme.radiusSmall,
              ),
              child: Icon(icon, size: 20, color: cs.primary),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.ibmPlexSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: GoogleFonts.ibmPlexSans(
                      fontSize: 12,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}
