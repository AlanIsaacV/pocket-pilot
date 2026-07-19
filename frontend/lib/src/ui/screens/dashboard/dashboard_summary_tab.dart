// ============================================================
// DashboardSummaryTab — body of the Resumen tab inside DashboardScreen
// ============================================================
//
// Hosts the existing dashboard widgets (currency tabs, net worth, metrics,
// accounts, credit cards, category/nature/tag spend). Extracted from the
// old `DashboardScreen.build()` when the Estadísticas tab was introduced.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:pocket_pilot/src/core/constants/nature_labels.dart';
import 'package:pocket_pilot/src/core/theme/app_colors.dart';
import 'package:pocket_pilot/src/core/theme/app_theme.dart';
import 'package:pocket_pilot/src/features/dashboard/domain/account_balance_dto.dart';
import 'package:pocket_pilot/src/features/dashboard/domain/category_spend_dto.dart';
import 'package:pocket_pilot/src/features/dashboard/domain/credit_card_payment_dto.dart';
import 'package:pocket_pilot/src/features/dashboard/domain/dashboard_metrics.dart';
import 'package:pocket_pilot/src/features/dashboard/domain/nature_spend_dto.dart';
import 'package:pocket_pilot/src/features/dashboard/domain/tag_spend_dto.dart';
import 'package:pocket_pilot/src/features/dashboard/ui/dashboard_view_model.dart';
import 'package:pocket_pilot/src/features/dashboard/ui/widgets/allocation_card.dart';
import 'package:pocket_pilot/src/ui/widgets/dashboard_filter_sheet.dart';

class DashboardSummaryTab extends StatelessWidget {
  const DashboardSummaryTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Consumer<DashboardViewModel>(
          builder: (context, vm, _) {
            if (vm.isLoading) {
              return const Center(child: CircularProgressIndicator());
            }

            final metrics = vm.activeMetrics;

            return RefreshIndicator(
              onRefresh: vm.refresh,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 160),
                children: [
                  if (metrics != null) ...[
                _NetWorthCard(metrics: metrics),
                const SizedBox(height: 12),
                AllocationCard(metrics: metrics),
                _MetricsGrid(metrics: metrics),
              ] else
                _EmptyHint(
                  icon: Icons.analytics_outlined,
                  label: 'Sin datos disponibles',
                ),
              if (vm.filteredCreditCardPayments.isNotEmpty) ...[
                const SizedBox(height: 28),
                _SectionHeader(title: 'Tarjetas de crédito'),
                const SizedBox(height: 12),
                ...vm.filteredCreditCardPayments.map(
                  (card) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _CreditCardPaymentCard(payment: card),
                  ),
                ),
              ],
              const SizedBox(height: 28),
              _SectionHeader(title: 'Cuentas'),
              const SizedBox(height: 12),
              if (vm.filteredAccountBalances.isEmpty)
                _EmptyHint(
                  icon: Icons.account_balance_wallet_outlined,
                  label: 'Sin cuentas registradas',
                )
              else
                ...vm.filteredAccountBalances.map(
                  (b) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _AccountCard(balance: b),
                  ),
                ),
              const SizedBox(height: 20),
              _SectionHeader(title: 'Gasto del mes'),
              const SizedBox(height: 12),
              if (vm.filteredMonthlySpend.isEmpty)
                _EmptyHint(
                  icon: Icons.pie_chart_outline,
                  label: 'Sin gastos este mes',
                )
              else
                _SpendBreakdown(items: vm.filteredMonthlySpend),
              const SizedBox(height: 20),
              _SectionHeader(title: 'Gastos por naturaleza'),
              const SizedBox(height: 12),
              if (vm.filteredMonthlySpendByNature.isEmpty)
                _EmptyHint(
                  icon: Icons.style_outlined,
                  label: 'Sin gastos este mes',
                )
              else
                _NatureSpendBreakdown(items: vm.filteredMonthlySpendByNature),
              const SizedBox(height: 20),
              _SectionHeader(title: 'Gastos por etiqueta'),
              const SizedBox(height: 12),
              if (vm.filteredMonthlySpendByTag.isEmpty)
                _EmptyHint(
                  icon: Icons.label_outlined,
                  label: 'Sin etiquetas este mes',
                )
              else
                    _TagSpendBreakdown(items: vm.filteredMonthlySpendByTag),
                ],
              ),
            );
          },
        ),
        const DashboardFilterSheet(),
      ],
    );
  }
}

// ============================================================
// Net Worth hero card
// ============================================================

class _NetWorthCard extends StatelessWidget {
  final DashboardMetrics metrics;

