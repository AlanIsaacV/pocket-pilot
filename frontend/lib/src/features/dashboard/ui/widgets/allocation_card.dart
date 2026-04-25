import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:pocket_pilot/src/core/theme/app_colors.dart';
import 'package:pocket_pilot/src/core/theme/app_theme.dart';
import 'package:pocket_pilot/src/features/dashboard/domain/dashboard_metrics.dart';

/// Stacked horizontal bar showing the user's net-worth composition split into
/// three buckets: free liquid (`liquidAssetsCents - yieldsValueCents`), market
/// value of holdings, and yield principal. Yields are subtracted from liquid
/// because their principal already lives inside the bank/cash balance — see
/// `architecture/investments.md` §"Allocation in dashboard".
///
/// Auxiliary chips below the bar surface debt and revolving credit, which are
/// not part of the 100% stack.
///
/// Renders nothing (`SizedBox.shrink()`) when there are no positive assets.
class AllocationCard extends StatelessWidget {
  final DashboardMetrics metrics;

  const AllocationCard({super.key, required this.metrics});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final freeLiquid = (metrics.liquidAssetsCents - metrics.yieldsValueCents)
        .clamp(0, 1 << 62);
    final stocks = metrics.marketValueOfHoldingsCents;
    final yields = metrics.yieldsValueCents;
    final total = freeLiquid + stocks + yields;

    if (total <= 0) return const SizedBox.shrink();

    final segments = <_AllocationSegment>[
      _AllocationSegment(
        label: 'Líquido',
        cents: freeLiquid,
        color: cs.primary,
      ),
      _AllocationSegment(
        label: 'Stocks',
        cents: stocks,
        color: AppColors.catSapphire,
      ),
      _AllocationSegment(
        label: 'Rend',
        cents: yields,
        color: AppColors.income,
      ),
    ].where((s) => s.cents > 0).toList();

    final hasDebt = metrics.debtCents > 0;
    final hasRevolving = metrics.revolvingCreditCents > 0;
    final hasAuxiliary = hasDebt || hasRevolving;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: cs.surfaceContainer,
          borderRadius: AppTheme.radiusMedium,
          border: Border.all(color: cs.surfaceContainerHigh, width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Composición',
              style: GoogleFonts.ibmPlexSans(
                fontSize: 13,
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: AppTheme.radiusFull,
              child: SizedBox(
                height: 12,
                child: Row(
                  children: [
                    for (final seg in segments)
                      Expanded(
                        flex: ((seg.cents / total) * 1000).round(),
                        child: Container(color: seg.color),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 6,
              children: [
                for (final seg in segments)
                  _AllocationLegend(
                    label: seg.label,
                    color: seg.color,
                    cents: seg.cents,
                    currency: metrics.currencyCode,
                    percentage: seg.cents / total,
                  ),
              ],
            ),
            if (hasAuxiliary) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 16,
                runSpacing: 4,
                children: [
                  if (hasDebt)
                    _AuxiliaryStat(
                      label: 'Deuda actual',
                      cents: -metrics.debtCents,
                      currency: metrics.currencyCode,
                      tone: cs.error,
                    ),
                  if (hasRevolving)
                    _AuxiliaryStat(
                      label: 'Crédito disp.',
                      cents: metrics.revolvingCreditCents,
                      currency: metrics.currencyCode,
                      tone: cs.onSurfaceVariant,
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AllocationSegment {
  final String label;
  final int cents;
  final Color color;

  const _AllocationSegment({
    required this.label,
    required this.cents,
    required this.color,
  });
}

class _AllocationLegend extends StatelessWidget {
  final String label;
  final Color color;
  final int cents;
  final String currency;
  final double percentage;

  const _AllocationLegend({
    required this.label,
    required this.color,
    required this.cents,
    required this.currency,
    required this.percentage,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final pct = (percentage * 100).toStringAsFixed(percentage >= 0.1 ? 0 : 1);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          '$label · $pct%',
          style: GoogleFonts.ibmPlexSans(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: cs.onSurface,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          _formatAmount(cents, currency),
          style: GoogleFonts.ibmPlexSans(
            fontSize: 12,
            color: cs.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _AuxiliaryStat extends StatelessWidget {
  final String label;
  final int cents;
  final String currency;
  final Color tone;

  const _AuxiliaryStat({
    required this.label,
    required this.cents,
    required this.currency,
    required this.tone,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$label: ',
          style: GoogleFonts.ibmPlexSans(
            fontSize: 12,
            color: cs.onSurfaceVariant,
          ),
        ),
        Text(
          _formatAmount(cents, currency),
          style: GoogleFonts.ibmPlexSans(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: tone,
          ),
        ),
      ],
    );
  }
}

String _formatAmount(int cents, String currency) {
  final negative = cents < 0;
  final absCents = cents.abs();
  final whole = absCents ~/ 100;
  final frac = absCents % 100;

  final formatted = frac == 0
      ? _formatWithCommas(whole)
      : '${_formatWithCommas(whole)}.${frac.toString().padLeft(2, '0')}';

  return '${negative ? '-' : ''}$currency \$$formatted';
}

String _formatWithCommas(int value) {
  final str = value.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < str.length; i++) {
    if (i > 0 && (str.length - i) % 3 == 0) buffer.write(',');
    buffer.write(str[i]);
  }
  return buffer.toString();
}
