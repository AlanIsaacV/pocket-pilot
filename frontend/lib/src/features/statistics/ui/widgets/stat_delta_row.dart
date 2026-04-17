// features/statistics/ui/widgets/stat_delta_row.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:pocket_pilot/src/core/theme/app_theme.dart';
import 'package:pocket_pilot/src/features/statistics/domain/trend.dart';

class StatDeltaRow extends StatelessWidget {
  final String currency;
  final int avgCents;
  final int currentCents;
  final String kind; // 'expense' | 'income'

  const StatDeltaRow({
    super.key,
    required this.currency,
    required this.avgCents,
    required this.currentCents,
    required this.kind,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final deltaPct = _deltaPct();
    final deltaColor = _deltaColor(cs);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        borderRadius: AppTheme.radiusMedium,
        border: Border.all(color: cs.surfaceContainerHigh, width: 1),
      ),
      child: Row(
        children: [
          Expanded(
            child: _Stat(
              label: 'Promedio',
              value: _fmt(avgCents, currency),
              color: cs.onSurface,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: _Stat(
              label: 'Este mes',
              value: _fmt(currentCents, currency),
              color: cs.onSurface,
              trailing: deltaPct == null
                  ? null
                  : Text(
                      '${deltaPct > 0 ? '+' : ''}$deltaPct%',
                      style: GoogleFonts.ibmPlexSans(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: deltaColor,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  int? _deltaPct() {
    if (avgCents == 0) return null;
    final diff = currentCents - avgCents;
    return (diff / avgCents * 100).round();
  }

  Color _deltaColor(ColorScheme cs) {
    final d = _deltaPct();
    if (d == null) return cs.onSurfaceVariant;
    final ratio = d.abs() / 100;
    if (ratio < kTrendFlatThresholdRatio) return cs.onSurfaceVariant;
    final higher = d > 0;
    // For expense: lower is better (primary). For income: higher is better.
    final good = (kind == 'income') == higher;
    return good ? cs.primary : cs.error;
  }

  static String _fmt(int cents, String currency) {
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
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final Widget? trailing;

  const _Stat({
    required this.label,
    required this.value,
    required this.color,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.ibmPlexSans(
            fontSize: 11,
            color: cs.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Flexible(
              child: Text(
                value,
                style: GoogleFonts.ibmPlexSans(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 8),
              trailing!,
            ],
          ],
        ),
      ],
    );
  }
}
