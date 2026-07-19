import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:pocket_pilot/src/core/theme/app_theme.dart';
import 'package:pocket_pilot/src/ui/widgets/form_date_utils.dart';

// ----------------------------------------------------------
// Enums
// ----------------------------------------------------------

enum QuickRange { d7, d30, m6, y1 }

enum PeriodGranularity { week, month, year }

// ----------------------------------------------------------
// Filter-state interface
// ----------------------------------------------------------

/// Minimal interface exposing the temporal-filter fields/callbacks that
/// [TemporalPageView] needs from its host view model.
///
/// Both `TransactionFilterViewModel` and `DashboardFilterViewModel` implement
/// this (they're already `ChangeNotifier`s, which satisfies [Listenable]); the
/// widget rebuilds via an internal [ListenableBuilder] instead of a provider
/// lookup.
abstract interface class TemporalFilterState implements Listenable {
  int get activePageIndex;
  QuickRange get quickSelection;
  PeriodGranularity get periodGranularity;
  String get periodLabel;
  DateTime get customFrom;
  DateTime get customTo;

  void setActivePageIndex(int index);
  void setQuickSelection(QuickRange range);
  void setPeriodGranularity(PeriodGranularity g);
  void navigatePeriod(int delta);
  void setCustomRange(DateTime from, DateTime to);
}

class TemporalPageView extends StatefulWidget {
  final TemporalFilterState state;
  const TemporalPageView({super.key, required this.state});

  @override
  State<TemporalPageView> createState() => _TemporalPageViewState();
}

class _TemporalPageViewState extends State<TemporalPageView> {
  late PageController _pageController;

  @override
  void initState() {
    super.initState();
    _pageController =
        PageController(initialPage: widget.state.activePageIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.state,
      builder: (context, _) {
        final state = widget.state;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 40,
              child: PageView(
                controller: _pageController,
                onPageChanged: (i) => state.setActivePageIndex(i),
                children: [
                  _QuickPage(state: state),
                  _PeriodPage(state: state),
                  _CustomPage(state: state),
                ],
              ),
            ),
            const SizedBox(height: 8),
            _DotsIndicator(
              count: 3,
              activeIndex: state.activePageIndex,
            ),
          ],
        );
      },
    );
  }
}

// ----------------------------------------------------------
// Page 1: Quick (7D, 30D, 6M, 1Y)
// ----------------------------------------------------------

class _QuickPage extends StatelessWidget {
  final TemporalFilterState state;
  const _QuickPage({required this.state});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: QuickRange.values.map((range) {
        final isSelected =
            state.quickSelection == range && state.activePageIndex == 0;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: _FilterChip(
            label: _label(range),
            isSelected: isSelected,
            onTap: () => state.setQuickSelection(range),
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
  final TemporalFilterState state;
  const _PeriodPage({required this.state});

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
          onPressed: () => state.navigatePeriod(-1),
        ),
        GestureDetector(
          onTap: () => _showGranularityPicker(context),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: state.activePageIndex == 1
                  ? cs.primary.withValues(alpha: 0.15)
                  : cs.surfaceContainerHigh,
              borderRadius: AppTheme.radiusSmall,
              border: state.activePageIndex == 1
                  ? Border.all(color: cs.primary.withValues(alpha: 0.4))
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  state.periodLabel,
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
          onPressed: () => state.navigatePeriod(1),
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
              PeriodGranularity.week => 'Semana',
              PeriodGranularity.month => 'Mes',
              PeriodGranularity.year => 'Año',
            };
            return ListTile(
              title: Text(label),
              trailing: state.periodGranularity == g
                  ? Icon(Icons.check_rounded,
                      color: Theme.of(context).colorScheme.primary)
                  : null,
              onTap: () {
                state.setPeriodGranularity(g);
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
  final TemporalFilterState state;
  const _CustomPage({required this.state});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _DateButton(
          date: state.customFrom,
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
          date: state.customTo,
          cs: cs,
          onTap: () => _pickDate(context, isFrom: false),
        ),
      ],
    );
  }

  Future<void> _pickDate(BuildContext context, {required bool isFrom}) async {
    final now = DateTime.now();
    final picked = await pickDate(
      context,
      isFrom ? state.customFrom : state.customTo,
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year + 5, now.month, now.day),
    );
    if (picked != null) {
      if (isFrom) {
        state.setCustomRange(picked, state.customTo);
      } else {
        state.setCustomRange(state.customFrom, picked);
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
    final label = '${_monthAbbr(date.month)} ${date.day}, ${date.year}';
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
