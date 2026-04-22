import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'package:pocket_pilot/src/core/theme/app_theme.dart';
import 'package:pocket_pilot/src/features/investments/domain/current_price_resolver.dart';
import 'package:pocket_pilot/src/features/investments/domain/investment_holding.dart';
import 'package:pocket_pilot/src/features/investments/domain/pnl_math.dart';
import 'package:pocket_pilot/src/features/investments/domain/position_math.dart';
import 'package:pocket_pilot/src/features/investments/ui/holding_detail_screen.dart'
    show PriceSourceBadge, formatMoney, formatQty;
import 'package:pocket_pilot/src/features/investments/ui/investment_view_model.dart';
import 'package:pocket_pilot/src/ui/widgets/pp_screen_state.dart';

/// Holding row stats precomputed once per frame.
class _HoldingStats {
  final InvestmentHoldingModel holding;
  final Position position;
  final PriceQuote priceQuote;
  final double? marketValue;
  final double unrealized;
  final double? realized;
  final Map<String, double> dividends;
  final bool hasError;

  const _HoldingStats({
    required this.holding,
    required this.position,
    required this.priceQuote,
    required this.marketValue,
    required this.unrealized,
    required this.realized,
    required this.dividends,
    required this.hasError,
  });
}

_HoldingStats _buildStats(
  InvestmentHoldingModel h,
  InvestmentViewModel vm,
) {
  final lots = vm.lotsFor(h.id);
  try {
    final position = computePosition(lots);
    final price = vm.priceFor(h.symbol, h.exchange);
    final quote = resolveCurrentPrice(
      holding: h,
      marketPrice: price,
      lots: lots,
    );
    final mv = (quote.price != null && position.netQuantity > 0)
        ? quote.price! * position.netQuantity
        : null;
    final unreal = computeUnrealizedPnL(
      position: position,
      currentPrice: quote.price,
    );
    double? realized;
    try {
      realized = computeRealizedPnL(lots).totalRealized;
    } on InvestmentMathException {
      realized = null;
    }
    final dividends = vm.totalDividendsFor(h.id);
    return _HoldingStats(
      holding: h,
      position: position,
      priceQuote: quote,
      marketValue: mv,
      unrealized: unreal,
      realized: realized,
      dividends: dividends,
      hasError: position.netQuantity < 0,
    );
  } catch (_) {
    return _HoldingStats(
      holding: h,
      position: (
        netQuantity: 0,
        weightedAvgCost: 0,
        fifoRemainingLots: const [],
      ),
      priceQuote: (price: null, source: 'none'),
      marketValue: null,
      unrealized: 0,
      realized: null,
      dividends: const {},
      hasError: true,
    );
  }
}

/// Threshold beyond which the banner warns the user that prices may be
/// outdated. The backend cron runs every 24h; two days is a conservative
/// floor that avoids noise on a single missed tick.
const Duration _kStalePriceThreshold = Duration(days: 2);

class HoldingsListTab extends StatelessWidget {
  const HoldingsListTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<InvestmentViewModel>(
      builder: (context, vm, _) {
        final holdings = [...vm.allHoldings]
          ..sort((a, b) => a.symbol.compareTo(b.symbol));

        final stats = holdings.map((h) => _buildStats(h, vm)).toList();

        return Column(
          children: [
            if (vm.isSyncing && !vm.isLoadingAll)
              LinearProgressIndicator(
                color: Theme.of(context).colorScheme.primary,
                backgroundColor:
                    Theme.of(context).colorScheme.surfaceContainerHigh,
                minHeight: 2,
              ),
            if (_shouldShowStaleBanner(vm.maxFetchedAt))
              _StalePricesBanner(maxFetchedAt: vm.maxFetchedAt!),
            Expanded(
              child: PpScreenState(
                isLoading: vm.isLoadingAll && holdings.isEmpty,
                errorMessage: holdings.isEmpty ? vm.errorMessage : null,
                isEmpty: !vm.isLoadingAll && holdings.isEmpty,
                emptyIcon: Icons.stacked_line_chart_rounded,
                emptyLabel: 'Sin holdings aún',
                emptySubLabel: 'Presiona + para agregar uno',
                onRefresh: vm.refresh,
                child: ListView.builder(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                  itemCount: stats.length,
                  itemBuilder: (ctx, index) {
                    final s = stats[index];
                    return Dismissible(
                      key: ValueKey(s.holding.id),
                      direction: DismissDirection.endToStart,
                      background: _ArchiveBackground(),
                      confirmDismiss: (_) =>
                          _confirmArchive(ctx, s.holding.symbol),
                      onDismissed: (_) async {
                        await vm.archiveHolding(s.holding);
                        if (!ctx.mounted) return;
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Holding "${s.holding.symbol}" archivado',
                            ),
                          ),
                        );
                      },
                      child: _HoldingPnLCard(
                        stats: s,
                        onTap: () => _openHolding(ctx, s.holding),
                      ),
                    );
                  },
                ),
              ),
            ),
            if (stats.isNotEmpty) _TotalsFooter(stats: stats),
          ],
        );
      },
    );
  }

  void _openHolding(BuildContext context, InvestmentHoldingModel holding) {
    context
        .push('/accounts/holdings/${holding.id}', extra: holding)
        .then((_) {
      if (!context.mounted) return;
      context.read<InvestmentViewModel>().loadPortfolio();
    });
  }

  Future<bool?> _confirmArchive(BuildContext context, String symbol) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Archivar holding'),
        content: Text(
          'Se archivará el holding "$symbol" y todas sus operaciones.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Archivar'),
          ),
        ],
      ),
    );
  }
}

