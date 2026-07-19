// features/statistics/ui/statistics_tab.dart
//
// Hub de visualizaciones de estadísticas. Cada entrada navega a su pantalla.
// Comparte el DashboardFilterViewModel con el resto del Dashboard a través
// del DashboardRouteScope, por lo que el filtro temporal/moneda/cuentas
// persiste al navegar entre pestañas y subpantallas.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:pocket_pilot/src/core/theme/app_theme.dart';
import 'package:pocket_pilot/src/ui/widgets/dashboard_filter_sheet.dart';

class StatisticsTab extends StatelessWidget {
  const StatisticsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Stack(
      children: [
        ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 160),
          children: [
            _HubEntry(
              icon: Icons.donut_small_outlined,
              title: 'Categorías',
              subtitle: 'Gastos e ingresos por categoría',
              onTap: () => context.push('/dashboard/statistics/categories'),
            ),
            const SizedBox(height: 10),
            _HubEntry(
              icon: Icons.swap_vert,
              title: 'Flujo',
              subtitle: 'Ingresos vs gastos y neto del periodo',
              onTap: () => context.push('/dashboard/statistics/cashflow'),
            ),
            const SizedBox(height: 10),
            _HubEntry(
              icon: Icons.label_outlined,
              title: 'Etiquetas',
              subtitle: 'Cuánto y en qué gastas por etiqueta',
              onTap: () => context.push('/dashboard/statistics/tags'),
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
        ),
        const DashboardFilterSheet(),
      ],
    );
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
