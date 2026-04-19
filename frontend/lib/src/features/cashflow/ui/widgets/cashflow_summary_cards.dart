// features/cashflow/ui/widgets/cashflow_summary_cards.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:pocket_pilot/src/core/theme/app_theme.dart';

class CashflowSummaryCards extends StatelessWidget {
  final String currencyCode;
  final int totalInCents;
  final int totalOutCents;
  final int netCents;

  const CashflowSummaryCards({
    super.key,
    required this.currencyCode,
    required this.totalInCents,
    required this.totalOutCents,
    required this.netCents,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: _Card(
            label: 'Entra',
            value: _fmt(totalInCents, currencyCode, showPlus: true),
            valueColor: cs.primary,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _Card(
            label: 'Sale',
            value: _fmt(-totalOutCents, currencyCode),
            valueColor: cs.error,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _Card(
            label: 'Neto',
            value: _fmt(netCents, currencyCode, showPlus: netCents > 0),
            valueColor: netCents >= 0 ? cs.primary : cs.error,
            emphasized: true,
          ),
        ),
      ],
    );
  }

  static String _fmt(int cents, String currency, {bool showPlus = false}) {
    final sign = cents < 0 ? '-' : (showPlus ? '+' : '');
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

class _Card extends StatelessWidget {
  final String label;
  final String value;
  final Color valueColor;
  final bool emphasized;

  const _Card({
    required this.label,
    required this.value,
    required this.valueColor,
    this.emphasized = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        borderRadius: AppTheme.radiusMedium,
        border: Border.all(
          color: emphasized ? valueColor.withValues(alpha: 0.3) : cs.surfaceContainerHigh,
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: GoogleFonts.ibmPlexSans(
              fontSize: 11,
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: GoogleFonts.ibmPlexSans(
                fontSize: emphasized ? 18 : 15,
                fontWeight: FontWeight.w700,
                color: valueColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
