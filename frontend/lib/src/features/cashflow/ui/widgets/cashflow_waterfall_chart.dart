// features/cashflow/ui/widgets/cashflow_waterfall_chart.dart
//
// Renders a waterfall: income entries step up from 0 to totalIn, expense
// entries step down from totalIn to net. A final "Neto" bar is drawn
// from 0 to net. Uses fl_chart's BarChartRodData.fromY/toY to position
// each bar as a segment of the staircase. Bars with amount <= 0 are
// skipped so an empty window doesn't render zero-height stubs.

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:pocket_pilot/src/core/constants/nature_labels.dart';
import 'package:pocket_pilot/src/features/cashflow/domain/cashflow_snapshot.dart';

class CashflowWaterfallChart extends StatelessWidget {
  final List<CashflowBreakdownEntry> entries;
  final BreakdownMode mode;
  final int totalInCents;
  final int totalOutCents;
  final int netCents;

  const CashflowWaterfallChart({
    super.key,
    required this.entries,
    required this.mode,
    required this.totalInCents,
    required this.totalOutCents,
    required this.netCents,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final steps = _buildSteps(cs);
    if (steps.isEmpty) {
      return SizedBox(
        height: 180,
        child: Center(
          child: Text(
            'Sin movimientos en este periodo',
            style: GoogleFonts.ibmPlexSans(
              fontSize: 13,
              color: cs.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    final minY = steps
        .map((s) => s.fromY < s.toY ? s.fromY : s.toY)
        .reduce((a, b) => a < b ? a : b);
    final maxY = steps
        .map((s) => s.fromY > s.toY ? s.fromY : s.toY)
        .reduce((a, b) => a > b ? a : b);
    final span = (maxY - minY).clamp(1.0, double.infinity);
    final padding = span * 0.1;

    return SizedBox(
      height: 240,
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          minY: minY - padding,
          maxY: maxY + padding,
          barTouchData: BarTouchData(
            enabled: true,
            touchTooltipData: BarTouchTooltipData(
              getTooltipItem: (group, a, rod, b) {
                final step = steps[group.x];
                return BarTooltipItem(
                  '${step.label}\n${_fmt(step.deltaCents)}',
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
                reservedSize: 28,
                getTitlesWidget: (x, _) {
                  final i = x.toInt();
                  if (i < 0 || i >= steps.length) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      _truncate(steps[i].label, 8),
                      style: GoogleFonts.ibmPlexSans(
                        fontSize: 10,
                        color: cs.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                },
              ),
            ),
          ),
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          extraLinesData: ExtraLinesData(
            horizontalLines: [
              HorizontalLine(
                y: 0,
                color: cs.onSurfaceVariant.withValues(alpha: 0.35),
                strokeWidth: 1,
                dashArray: const [3, 3],
              ),
            ],
          ),
          barGroups: [
            for (var i = 0; i < steps.length; i++)
              BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    fromY: steps[i].fromY,
                    toY: steps[i].toY,
                    width: 18,
                    color: steps[i].color,
                    borderRadius: const BorderRadius.all(Radius.circular(3)),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  List<_Step> _buildSteps(ColorScheme cs) {
    final income = entries.where((e) => e.kind == 'income' && e.amountCents > 0);
    final expense =
        entries.where((e) => e.kind == 'expense' && e.amountCents > 0);

    final steps = <_Step>[];
    var running = 0.0;

    for (final e in income) {
      final next = running + e.amountCents;
      steps.add(_Step(
        label: _labelFor(e),
        fromY: running,
        toY: next,
        deltaCents: e.amountCents,
        color: e.color ?? cs.primary,
      ));
      running = next;
    }

    for (final e in expense) {
      final next = running - e.amountCents;
      steps.add(_Step(
        label: _labelFor(e),
        fromY: running,
        toY: next,
        deltaCents: -e.amountCents,
        color: e.color ?? cs.error,
      ));
      running = next;
    }

    if (steps.isEmpty) return const [];

    steps.add(_Step(
      label: 'Neto',
      fromY: 0,
      toY: netCents.toDouble(),
      deltaCents: netCents,
      color: netCents >= 0 ? cs.primary : cs.error,
    ));

    return steps;
  }

  String _labelFor(CashflowBreakdownEntry e) {
    if (mode == BreakdownMode.nature) return natureDisplayLabel(e.label);
    return e.label;
  }

  static String _truncate(String s, int max) =>
      s.length <= max ? s : '${s.substring(0, max - 1)}…';

  static String _fmt(int cents) {
    final sign = cents < 0 ? '-' : '+';
    final abs = cents.abs();
    final whole = abs ~/ 100;
    final buf = StringBuffer();
    final str = whole.toString();
    for (var i = 0; i < str.length; i++) {
      if (i > 0 && (str.length - i) % 3 == 0) buf.write(',');
      buf.write(str[i]);
    }
    return '$sign\$${buf.toString()}';
  }
}

class _Step {
  final String label;
  final double fromY;
  final double toY;
  final int deltaCents;
  final Color color;

  const _Step({
    required this.label,
    required this.fromY,
    required this.toY,
    required this.deltaCents,
    required this.color,
  });
}
