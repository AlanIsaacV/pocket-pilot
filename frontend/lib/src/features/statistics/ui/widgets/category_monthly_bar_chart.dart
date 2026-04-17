// features/statistics/ui/widgets/category_monthly_bar_chart.dart
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:pocket_pilot/src/features/statistics/domain/monthly_point_dto.dart';

class CategoryMonthlyBarChart extends StatelessWidget {
  final List<MonthlyPointDTO> points;
  final int? budgetLimitCents;
  final String currentYm;
  final int? selectedIndex;
  final ValueChanged<int> onBarTap;

  const CategoryMonthlyBarChart({
    super.key,
    required this.points,
    required this.currentYm,
    required this.onBarTap,
    this.budgetLimitCents,
    this.selectedIndex,
  });

  static const _monthAbbr = [
    'ene', 'feb', 'mar', 'abr', 'may', 'jun',
    'jul', 'ago', 'sep', 'oct', 'nov', 'dic',
  ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final allZero = points.every((p) => p.amountCents == 0);
    if (points.isEmpty || allZero) {
      return SizedBox(
        height: 180,
        child: Center(
          child: Text(
            'Sin datos en esta ventana',
            style: GoogleFonts.ibmPlexSans(
              fontSize: 13,
              color: cs.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    final maxAmount = points
        .map((p) => p.amountCents)
        .reduce((a, b) => a > b ? a : b);
    final cap = [maxAmount, budgetLimitCents ?? 0]
        .reduce((a, b) => a > b ? a : b);
    final axisMax = (cap * 1.15).clamp(1, double.infinity).toDouble();

    final firstYear = points.first.yearMonth.substring(0, 4);
    final crossesYears =
        points.any((p) => !p.yearMonth.startsWith(firstYear));

    return SizedBox(
      height: 200,
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: axisMax,
          minY: 0,
          barTouchData: BarTouchData(
            enabled: true,
            touchCallback: (event, response) {
              if (event is! FlTapUpEvent) return;
              final idx = response?.spot?.touchedBarGroupIndex;
              if (idx != null) onBarTap(idx);
            },
            touchTooltipData: BarTouchTooltipData(
              getTooltipItem: (group, a, rod, b) {
                final p = points[group.x];
                return BarTooltipItem(
                  '${_labelFor(p.yearMonth, crossesYears)}\n'
                  '\$${(p.amountCents / 100).toStringAsFixed(0)}',
                  GoogleFonts.ibmPlexSans(
                    fontSize: 12,
                    color: cs.onInverseSurface,
                  ),
                );
              },
            ),
          ),
          titlesData: FlTitlesData(
            leftTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 22,
                getTitlesWidget: (x, _) {
                  final i = x.toInt();
                  if (i < 0 || i >= points.length) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      _labelFor(points[i].yearMonth, crossesYears),
                      style: GoogleFonts.ibmPlexSans(
                        fontSize: 10,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          barGroups: [
            for (var i = 0; i < points.length; i++)
              BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: points[i].amountCents.toDouble().clamp(0, axisMax),
                    width: 14,
                    color: points[i].yearMonth == currentYm
                        ? cs.primary
                        : cs.surfaceContainerHigh,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(3),
                    ),
                  ),
                ],
              ),
          ],
          extraLinesData: ExtraLinesData(
            horizontalLines: [
              if (budgetLimitCents != null && budgetLimitCents! > 0)
                HorizontalLine(
                  y: budgetLimitCents!.toDouble(),
                  color: cs.error,
                  strokeWidth: 1.5,
                  dashArray: const [4, 4],
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _labelFor(String ym, bool includeYear) {
    final year = int.parse(ym.substring(0, 4));
    final month = int.parse(ym.substring(5, 7));
    final abbr = _monthAbbr[month - 1];
    if (!includeYear) return abbr;
    return "$abbr '${year.toString().substring(2)}";
  }
}
