// features/cashflow/ui/cashflow_tab.dart
//
// Vista full-screen de Cashflow. Lee el window (meses) desde
// DashboardFilterViewModel.monthsWindow, compartido con el resto de
// Dashboard/Stats.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'package:pocket_pilot/src/core/constants/nature_labels.dart';
import 'package:pocket_pilot/src/core/theme/app_theme.dart';
import 'package:pocket_pilot/src/features/cashflow/domain/cashflow_snapshot.dart';
import 'package:pocket_pilot/src/features/cashflow/ui/cashflow_view_model.dart';
import 'package:pocket_pilot/src/features/cashflow/ui/widgets/cashflow_summary_cards.dart';
import 'package:pocket_pilot/src/features/cashflow/ui/widgets/cashflow_waterfall_chart.dart';
import 'package:pocket_pilot/src/features/dashboard/ui/widgets/dashboard_filter_sheet.dart';

class CashflowTab extends StatelessWidget {
  const CashflowTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Flujo')),
      body: const _Body(),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Consumer<CashflowViewModel>(
          builder: (context, vm, _) {
            if (vm.isLoading && vm.snapshot == null) {
              return const Center(child: CircularProgressIndicator());
            }
            if (vm.errorMessage != null) {
              return _ErrorState(
                  message: vm.errorMessage!, onRetry: vm.refresh);
            }
            final snap = vm.snapshot;
            if (snap == null) {
              return _EmptyCurrency();
            }

            return RefreshIndicator(
              onRefresh: vm.refresh,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 160),
                children: [
                  CashflowSummaryCards(
                    currencyCode: snap.currencyCode,
                    totalInCents: snap.totalInCents,
                    totalOutCents: snap.totalOutCents,
                    netCents: snap.netCents,
                  ),
                  const SizedBox(height: 20),
                  _ModeToggle(
                    mode: vm.mode,
                    onChanged: vm.setMode,
                  ),
                  const SizedBox(height: 16),
                  if (snap.isEmpty)
                    _EmptyPeriod()
                  else ...[
                    CashflowWaterfallChart(
                      entries: snap.entriesFor(vm.mode),
                      mode: vm.mode,
                      totalInCents: snap.totalInCents,
                      totalOutCents: snap.totalOutCents,
                      netCents: snap.netCents,
                    ),
                    const SizedBox(height: 20),
                    _BreakdownList(
                      entries: snap.entriesFor(vm.mode),
                      mode: vm.mode,
                      currencyCode: snap.currencyCode,
                      totalInCents: snap.totalInCents,
                      totalOutCents: snap.totalOutCents,
                    ),
                  ],
                ],
              ),
            );
          },
        ),
        const DashboardFilterSheet(),
      ],
    );
  }
}

class _ModeToggle extends StatelessWidget {
  final BreakdownMode mode;
  final ValueChanged<BreakdownMode> onChanged;

  const _ModeToggle({required this.mode, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SegmentedButton<BreakdownMode>(
        showSelectedIcon: false,
        segments: const [
          ButtonSegment(
            value: BreakdownMode.category,
            label: Text('Categoría'),
          ),
          ButtonSegment(
            value: BreakdownMode.nature,
            label: Text('Naturaleza'),
          ),
        ],
        selected: {mode},
        onSelectionChanged: (s) => onChanged(s.first),
      ),
    );
  }
}

class _BreakdownList extends StatelessWidget {
  final List<CashflowBreakdownEntry> entries;
  final BreakdownMode mode;
  final String currencyCode;
  final int totalInCents;
  final int totalOutCents;

  const _BreakdownList({
    required this.entries,
    required this.mode,
    required this.currencyCode,
    required this.totalInCents,
    required this.totalOutCents,
  });

  @override
  Widget build(BuildContext context) {
    final income = entries.where((e) => e.kind == 'income').toList();
    final expense = entries.where((e) => e.kind == 'expense').toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (income.isNotEmpty) ...[
          _SectionHeader(title: 'Ingresos'),
          const SizedBox(height: 10),
          ...income.map((e) => _BreakdownRow(
                entry: e,
                mode: mode,
                currencyCode: currencyCode,
                totalKindCents: totalInCents,
              )),
          const SizedBox(height: 16),
        ],
        if (expense.isNotEmpty) ...[
          _SectionHeader(title: 'Gastos'),
          const SizedBox(height: 10),
          ...expense.map((e) => _BreakdownRow(
                entry: e,
                mode: mode,
                currencyCode: currencyCode,
                totalKindCents: totalOutCents,
              )),
        ],
      ],
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

class _BreakdownRow extends StatelessWidget {
  final CashflowBreakdownEntry entry;
  final BreakdownMode mode;
  final String currencyCode;
  final int totalKindCents;

  const _BreakdownRow({
    required this.entry,
    required this.mode,
    required this.currencyCode,
    required this.totalKindCents,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = entry.color ??
        (entry.kind == 'income' ? cs.primary : cs.error);
    final pct = totalKindCents > 0
        ? (entry.amountCents / totalKindCents * 100).round()
        : 0;
    final label = mode == BreakdownMode.nature
        ? natureDisplayLabel(entry.label)
        : entry.label;
    final sign = entry.kind == 'income' ? '+' : '-';

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: cs.surfaceContainer,
          borderRadius: AppTheme.radiusMedium,
          border: Border.all(color: cs.surfaceContainerHigh, width: 1),
        ),
        child: Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: color,
                borderRadius: const BorderRadius.all(Radius.circular(3)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: GoogleFonts.ibmPlexSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: cs.onSurface,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              '$pct%',
              style: GoogleFonts.ibmPlexSans(
                fontSize: 11,
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              '$sign${_fmt(entry.amountCents, currencyCode)}',
              style: GoogleFonts.ibmPlexSans(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _fmt(int cents, String currency) {
    final whole = cents ~/ 100;
    final frac = cents % 100;
    final buf = StringBuffer();
    final s = whole.toString();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    final fracStr = frac == 0 ? '' : '.${frac.toString().padLeft(2, '0')}';
    return '$currency \$${buf.toString()}$fracStr';
  }
}

class _EmptyCurrency extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.currency_exchange, size: 40, color: cs.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(
              'Selecciona una moneda para ver el flujo',
              style: GoogleFonts.ibmPlexSans(
                fontSize: 14,
                color: cs.onSurface,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyPeriod extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          Icon(Icons.trending_flat, size: 40, color: cs.onSurfaceVariant),
          const SizedBox(height: 12),
          Text(
            'Sin movimientos en este periodo',
            style: GoogleFonts.ibmPlexSans(
              fontSize: 14,
              color: cs.onSurfaceVariant,
            ),
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
              'No se pudo calcular el flujo',
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
