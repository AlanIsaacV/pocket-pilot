// features/investments/ui/widgets/portfolio_pie_chart.dart
//
// Renders the portfolio distribution as one PieChart per currency. Slices are
// ordered desc by market value; the legend below the pie is the primary source
// of textual info (symbol + percentage) — arc labels are intentionally empty
// to avoid collision when a user holds many small positions.

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:pocket_pilot/src/core/theme/app_colors.dart';
import 'package:pocket_pilot/src/features/investments/domain/portfolio_distribution.dart';

class PortfolioPieChart extends StatelessWidget {
  final Map<String, List<PortfolioSlice>> distribution;

  const PortfolioPieChart({super.key, required this.distribution});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (distribution.isEmpty) {
      return SizedBox(
        height: 180,
        child: Center(
          child: Text(
            'Sin datos para graficar',
            style: GoogleFonts.ibmPlexSans(
              fontSize: 13,
              color: cs.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    final currencies = distribution.keys.toList()..sort();

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      itemCount: currencies.length,
      separatorBuilder: (_, _) =>
          Divider(height: 32, color: cs.outlineVariant),
      itemBuilder: (context, index) {
        final currency = currencies[index];
        final slices = distribution[currency]!;
        return _CurrencyGroup(currency: currency, slices: slices);
      },
    );
  }
}

class _CurrencyGroup extends StatelessWidget {
  final String currency;
  final List<PortfolioSlice> slices;

  const _CurrencyGroup({required this.currency, required this.slices});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final total = slices.fold<double>(0, (a, s) => a + s.marketValue);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              'Portafolio $currency',
              style: GoogleFonts.ibmPlexSans(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
            ),
            const Spacer(),
            Text(
              '${slices.length} · \$${_formatMoney(total)}',
              style: GoogleFonts.ibmPlexSans(
                fontSize: 12,
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 220,
          child: PieChart(
            PieChartData(
              sectionsSpace: 2,
              centerSpaceRadius: 48,
              startDegreeOffset: -90,
              sections: [
                for (final s in slices)
                  PieChartSectionData(
                    value: s.marketValue,
                    title: '',
                    radius: 54,
                    color: _colorFor(s.holdingId),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            for (final s in slices) _LegendChip(slice: s, color: _colorFor(s.holdingId)),
          ],
        ),
      ],
    );
  }
}

class _LegendChip extends StatelessWidget {
  final PortfolioSlice slice;
  final Color color;

  const _LegendChip({required this.slice, required this.color});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final pct = (slice.percentage * 100).toStringAsFixed(1);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text(
            '${slice.symbol} · $pct%',
            style: GoogleFonts.ibmPlexSans(
              fontSize: 12,
              color: cs.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

Color _colorFor(String holdingId) {
  final palette = AppColors.categoryPresets;
  final idx = holdingId.hashCode.abs() % palette.length;
  return palette[idx];
}

String _formatMoney(double v) {
  final whole = v.truncate();
  final cents = ((v - whole) * 100).round().abs().toString().padLeft(2, '0');
  final buf = StringBuffer();
  final str = whole.abs().toString();
  for (var i = 0; i < str.length; i++) {
    if (i > 0 && (str.length - i) % 3 == 0) buf.write(',');
    buf.write(str[i]);
  }
  final sign = whole < 0 ? '-' : '';
  return '$sign${buf.toString()}.$cents';
}
