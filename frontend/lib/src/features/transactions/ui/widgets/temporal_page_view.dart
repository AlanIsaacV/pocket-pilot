// frontend/lib/src/features/transactions/ui/widgets/temporal_page_view.dart

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'package:pocket_pilot/src/core/theme/app_theme.dart';
import 'package:pocket_pilot/src/features/transactions/ui/transaction_filter_view_model.dart';

class TemporalPageView extends StatefulWidget {
  const TemporalPageView({super.key});

  @override
  State<TemporalPageView> createState() => _TemporalPageViewState();
}

class _TemporalPageViewState extends State<TemporalPageView> {
  late PageController _pageController;

  @override
  void initState() {
    super.initState();
    final vm = context.read<TransactionFilterViewModel>();
    _pageController = PageController(initialPage: vm.activePageIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<TransactionFilterViewModel>();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 40,
          child: PageView(
            controller: _pageController,
            onPageChanged: (i) => vm.setActivePageIndex(i),
            children: [
              _QuickPage(vm: vm),
              _PeriodPage(vm: vm),
              _CustomPage(vm: vm),
            ],
          ),
        ),
        const SizedBox(height: 8),
        _DotsIndicator(
          count: 3,
          activeIndex: vm.activePageIndex,
        ),
      ],
    );
  }
}

// ----------------------------------------------------------
// Page 1: Quick (7D, 30D, 6M, 1Y)
// ----------------------------------------------------------

class _QuickPage extends StatelessWidget {
  final TransactionFilterViewModel vm;
  const _QuickPage({required this.vm});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: QuickRange.values.map((range) {
        final isSelected = vm.quickSelection == range &&
            vm.activePageIndex == 0;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: _FilterChip(
            label: _label(range),
            isSelected: isSelected,
            onTap: () => vm.setQuickSelection(range),
          ),
        );
      }).toList(),
    );
  }

  String _label(QuickRange r) => switch (r) {
        QuickRange.d7 => '7D',
        QuickRange.d30 => '30D',
        QuickRange.m6 => '6M',
        QuickRange.y1 => '1Y',
      };
}

// ----------------------------------------------------------
// Page 2: Period (← [dropdown] →)
// ----------------------------------------------------------

class _PeriodPage extends StatelessWidget {
  final TransactionFilterViewModel vm;
  const _PeriodPage({required this.vm});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left_rounded),
          iconSize: 22,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          onPressed: () => vm.navigatePeriod(-1),
        ),
        GestureDetector(
          onTap: () => _showGranularityPicker(context),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: vm.activePageIndex == 1
                  ? cs.primary.withValues(alpha: 0.15)
                  : cs.surfaceContainerHigh,
              borderRadius: AppTheme.radiusSmall,
              border: vm.activePageIndex == 1
                  ? Border.all(color: cs.primary.withValues(alpha: 0.4))
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  vm.periodLabel,
                  style: GoogleFonts.ibmPlexSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.arrow_drop_down_rounded,
                  size: 18,
                  color: cs.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.chevron_right_rounded),
          iconSize: 22,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          onPressed: vm.isAtCurrentPeriod
              ? null
              : () => vm.navigatePeriod(1),
        ),
      ],
    );
  }

  void _showGranularityPicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: PeriodGranularity.values.map((g) {
            final label = switch (g) {
              PeriodGranularity.week => 'Week',
              PeriodGranularity.month => 'Month',
              PeriodGranularity.year => 'Year',
            };
            return ListTile(
              title: Text(label),
              trailing: vm.periodGranularity == g
                  ? Icon(Icons.check_rounded,
                      color: Theme.of(context).colorScheme.primary)
                  : null,
              onTap: () {
                vm.setPeriodGranularity(g);
                Navigator.of(context).pop();
              },
            );
          }).toList(),
        ),
      ),
    );
  }
}

// ----------------------------------------------------------
// Page 3: Custom (date — date)
// ----------------------------------------------------------

class _CustomPage extends StatelessWidget {
  final TransactionFilterViewModel vm;
  const _CustomPage({required this.vm});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _DateButton(
          date: vm.customFrom,
          cs: cs,
          onTap: () => _pickDate(context, isFrom: true),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text('—',
              style: GoogleFonts.ibmPlexSans(
                  color: cs.onSurfaceVariant, fontSize: 14)),
        ),
        _DateButton(
          date: vm.customTo,
          cs: cs,
          onTap: () => _pickDate(context, isFrom: false),
        ),
      ],
    );
  }

  Future<void> _pickDate(BuildContext context, {required bool isFrom}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isFrom ? vm.customFrom : vm.customTo,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      if (isFrom) {
        vm.setCustomRange(picked, vm.customTo);
      } else {
        vm.setCustomRange(vm.customFrom, picked);
      }
    }
  }
}

class _DateButton extends StatelessWidget {
  final DateTime date;
  final ColorScheme cs;
  final VoidCallback onTap;
  const _DateButton({required this.date, required this.cs, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final label =
        '${_monthAbbr(date.month)} ${date.day}, ${date.year}';
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHigh,
          borderRadius: AppTheme.radiusSmall,
          border: Border.all(color: cs.outline),
        ),
        child: Text(
          label,
          style: GoogleFonts.ibmPlexSans(fontSize: 13, color: cs.onSurface),
        ),
      ),
    );
  }

  static String _monthAbbr(int m) {
    const abbrs = [
      'Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun',
      'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic',
    ];
    return abbrs[m - 1];
  }
}

// ----------------------------------------------------------
// Shared widgets
// ----------------------------------------------------------

class _FilterChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  const _FilterChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? cs.primary.withValues(alpha: 0.15)
              : cs.surfaceContainerHigh,
          borderRadius: AppTheme.radiusFull,
          border: isSelected
              ? Border.all(color: cs.primary.withValues(alpha: 0.5))
              : null,
        ),
        child: Text(
          label,
          style: GoogleFonts.ibmPlexSans(
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
            color: isSelected ? cs.primary : cs.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _DotsIndicator extends StatelessWidget {
  final int count;
  final int activeIndex;
  const _DotsIndicator({required this.count, required this.activeIndex});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (i) {
        return Container(
          width: 6,
          height: 6,
          margin: const EdgeInsets.symmetric(horizontal: 3),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: i == activeIndex
                ? cs.primary
                : cs.onSurfaceVariant.withValues(alpha: 0.3),
          ),
        );
      }),
    );
  }
}
