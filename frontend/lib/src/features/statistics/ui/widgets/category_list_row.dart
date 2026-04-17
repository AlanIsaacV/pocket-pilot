// features/statistics/ui/widgets/category_list_row.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:pocket_pilot/src/core/theme/app_theme.dart';
import 'package:pocket_pilot/src/features/statistics/domain/category_series_dto.dart';
import 'package:pocket_pilot/src/features/statistics/domain/trend.dart';

class CategoryListRow extends StatelessWidget {
  final CategorySeriesDTO item;
  final int windowMonths;
  final VoidCallback onTap;

  const CategoryListRow({
    super.key,
    required this.item,
    required this.windowMonths,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = _parseHex(item.color, cs.primary);

    return InkWell(
      borderRadius: AppTheme.radiusMedium,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: cs.surfaceContainer,
          borderRadius: AppTheme.radiusMedium,
          border: Border.all(color: cs.surfaceContainerHigh, width: 1),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: AppTheme.radiusSmall,
              ),
              child: Icon(Icons.category_outlined, size: 20, color: color),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    style: GoogleFonts.ibmPlexSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface,
                    ),
                  ),
                  Row(
                    children: [
                      Text(
                        'prom. últimos ${windowMonths}m: '
                        '${_fmt(item.avgMonthlyCents, item.currencyCode)}',
                        style: GoogleFonts.ibmPlexSans(
                          fontSize: 12,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Icon(
                        _trendIcon(item.trend),
                        size: 14,
                        color: _trendColor(item.trend, item.kind, cs),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Text(
              _fmt(item.currentMonthCents, item.currencyCode),
              style: GoogleFonts.ibmPlexSans(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static IconData _trendIcon(Trend t) => switch (t) {
        Trend.up => Icons.trending_up,
        Trend.down => Icons.trending_down,
        Trend.flat => Icons.trending_flat,
      };

  static Color _trendColor(Trend t, String kind, ColorScheme cs) {
    if (t == Trend.flat) return cs.onSurfaceVariant;
    final goingUp = t == Trend.up;
    // For expenses, up = worse (red). For income, up = better (green).
    final good = (kind == 'income') == goingUp;
    return good ? cs.primary : cs.error;
  }

  static Color _parseHex(String hex, Color fallback) {
    if (hex.isEmpty) return fallback;
    try {
      final cleaned = hex.replaceFirst('#', '');
      return Color(int.parse('FF$cleaned', radix: 16));
    } catch (_) {
      return fallback;
    }
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
    final wholeStr = buf.toString();
    final fracStr = frac == 0 ? '' : '.${frac.toString().padLeft(2, '0')}';
    return '$sign$currency \$$wholeStr$fracStr';
  }
}