class _HoldingPnLCard extends StatelessWidget {
  final _HoldingStats stats;
  final VoidCallback onTap;

  const _HoldingPnLCard({required this.stats, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ccy = stats.holding.currencyCode;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: AppTheme.radiusMedium,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainer,
            borderRadius: AppTheme.radiusMedium,
            border: Border.all(color: theme.colorScheme.surfaceContainerHigh),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary
                          .withValues(alpha: 0.12),
                      borderRadius: AppTheme.radiusFull,
                    ),
                    child: Icon(
                      Icons.stacked_line_chart_rounded,
                      color: theme.colorScheme.primary,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          stats.holding.symbol,
                          style: GoogleFonts.ibmPlexSans(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          [
                            stats.holding.displayName,
                            stats.holding.exchange,
                            ccy,
                          ].where((e) => e.isNotEmpty).join(' · '),
                          style: GoogleFonts.ibmPlexSans(
                            fontSize: 11,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (stats.hasError)
                    _ErrorPill()
                  else
                    PriceSourceBadge(source: stats.priceQuote.source),
                ],
              ),
              const SizedBox(height: 10),
              LayoutBuilder(
                builder: (ctx, c) {
                  final narrow = c.maxWidth < 480;
                  final tiles = [
                    _MetricTile(
                      label: 'Cant.',
                      value: formatQty(stats.position.netQuantity),
                    ),
                    _MetricTile(
                      label: 'Avg',
                      value: stats.position.weightedAvgCost > 0
                          ? formatMoney(stats.position.weightedAvgCost)
                          : '—',
                    ),
                    _MetricTile(
                      label: 'Px',
                      value: stats.priceQuote.price == null
                          ? '—'
                          : formatMoney(stats.priceQuote.price!),
                    ),
                    _MetricTile(
                      label: 'Valor',
                      value: stats.marketValue == null
                          ? '—'
                          : formatMoney(stats.marketValue!),
                      emphasis: true,
                    ),
                  ];
                  if (narrow) {
                    return Column(
                      children: [
                        Row(children: [
                          Expanded(child: tiles[0]),
                          Expanded(child: tiles[1]),
                        ]),
                        const SizedBox(height: 6),
                        Row(children: [
                          Expanded(child: tiles[2]),
                          Expanded(child: tiles[3]),
                        ]),
                      ],
                    );
                  }
                  return Row(
                    children: tiles.map((t) => Expanded(child: t)).toList(),
                  );
                },
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 14,
                runSpacing: 4,
                children: [
                  _PnLChip(
                    label: 'Unreal',
                    amount: stats.priceQuote.price == null
                        ? null
                        : stats.unrealized,
                    currencyCode: ccy,
                  ),
                  _PnLChip(
                    label: 'Real',
                    amount: stats.realized,
                    currencyCode: ccy,
                  ),
                  if (stats.dividends.isNotEmpty)
                    _PnLChip(
                      label: 'Div',
                      amount: stats.dividends[ccy],
                      currencyCode: ccy,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  final String label;
  final String value;
  final bool emphasis;

  const _MetricTile({
    required this.label,
    required this.value,
    this.emphasis = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.ibmPlexSans(
            fontSize: 10,
            letterSpacing: 0.4,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        Text(
          value,
          style: GoogleFonts.ibmPlexSans(
            fontSize: emphasis ? 15 : 13,
            fontWeight: emphasis ? FontWeight.w700 : FontWeight.w600,
            color: emphasis ? theme.colorScheme.primary : null,
          ),
        ),
      ],
    );
  }
}

class _PnLChip extends StatelessWidget {
  final String label;
  final double? amount;
  final String currencyCode;

  const _PnLChip({
    required this.label,
    required this.amount,
    required this.currencyCode,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (amount == null) {
      return _chipText(
        context,
        '$label —',
        theme.colorScheme.onSurfaceVariant,
      );
    }
    final v = amount!;
    final color = v > 0
        ? Colors.green.shade600
        : (v < 0 ? theme.colorScheme.error : theme.colorScheme.onSurface);
    final sign = v > 0 ? '+' : (v < 0 ? '' : '');
    return _chipText(
      context,
      '$label $sign${formatMoney(v)} $currencyCode',
      color,
    );
  }

  Widget _chipText(BuildContext context, String text, Color color) {
    return Text(
      text,
      style: GoogleFonts.ibmPlexSans(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: color,
      ),
    );
  }
}

class _ErrorPill extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.error;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: AppTheme.radiusFull,
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        'Datos inconsistentes',
        style: GoogleFonts.ibmPlexSans(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: color,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

class _TotalsFooter extends StatelessWidget {
  final List<_HoldingStats> stats;

  const _TotalsFooter({required this.stats});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final valueByCcy = <String, double>{};
    final unrealByCcy = <String, double>{};
    final realByCcy = <String, double>{};
    final divByCcy = <String, double>{};

    for (final s in stats) {
      final ccy = s.holding.currencyCode;
      if (s.marketValue != null) {
        valueByCcy[ccy] = (valueByCcy[ccy] ?? 0) + s.marketValue!;
      }
      if (s.priceQuote.price != null) {
        unrealByCcy[ccy] = (unrealByCcy[ccy] ?? 0) + s.unrealized;
      }
      if (s.realized != null) {
        realByCcy[ccy] = (realByCcy[ccy] ?? 0) + s.realized!;
      }
      for (final e in s.dividends.entries) {
        divByCcy[e.key] = (divByCcy[e.key] ?? 0) + e.value;
      }
    }

    final currencies = <String>{
      ...valueByCcy.keys,
      ...unrealByCcy.keys,
      ...realByCcy.keys,
      ...divByCcy.keys,
    }.toList()
      ..sort();

    if (currencies.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        border: Border(
          top: BorderSide(color: theme.colorScheme.surfaceContainerHighest),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final ccy in currencies)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: _TotalsRow(
                currency: ccy,
                value: valueByCcy[ccy],
                unreal: unrealByCcy[ccy],
                real: realByCcy[ccy],
                div: divByCcy[ccy],
              ),
            ),
        ],
      ),
    );
  }
}

class _TotalsRow extends StatelessWidget {
  final String currency;
  final double? value;
  final double? unreal;
  final double? real;
  final double? div;

  const _TotalsRow({
    required this.currency,
    required this.value,
    required this.unreal,
    required this.real,
    required this.div,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 14,
      runSpacing: 2,
      children: [
        Text(
          'Total $currency',
          style: GoogleFonts.ibmPlexSans(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: theme.colorScheme.onSurface,
          ),
        ),
        if (value != null)
          _TotalsItem(label: 'Valor', amount: value!, neutral: true),
        if (unreal != null)
          _TotalsItem(label: 'Unreal', amount: unreal!),
        if (real != null) _TotalsItem(label: 'Real', amount: real!),
        if (div != null) _TotalsItem(label: 'Div', amount: div!, neutral: true),
      ],
    );
  }
}

class _TotalsItem extends StatelessWidget {
  final String label;
  final double amount;
  final bool neutral;

  const _TotalsItem({
    required this.label,
    required this.amount,
    this.neutral = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = neutral
        ? theme.colorScheme.onSurface
        : (amount > 0
            ? Colors.green.shade600
            : (amount < 0
                ? theme.colorScheme.error
                : theme.colorScheme.onSurface));
    final sign = (!neutral && amount > 0) ? '+' : '';
    return Text(
      '$label $sign${formatMoney(amount)}',
      style: GoogleFonts.ibmPlexSans(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: color,
      ),
    );
  }
}

bool _shouldShowStaleBanner(DateTime? maxFetchedAt) {
  if (maxFetchedAt == null) return false;
  return DateTime.now().difference(maxFetchedAt) > _kStalePriceThreshold;
}

class _StalePricesBanner extends StatelessWidget {
  final DateTime maxFetchedAt;

  const _StalePricesBanner({required this.maxFetchedAt});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final days = DateTime.now().difference(maxFetchedAt).inDays;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: theme.colorScheme.tertiary.withValues(alpha: 0.12),
      child: Row(
        children: [
          Icon(
            Icons.access_time_rounded,
            size: 16,
            color: theme.colorScheme.tertiary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Precios actualizados hace $days ${days == 1 ? "día" : "días"}',
              style: GoogleFonts.ibmPlexSans(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.tertiary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ArchiveBackground extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.tertiary.withValues(alpha: 0.18),
        borderRadius: AppTheme.radiusMedium,
        border: Border.all(
          color: Theme.of(context).colorScheme.tertiary.withValues(alpha: 0.5),
        ),
      ),
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Archivar',
            style: GoogleFonts.ibmPlexSans(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.tertiary,
            ),
          ),
          const SizedBox(width: 6),
          Icon(
            Icons.archive_outlined,
            color: Theme.of(context).colorScheme.tertiary,
          ),
        ],
      ),
    );
  }
}
