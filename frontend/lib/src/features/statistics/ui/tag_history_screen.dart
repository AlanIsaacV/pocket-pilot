// features/statistics/ui/tag_history_screen.dart
//
// Drill-down de un solo tag. Mismo patrón que category_history_screen:
// escucha DashboardFilterViewModel (rango/moneda/cuentas), recarga al
// cambiar, body con StatDeltaRow + barra mensual + breakdown por
// categoría dentro del tag. DashboardFilterSheet flotante.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'package:pocket_pilot/src/core/theme/app_colors.dart';
import 'package:pocket_pilot/src/core/theme/app_theme.dart';
import 'package:pocket_pilot/src/features/statistics/data/statistics_repository.dart';
import 'package:pocket_pilot/src/features/statistics/domain/tag_category_slice_dto.dart';
import 'package:pocket_pilot/src/features/statistics/domain/tag_history_dto.dart';
import 'package:pocket_pilot/src/features/statistics/ui/widgets/category_monthly_bar_chart.dart';
import 'package:pocket_pilot/src/features/statistics/ui/widgets/stat_delta_row.dart';
import 'package:pocket_pilot/src/ui/widgets/dashboard_filter_sheet.dart';
import 'package:pocket_pilot/src/ui/widgets/dashboard_filter_view_model.dart';

class TagHistoryScreen extends StatefulWidget {
  final String tagName;
  final String? initialCurrencyCode;

  const TagHistoryScreen({
    super.key,
    required this.tagName,
    this.initialCurrencyCode,
  });

  @override
  State<TagHistoryScreen> createState() => _TagHistoryScreenState();
}

class _TagHistoryScreenState extends State<TagHistoryScreen> {
  int? _selectedBarIndex;
  TagHistoryDTO? _history;
  bool _loading = true;
  String? _error;

  DashboardFilterViewModel? _filterVM;
  String? _lastFrom;
  String? _lastTo;
  String? _lastCurrency;
  Set<String> _lastAccountIds = const {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final vm = context.read<DashboardFilterViewModel>();
    if (!identical(vm, _filterVM)) {
      _filterVM?.removeListener(_onFilterChanged);
      _filterVM = vm;
      _filterVM!.addListener(_onFilterChanged);
    }
  }

  @override
  void dispose() {
    _filterVM?.removeListener(_onFilterChanged);
    super.dispose();
  }

  void _onFilterChanged() {
    final vm = _filterVM!;
    final (from, to) = vm.resolvedDateRange;
    final currency = vm.currencyCode;
    final accountIds = vm.accountIds;
    if (from == _lastFrom &&
        to == _lastTo &&
        currency == _lastCurrency &&
        _setEquals(accountIds, _lastAccountIds)) {
      return;
    }
    _load();
  }

  static bool _setEquals(Set<String> a, Set<String> b) {
    if (a.length != b.length) return false;
    for (final item in a) {
      if (!b.contains(item)) return false;
    }
    return true;
  }

  Future<void> _load() async {
    final repo = context.read<StatisticsRepository>();
    final vm = context.read<DashboardFilterViewModel>();
    final (from, to) = vm.resolvedDateRange;
    final accountIds = vm.accountIds.isNotEmpty ? vm.accountIds : null;
    final currency = widget.initialCurrencyCode ?? vm.currencyCode;
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
      final data = await repo.getTagHistory(
        tagName: widget.tagName,
        currencyCode: currency,
        from: from,
        to: to,
        accountIds: accountIds,
      );
      if (!mounted) return;
      setState(() {
        _history = data;
        _selectedBarIndex = data.points.length - 1;
        _loading = false;
        _lastFrom = from;
        _lastTo = to;
        _lastCurrency = currency;
        _lastAccountIds = Set.of(vm.accountIds);
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
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.tagName),
      ),
      body: Stack(
        children: [
          _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? _Error(message: _error!, onRetry: _load)
                  : _Body(
                      history: _history!,
                      selectedBarIndex: _selectedBarIndex,
                      onBarTap: (i) => setState(() => _selectedBarIndex = i),
                    ),
          const DashboardFilterSheet(),
        ],
      ),
    );
  }
}

class _Body extends StatelessWidget {
  final TagHistoryDTO history;
  final int? selectedBarIndex;
  final ValueChanged<int> onBarTap;

  const _Body({
    required this.history,
    required this.selectedBarIndex,
    required this.onBarTap,
  });