  const _NetWorthCard({required this.metrics});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isNegative = metrics.netWorthCents < 0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        borderRadius: AppTheme.radiusMedium,
        border: Border.all(color: cs.surfaceContainerHigh, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Patrimonio neto',
                style: GoogleFonts.ibmPlexSans(
                  fontSize: 13,
                  color: cs.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHigh,
                  borderRadius: AppTheme.radiusFull,
                ),
                child: Text(
                  metrics.currencyCode,
                  style: GoogleFonts.ibmPlexSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _formatAmount(metrics.netWorthCents, metrics.currencyCode),
            style: GoogleFonts.ibmPlexSans(
              fontSize: 36,
              fontWeight: FontWeight.w600,
              letterSpacing: -1,
              color: isNegative ? cs.error : cs.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// Metrics grid — 3 secondary metrics
// ============================================================

class _MetricsGrid extends StatelessWidget {
  final DashboardMetrics metrics;

  const _MetricsGrid({required this.metrics});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _MetricCard(
                label: 'Liquidez real',
                cents: metrics.liquidAssetsCents,
                currency: metrics.currencyCode,
                icon: Icons.water_drop_outlined,
                iconColor: AppColors.catSapphire,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _MetricCard(
                label: 'Liquidez libre',
                cents: metrics.safeToSpendCents,
                currency: metrics.currencyCode,
                icon: Icons.shield_outlined,
                iconColor: AppColors.catGreen,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _MetricCard(
          label: 'Poder de compra',
          cents: metrics.buyingPowerCents,
          currency: metrics.currencyCode,
          icon: Icons.bolt_outlined,
          iconColor: AppColors.catYellow,
          fullWidth: true,
        ),
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String label;
  final int cents;
  final String currency;
  final IconData icon;
  final Color iconColor;
  final bool fullWidth;

  const _MetricCard({
    required this.label,
    required this.cents,
    required this.currency,
    required this.icon,
    required this.iconColor,
    this.fullWidth = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isNegative = cents < 0;

    final card = Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        borderRadius: AppTheme.radiusMedium,
        border: Border.all(color: cs.surfaceContainerHigh, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: iconColor),
          const SizedBox(height: 8),
          Text(
            _formatAmount(cents, currency),
            style: GoogleFonts.ibmPlexSans(
              fontSize: fullWidth ? 22 : 18,
              fontWeight: FontWeight.w600,
              color: isNegative ? cs.error : cs.onSurface,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: GoogleFonts.ibmPlexSans(
              fontSize: 11,
              color: cs.onSurfaceVariant,
            ),
            maxLines: 2,
          ),
        ],
      ),
    );

    return fullWidth ? SizedBox(width: double.infinity, child: card) : card;
  }
}

// ============================================================
// Account cards
// ============================================================

class _AccountCard extends StatelessWidget {
  final AccountBalanceDTO balance;

  const _AccountCard({required this.balance});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isNegative = balance.balanceCents < 0;

    return InkWell(
      borderRadius: AppTheme.radiusMedium,
      onTap: () => context.push('/accounts/${balance.accountId}/edit'),
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
                color: cs.primary.withValues(alpha: 0.12),
                borderRadius: AppTheme.radiusSmall,
              ),
              child: Icon(
                _accountIcon(balance.accountType),
                size: 20,
                color: cs.primary,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    balance.accountName,
                    style: GoogleFonts.ibmPlexSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface,
                    ),
                  ),
                  Text(
                    _accountTypeLabel(balance.accountType),
                    style: GoogleFonts.ibmPlexSans(
                      fontSize: 12,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              _formatAmount(balance.balanceCents, balance.currencyCode),
              style: GoogleFonts.ibmPlexSans(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: isNegative ? cs.error : cs.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// Credit card payment card
// ============================================================

class _CreditCardPaymentCard extends StatelessWidget {
  final CreditCardPaymentDTO payment;

  const _CreditCardPaymentCard({required this.payment});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
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
              color: AppColors.catPeach.withValues(alpha: 0.12),
              borderRadius: AppTheme.radiusSmall,
            ),
            child: Icon(
              Icons.credit_card_outlined,
              size: 20,
              color: AppColors.catPeach,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  payment.accountName,
                  style: GoogleFonts.ibmPlexSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                  ),
                ),
                Text(
                  'Pago estimado',
                  style: GoogleFonts.ibmPlexSans(
                    fontSize: 12,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Text(
            _formatAmount(payment.estimatedPaymentCents, payment.currencyCode),
            style: GoogleFonts.ibmPlexSans(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: payment.estimatedPaymentCents > 0
                  ? cs.error
                  : cs.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// Monthly spend breakdown
// ============================================================

class _SpendBreakdown extends StatelessWidget {
  final List<CategorySpendDTO> items;

  const _SpendBreakdown({required this.items});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final sorted = items.where((i) => i.spentCents > 0).toList()
      ..sort((a, b) => b.spentCents.compareTo(a.spentCents));

    if (sorted.isEmpty) {
      return _EmptyHint(
        icon: Icons.pie_chart_outline,
        label: 'Sin gastos este mes',
      );
    }

    final totalSpent = sorted.fold(0, (sum, i) => sum + i.spentCents);
    final currency = sorted.first.currencyCode;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        borderRadius: AppTheme.radiusMedium,
        border: Border.all(color: cs.surfaceContainerHigh, width: 1),
      ),
      child: Column(
        children: [
          ClipRRect(
            borderRadius: AppTheme.radiusFull,
            child: SizedBox(
              height: 8,
              child: Row(
                children: sorted.map((item) {
                  final fraction =
                      totalSpent > 0 ? item.spentCents / totalSpent : 0.0;
                  return Expanded(
                    flex: (fraction * 1000).round().clamp(1, 1000),
                    child: Container(
                      color: _parseCategoryColor(item.categoryColor, cs),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          const SizedBox(height: 16),
          ...sorted.take(6).map((item) {
            final pct = totalSpent > 0
                ? (item.spentCents / totalSpent * 100).round()
                : 0;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: _parseCategoryColor(item.categoryColor, cs),
                      borderRadius:
                          const BorderRadius.all(Radius.circular(3)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      item.categoryName ?? 'Sin categoría',
                      style: GoogleFonts.ibmPlexSans(
                        fontSize: 13,
                        color: cs.onSurface,
                      ),
                    ),
                  ),
                  Text(
                    '$pct%',
                    style: GoogleFonts.ibmPlexSans(
                      fontSize: 12,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    _formatAmount(item.spentCents, currency),
                    style: GoogleFonts.ibmPlexSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface,
                    ),
                  ),
                ],
              ),
            );
          }),
          if (sorted.length > 6)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '+${sorted.length - 6} más',
                style: GoogleFonts.ibmPlexSans(
                  fontSize: 12,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ============================================================
// Nature spend breakdown
// ============================================================

class _NatureSpendBreakdown extends StatelessWidget {
  final List<NatureSpendDTO> items;

  const _NatureSpendBreakdown({required this.items});

  static const _natureColors = <String, Color>{
    'required': AppColors.catRed,
    'obligation': AppColors.catPeach,
    'lifestyle': AppColors.catMauve,
    'active': AppColors.catGreen,
    'passive': AppColors.catTeal,
    'windfall': AppColors.catYellow,
    'adjustment': AppColors.catSapphire,
  };

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final sorted = items.where((i) => i.spentCents > 0).toList()
      ..sort((a, b) => b.spentCents.compareTo(a.spentCents));

    if (sorted.isEmpty) {
      return _EmptyHint(
        icon: Icons.style_outlined,
        label: 'Sin gastos este mes',
      );
    }

    final totalSpent = sorted.fold(0, (sum, i) => sum + i.spentCents);
    final currency = sorted.first.currencyCode;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        borderRadius: AppTheme.radiusMedium,
        border: Border.all(color: cs.surfaceContainerHigh, width: 1),
      ),
      child: Column(
        children: [
          ClipRRect(
            borderRadius: AppTheme.radiusFull,
            child: SizedBox(
              height: 8,
              child: Row(
                children: sorted.map((item) {
                  final fraction =
                      totalSpent > 0 ? item.spentCents / totalSpent : 0.0;
                  return Expanded(
                    flex: (fraction * 1000).round().clamp(1, 1000),
                    child: Container(
                      color: _natureColors[item.nature] ?? cs.primary,
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          const SizedBox(height: 16),
          ...sorted.map((item) {
            final pct = totalSpent > 0
                ? (item.spentCents / totalSpent * 100).round()
                : 0;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: _natureColors[item.nature] ?? cs.primary,
                      borderRadius:
                          const BorderRadius.all(Radius.circular(3)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      natureDisplayLabel(item.nature),
                      style: GoogleFonts.ibmPlexSans(
                        fontSize: 13,
                        color: cs.onSurface,
                      ),
                    ),
                  ),
                  Text(
                    '$pct%',
                    style: GoogleFonts.ibmPlexSans(
                      fontSize: 12,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    _formatAmount(item.spentCents, currency),
                    style: GoogleFonts.ibmPlexSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface,
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
}

// ============================================================
// Tag spend breakdown
// ============================================================

class _TagSpendBreakdown extends StatelessWidget {
  final List<TagSpendDTO> items;

  const _TagSpendBreakdown({required this.items});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final palette = AppColors.categoryPresets;

    final sorted = items.where((i) => i.spentCents > 0).toList()
      ..sort((a, b) => b.spentCents.compareTo(a.spentCents));

    if (sorted.isEmpty) {
      return _EmptyHint(
        icon: Icons.label_outlined,
        label: 'Sin etiquetas este mes',
      );
    }

    final totalSpent = sorted.fold(0, (sum, i) => sum + i.spentCents);
    final currency = sorted.first.currencyCode;

    Color colorFor(String tag) =>
        palette[tag.hashCode.abs() % palette.length];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        borderRadius: AppTheme.radiusMedium,
        border: Border.all(color: cs.surfaceContainerHigh, width: 1),
      ),
      child: Column(
        children: [
          ClipRRect(
            borderRadius: AppTheme.radiusFull,
            child: SizedBox(
              height: 8,
              child: Row(
                children: sorted.map((item) {
                  final fraction =
                      totalSpent > 0 ? item.spentCents / totalSpent : 0.0;
                  return Expanded(
                    flex: (fraction * 1000).round().clamp(1, 1000),
                    child: Container(color: colorFor(item.tagName)),
                  );
                }).toList(),
              ),
            ),
          ),
          const SizedBox(height: 16),
          ...sorted.take(8).map((item) {
            final pct = totalSpent > 0
                ? (item.spentCents / totalSpent * 100).round()
                : 0;
            return InkWell(
              borderRadius: AppTheme.radiusSmall,
              onTap: () => context.push(
                '/dashboard/statistics/tags/${Uri.encodeComponent(item.tagName)}'
                '?currency=${item.currencyCode}',
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: colorFor(item.tagName),
                        borderRadius:
                            const BorderRadius.all(Radius.circular(3)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        item.tagName,
                        style: GoogleFonts.ibmPlexSans(
                          fontSize: 13,
                          color: cs.onSurface,
                        ),
                      ),
                    ),
                    Text(
                      '$pct%',
                      style: GoogleFonts.ibmPlexSans(
                        fontSize: 12,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      _formatAmount(item.spentCents, currency),
                      style: GoogleFonts.ibmPlexSans(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
          if (sorted.length > 8)
            InkWell(
              borderRadius: AppTheme.radiusSmall,
              onTap: () => context.push('/dashboard/statistics/tags'),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(
                  '+${sorted.length - 8} más',
                  style: GoogleFonts.ibmPlexSans(
                    fontSize: 12,
                    color: cs.primary,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ============================================================
// Shared helpers
// ============================================================

class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: GoogleFonts.ibmPlexSans(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: Theme.of(context).colorScheme.onSurface,
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  final IconData icon;
  final String label;

  const _EmptyHint({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        borderRadius: AppTheme.radiusMedium,
        border: Border.all(color: cs.surfaceContainerHigh, width: 1),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 18, color: cs.onSurfaceVariant),
          const SizedBox(width: 8),
          Text(
            label,
            style: GoogleFonts.ibmPlexSans(
              fontSize: 13,
              color: cs.onSurfaceVariant,
            ),
          ),
        ],
      ),
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

IconData _accountIcon(String type) {
  return switch (type) {
    'bank' => Icons.account_balance_outlined,
    'cash' => Icons.payments_outlined,
    'credit_card' => Icons.credit_card_outlined,
    'loan' => Icons.request_quote_outlined,
    'investment' => Icons.trending_up_outlined,
    'crypto' => Icons.currency_bitcoin_outlined,
    _ => Icons.account_balance_wallet_outlined,
  };
}

String _accountTypeLabel(String type) {
  return switch (type) {
    'bank' => 'Banco',
    'cash' => 'Efectivo',
    'credit_card' => 'Tarjeta de crédito',
    'loan' => 'Préstamo',
    'investment' => 'Inversión',
    'crypto' => 'Cripto',
    'other' => 'Otro',
    _ => type,
  };
}

Color _parseCategoryColor(String? hex, ColorScheme cs) {
  if (hex == null || hex.isEmpty) return cs.primary;
  try {
    final cleaned = hex.replaceFirst('#', '');
    return Color(int.parse('FF$cleaned', radix: 16));
  } catch (_) {
    return cs.primary;
  }
}
