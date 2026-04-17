// features/statistics/ui/category_history_screen.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'package:pocket_pilot/src/core/theme/app_theme.dart';
import 'package:pocket_pilot/src/features/budgets/domain/budget_status.dart';
import 'package:pocket_pilot/src/features/dashboard/ui/dashboard_filter_view_model.dart';
import 'package:pocket_pilot/src/features/statistics/data/statistics_repository.dart';
import 'package:pocket_pilot/src/features/statistics/domain/category_history_dto.dart';
import 'package:pocket_pilot/src/features/statistics/domain/category_series_dto.dart';
import 'package:pocket_pilot/src/features/statistics/ui/widgets/category_monthly_bar_chart.dart';
import 'package:pocket_pilot/src/features/statistics/ui/widgets/stat_delta_row.dart';
import 'package:pocket_pilot/src/features/statistics/ui/widgets/time_window_chips.dart';

class CategoryHistoryScreen extends StatefulWidget {
  final String categoryId;
  final CategorySeriesDTO? initialSummary;

  const CategoryHistoryScreen({
    super.key,
    required this.categoryId,
    this.initialSummary,
  });

  @override
  State<CategoryHistoryScreen> createState() => _CategoryHistoryScreenState();
}

class _CategoryHistoryScreenState extends State<CategoryHistoryScreen> {
  int _months = 6;
  int? _selectedBarIndex;
  CategoryHistoryDTO? _history;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final repo = context.read<StatisticsRepository>();
    final filter = context.read<DashboardFilterViewModel>();
    final currency = filter.currencyCode;
    if (currency == null) {
      setState(() {
        _loading = false;
        _error = 'Selecciona una moneda primero';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await repo.getHistory(
        categoryId: widget.categoryId,
        currencyCode: currency,
        months: _months,
        now: DateTime.now(),
      );
      if (!mounted) return;
      setState(() {
        _history = data;
        _selectedBarIndex = data.points.length - 1;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final summary = _history?.summary ?? widget.initialSummary;

    return Scaffold(
      appBar: AppBar(
        title: Text(summary?.name ?? ''),
        actions: [
          IconButton(
            icon: const Icon(Icons.list_alt),
            tooltip: 'Ver transacciones',
            onPressed: () => context.go(
              '/transactions',
              extra: {'categoryId': widget.categoryId},
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _Error(message: _error!, onRetry: _load)
              : _Body(
                  history: _history!,
                  months: _months,
                  selectedBarIndex: _selectedBarIndex,
                  onWindowChanged: (m) {
                    setState(() => _months = m);
                    _load();
                  },
                  onBarTap: (i) => setState(() => _selectedBarIndex = i),
                ),
    );
  }
}

class _Body extends StatelessWidget {
  final CategoryHistoryDTO history;
  final int months;
  final int? selectedBarIndex;
  final ValueChanged<int> onWindowChanged;
  final ValueChanged<int> onBarTap;

  const _Body({
    required this.history,
    required this.months,
    required this.selectedBarIndex,
    required this.onWindowChanged,
    required this.onBarTap,
  });

  @override
  Widget build(BuildContext context) {
    final s = history.summary;
    final current = history.points.isEmpty
        ? 0
        : history.points.last.amountCents;
    final currentYm = history.points.isEmpty
        ? ''
        : history.points.last.yearMonth;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 96),
      children: [
        Center(
          child: TimeWindowChips(
            selectedMonths: months,
            onChanged: onWindowChanged,
          ),
        ),
        const SizedBox(height: 16),
        StatDeltaRow(
          currency: s.currencyCode,
          avgCents: s.avgMonthlyCents,
          currentCents: current,
          kind: s.kind,
        ),
        const SizedBox(height: 16),
        CategoryMonthlyBarChart(
          points: history.points,
          currentYm: currentYm,
          budgetLimitCents: history.budget?.budget.period == 'MONTHLY'
              ? history.budget!.budget.limitAmountCents
              : null,
          selectedIndex: selectedBarIndex,
          onBarTap: onBarTap,
        ),
        const SizedBox(height: 20),
        _BudgetCard(
          status: history.budget,
          fallbackSuggestionCents: s.avgMonthlyCents,
          categoryId: s.categoryId,
          currency: s.currencyCode,
        ),
      ],
    );
  }
}

class _BudgetCard extends StatelessWidget {
  final BudgetStatus? status;
  final int fallbackSuggestionCents;
  final String categoryId;
  final String currency;

  const _BudgetCard({
    required this.status,
    required this.fallbackSuggestionCents,
    required this.categoryId,
    required this.currency,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (status == null) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: AppTheme.radiusMedium,
          border: Border.all(color: cs.surfaceContainerHigh),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Crea un presupuesto basado en tu promedio',
              style: GoogleFonts.ibmPlexSans(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: () => context.push(
                '/accounts/budgets/new'
                '?categoryId=$categoryId'
                '&suggested=$fallbackSuggestionCents'
                '&currency=$currency',
              ),
              child: const Text('Crear presupuesto'),
            ),
          ],
        ),
      );
    }

    final pct = status!.progressPercentage.clamp(0, 100).toDouble();
    final isOver = status!.spentAmountCents > status!.budget.limitAmountCents;
    final isMonthly = status!.budget.period == 'MONTHLY';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        borderRadius: AppTheme.radiusMedium,
        border: Border.all(color: cs.surfaceContainerHigh),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isMonthly
                ? 'Presupuesto mensual'
                : 'Presupuesto anual — línea no mostrada',
            style: GoogleFonts.ibmPlexSans(
              fontSize: 12,
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: pct / 100,
            color: isOver ? cs.error : cs.primary,
            backgroundColor: cs.surfaceContainerHigh,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                '${pct.round()}%',
                style: GoogleFonts.ibmPlexSans(
                  fontSize: 13,
                  color: cs.onSurface,
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: () => context.push(
                  '/accounts/budgets/${status!.budget.id}/edit',
                  extra: status!.budget,
                ),
                child: const Text('Editar'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Error extends StatelessWidget {
  final String message;
  final Future<void> Function() onRetry;
  const _Error({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message),
            const SizedBox(height: 12),
            FilledButton(onPressed: onRetry, child: const Text('Reintentar')),
          ],
        ),
      ),
    );
  }
}