  @override
  Widget build(BuildContext context) {
    final currentCents =
        history.points.isEmpty ? 0 : history.points.last.amountCents;
    final currentYm =
        history.points.isEmpty ? '' : history.points.last.yearMonth;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 160),
      children: [
        StatDeltaRow(
          currency: history.currencyCode,
          avgCents: history.avgMonthlyCents,
          currentCents: currentCents,
          kind: 'expense',
        ),
        const SizedBox(height: 16),
        CategoryMonthlyBarChart(
          points: history.points,
          currentYm: currentYm,
          selectedIndex: selectedBarIndex,
          onBarTap: onBarTap,
        ),
        const SizedBox(height: 20),
        _TagTotalCard(
          totalCents: history.totalCents,
          currencyCode: history.currencyCode,
        ),
        const SizedBox(height: 16),
        _TagCategoryBreakdown(
          slices: history.categoryBreakdown,
          currencyCode: history.currencyCode,
        ),
      ],
    );
  }
}

class _TagTotalCard extends StatelessWidget {
  final int totalCents;
  final String currencyCode;

  const _TagTotalCard({
    required this.totalCents,
    required this.currencyCode,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        borderRadius: AppTheme.radiusMedium,
        border: Border.all(color: cs.surfaceContainerHigh, width: 1),
      ),
      child: Row(
        children: [
          Text(
            'Total en el periodo',
            style: GoogleFonts.ibmPlexSans(
              fontSize: 12,
              color: cs.onSurfaceVariant,
            ),
          ),
          const Spacer(),
          Text(
            _fmt(totalCents, currencyCode),
            style: GoogleFonts.ibmPlexSans(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: cs.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

class _TagCategoryBreakdown extends StatelessWidget {
  final List<TagCategorySliceDTO> slices;
  final String currencyCode;

  const _TagCategoryBreakdown({
    required this.slices,
    required this.currencyCode,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final palette = AppColors.categoryPresets;

    final positive = slices.where((s) => s.amountCents > 0).toList()
      ..sort((a, b) => b.amountCents.compareTo(a.amountCents));

    if (positive.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: cs.surfaceContainer,
          borderRadius: AppTheme.radiusMedium,
          border: Border.all(color: cs.surfaceContainerHigh, width: 1),
        ),
        child: Center(
          child: Text(
            'Sin gastos en este tag para el periodo',
            style: GoogleFonts.ibmPlexSans(
              fontSize: 13,
              color: cs.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    final total = positive.fold(0, (s, c) => s + c.amountCents);
    Color colorFor(TagCategorySliceDTO s) {
      if (s.categoryColor.isNotEmpty) {
        final parsed = _tryParseHex(s.categoryColor);
        if (parsed != null) return parsed;
      }
      return palette[s.categoryId.hashCode.abs() % palette.length];
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        borderRadius: AppTheme.radiusMedium,
        border: Border.all(color: cs.surfaceContainerHigh, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Por categoría',
            style: GoogleFonts.ibmPlexSans(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: AppTheme.radiusFull,
            child: SizedBox(
              height: 8,
              child: Row(
                children: positive.map((s) {
                  final fraction = total > 0 ? s.amountCents / total : 0.0;
                  return Expanded(
                    flex: (fraction * 1000).round().clamp(1, 1000),
                    child: Container(color: colorFor(s)),
                  );
                }).toList(),
              ),
            ),
          ),
          const SizedBox(height: 16),
          ...positive.map((s) {
            final pct =
                total > 0 ? (s.amountCents / total * 100).round() : 0;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: colorFor(s),
                      borderRadius:
                          const BorderRadius.all(Radius.circular(3)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      s.categoryName,
                      style: GoogleFonts.ibmPlexSans(
                        fontSize: 13,
                        color: cs.onSurface,
                      ),
                    ),
                  ),
                  Text(
                    _fmt(s.amountCents, currencyCode),
                    style: GoogleFonts.ibmPlexSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface,
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 36,
                    child: Text(
                      '$pct%',
                      textAlign: TextAlign.right,
                      style: GoogleFonts.ibmPlexSans(
                        fontSize: 12,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  static Color? _tryParseHex(String hex) {
    final cleaned = hex.replaceAll('#', '').trim();
    if (cleaned.length != 6 && cleaned.length != 8) return null;
    final value = int.tryParse(cleaned, radix: 16);
    if (value == null) return null;
    return Color(cleaned.length == 6 ? 0xFF000000 | value : value);
  }
}

String _fmt(int cents, String currency) {
  final sign = cents < 0 ? '-' : '';
  final abs = cents.abs();
  final whole = abs ~/ 100;
  final frac = abs % 100;
  final buf = StringBuffer();
  final s = whole.toString();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
    buf.write(s[i]);
  }
  final fracStr = frac == 0 ? '' : '.${frac.toString().padLeft(2, '0')}';
  return '$sign$currency \$${buf.toString()}$fracStr';
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
