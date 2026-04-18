// features/statistics/ui/statistics_tab.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'package:pocket_pilot/src/features/statistics/domain/category_series_dto.dart';
import 'package:pocket_pilot/src/features/statistics/ui/statistics_view_model.dart';
import 'package:pocket_pilot/src/features/statistics/ui/widgets/category_list_row.dart';
import 'package:pocket_pilot/src/features/statistics/ui/widgets/time_window_chips.dart';

class StatisticsTab extends StatelessWidget {
  const StatisticsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Consumer<StatisticsViewModel>(
      builder: (context, vm, _) {
        if (vm.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }
        if (vm.errorMessage != null) {
          return _ErrorState(
            message: vm.errorMessage!,
            onRetry: vm.refresh,
          );
        }

        final expense = vm.series.where((s) => s.kind == 'expense').toList();
        final income = vm.series.where((s) => s.kind == 'income').toList();

        return RefreshIndicator(
          onRefresh: vm.refresh,
          child: CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 96),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    Center(
                      child: TimeWindowChips(
                        selectedMonths: vm.months,
                        onChanged: vm.setWindow,
                      ),
                    ),
                    const SizedBox(height: 20),
                    if (vm.series.isEmpty)
                      _EmptyState(cs: cs)
                    else ...[
                      if (expense.isNotEmpty) ...[
                        _SectionHeader(title: 'Gastos'),
                        const SizedBox(height: 12),
                        ...expense.map(
                          (s) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: CategoryListRow(
                              item: s,
                              windowMonths: vm.months,
                              onTap: () => _openDetail(context, s),
                            ),
                          ),
                        ),
                      ],
                      if (income.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        _SectionHeader(title: 'Ingresos'),
                        const SizedBox(height: 12),
                        ...income.map(
                          (s) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: CategoryListRow(
                              item: s,
                              windowMonths: vm.months,
                              onTap: () => _openDetail(context, s),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ]),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _openDetail(BuildContext context, CategorySeriesDTO item) {
    context.push(
      '/dashboard/statistics/category/${item.categoryId}'
      '?currency=${Uri.encodeQueryComponent(item.currencyCode)}',
      extra: item,
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: GoogleFonts.ibmPlexSans(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: Theme.of(context).colorScheme.onSurface,
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final ColorScheme cs;
  const _EmptyState({required this.cs});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          Icon(Icons.query_stats, size: 40, color: cs.onSurfaceVariant),
          const SizedBox(height: 12),
          Text(
            'Aún no hay suficiente historial',
            style: GoogleFonts.ibmPlexSans(
              fontSize: 14,
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => context.go('/transactions'),
            child: const Text('Ver transacciones'),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final Future<void> Function() onRetry;
  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 40, color: cs.error),
            const SizedBox(height: 12),
            Text(
              'No se pudieron cargar las estadísticas',
              style: GoogleFonts.ibmPlexSans(
                fontSize: 14,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              message,
              style: GoogleFonts.ibmPlexSans(
                fontSize: 12,
                color: cs.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => onRetry(),
              child: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }
}
