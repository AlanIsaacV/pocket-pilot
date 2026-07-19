import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'package:pocket_pilot/src/core/theme/app_theme.dart';
import 'package:pocket_pilot/src/features/accounts/data/account_local_store.dart';
import 'package:pocket_pilot/src/features/accounts/domain/account.dart';
import 'package:pocket_pilot/src/features/investments/domain/current_price_resolver.dart';
import 'package:pocket_pilot/src/features/investments/domain/investment_holding.dart';
import 'package:pocket_pilot/src/features/investments/domain/investment_lot.dart';
import 'package:pocket_pilot/src/features/investments/domain/investment_split.dart';
import 'package:pocket_pilot/src/features/investments/domain/pnl_math.dart';
import 'package:pocket_pilot/src/features/investments/domain/position_math.dart';
import 'package:pocket_pilot/src/features/investments/ui/investment_view_model.dart';
import 'package:pocket_pilot/src/features/transactions/domain/transaction.dart';
import 'package:pocket_pilot/src/ui/widgets/confirm_dialog.dart';
import 'package:pocket_pilot/src/ui/widgets/form_date_utils.dart';
import 'package:pocket_pilot/src/ui/widgets/pp_screen_state.dart';

class HoldingDetailScreen extends StatefulWidget {
  final String holdingId;
  final InvestmentHoldingModel? initialHolding;

  const HoldingDetailScreen({
    required this.holdingId,
    this.initialHolding,
    super.key,
  });

  @override
  State<HoldingDetailScreen> createState() => _HoldingDetailScreenState();
}

class _HoldingDetailScreenState extends State<HoldingDetailScreen> {
  InvestmentHoldingModel? _holding;
  Map<String, AccountModel> _accountsById = const {};

  @override
  void initState() {
    super.initState();
    _holding = widget.initialHolding;
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final vm = context.read<InvestmentViewModel>();
    final accountStore = context.read<AccountLocalStore>();

    await vm.loadHoldingFull(widget.holdingId);
    if (!mounted) return;

    var found = vm.findHolding(widget.holdingId);
    if (found == null) {
      await vm.loadAll();
      if (!mounted) return;
      found = vm.findHolding(widget.holdingId);
    }

    final accounts = await accountStore.getAccounts();
    if (!mounted) return;
    setState(() {
      if (found != null) _holding = found;
      _accountsById = {for (final a in accounts) a.id: a};
    });
  }

  void _onAddLot(String kind) {
    context
        .push('/accounts/holdings/${widget.holdingId}/lots/new?kind=$kind')
        .then((_) => _load());
  }

  void _onEditLot(InvestmentLotModel lot) {
    context
        .push(
          '/accounts/holdings/${widget.holdingId}/lots/${lot.id}/edit',
          extra: lot,
        )
        .then((_) => _load());
  }

  void _onAddSplit() {
    context
        .push('/accounts/holdings/${widget.holdingId}/splits/new')
        .then((_) => _load());
  }

  void _onEditSplit(InvestmentSplitModel split) {
    context
        .push(
          '/accounts/holdings/${widget.holdingId}/splits/${split.id}/edit',
          extra: split,
        )
        .then((_) => _load());
  }

  void _onEditHolding() {
    final holding = _holding;
    if (holding == null) return;
    context
        .push('/accounts/holdings/${widget.holdingId}/edit', extra: holding)
        .then((_) => _load());
  }

  Future<void> _onArchiveHolding() async {
    final holding = _holding;
    if (holding == null) return;
    final confirm = await showConfirmDialog(
      context,
      title: 'Archivar holding',
      message:
          'Se archivará el holding "${holding.symbol}" y todas sus operaciones.',
      confirmLabel: 'Archivar',
    );
    if (confirm != true || !mounted) return;

    await context.read<InvestmentViewModel>().archiveHolding(holding);
    if (!mounted) return;
    context.pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<InvestmentViewModel>();
    final holding = _holding;
    final lots = vm.lotsFor(widget.holdingId);
    final splits = vm.splitsFor(widget.holdingId);
    final events =
        <_HoldingEvent>[
          ...lots.map(_LotEvent.new),
          ...splits.map(_SplitEvent.new),
        ]..sort((a, b) {
          final byDate = b.occurredAt.compareTo(a.occurredAt);
          if (byDate != 0) return byDate;
          return b.createdAt.compareTo(a.createdAt);
        });
    final isLoading = vm.isLoadingHolding(widget.holdingId);

    final position = computePosition(lots, splits: splits);
    RealizedPnL? realized;
    try {
      realized = computeRealizedPnL(lots, splits: splits);
    } on InvestmentMathException {
      realized = null;
    }
    final priceQuote = holding == null
        ? (price: null, source: 'none')
        : resolveCurrentPrice(
            holding: holding,
            marketPrice: vm.priceFor(holding.symbol, holding.exchange),
            lots: lots,
            splits: splits,
          );
    final unrealized = computeUnrealizedPnL(
      position: position,
      currentPrice: priceQuote.price,
    );
    final dividends = vm.totalDividendsFor(widget.holdingId);
    final lastDividend = vm.dividendsFor(widget.holdingId).firstOrNull;

    return Scaffold(
      appBar: AppBar(
        title: Text(holding?.symbol ?? 'Holding'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
          onPressed: () => context.pop(),
        ),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'edit') {
                _onEditHolding();
              } else if (value == 'archive') {
                _onArchiveHolding();
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'edit',
                child: Row(
                  children: [
                    Icon(Icons.edit_outlined, size: 18),
                    SizedBox(width: 12),
                    Text('Editar holding'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'archive',
                child: Row(
                  children: [
                    Icon(Icons.archive_outlined, size: 18),
                    SizedBox(width: 12),
                    Text('Archivar'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          if (holding != null)
            _HoldingSummaryCard(
              holding: holding,
              position: position,
              realizedTotal: realized?.totalRealized,
              unrealized: unrealized,
              priceQuote: priceQuote,
              dividendsByCurrency: dividends,
              lastDividend: lastDividend,
            ),
          Expanded(
            child: PpScreenState(
              isLoading: isLoading && events.isEmpty,
              isEmpty: !isLoading && events.isEmpty,
              emptyIcon: Icons.receipt_long_outlined,
              emptyLabel: 'Sin operaciones aún',
              emptySubLabel: 'Añade una compra, venta o split',
              onRefresh: _load,
              child: ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                itemCount: events.length,
                itemBuilder: (ctx, index) {
                  final ev = events[index];
                  if (ev is _LotEvent) {
                    final lot = ev.lot;
                    final account = _accountsById[lot.accountId];
                    return _LotCard(
                      lot: lot,
                      holdingCurrencyCode: holding?.currencyCode ?? '',
                      accountName: account?.name,
                      onTap: () => _onEditLot(lot),
                    );
                  }
                  final split = (ev as _SplitEvent).split;
                  return _SplitCard(
                    split: split,
                    onTap: () => _onEditSplit(split),
                  );
                },
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddLotSheet(context),
        icon: const Icon(Icons.add),
        label: const Text('Añadir operación'),
      ),
    );
  }

  void _showAddLotSheet(BuildContext context) {
    showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(ctx).colorScheme.surfaceContainerHighest,
                  borderRadius: AppTheme.radiusFull,
                ),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.arrow_downward_rounded),
                title: const Text('Añadir compra'),
                onTap: () => Navigator.pop(ctx, 'buy'),
              ),
              ListTile(
                leading: const Icon(Icons.arrow_upward_rounded),
                title: const Text('Añadir venta'),
                onTap: () => Navigator.pop(ctx, 'sell'),
              ),
              ListTile(
                leading: const Icon(Icons.call_split_rounded),
                title: const Text('Registrar split'),
                onTap: () => Navigator.pop(ctx, 'split'),
              ),
            ],
          ),
        ),
      ),
    ).then((kind) {
      if (kind == null) return;
      if (kind == 'split') {
        _onAddSplit();
      } else {
        _onAddLot(kind);
      }
    });
  }
}

/// Marker base for events shown in the holding's mixed timeline.
sealed class _HoldingEvent {
  String get occurredAt;
  DateTime get createdAt;
}

class _LotEvent implements _HoldingEvent {
  final InvestmentLotModel lot;
  _LotEvent(this.lot);
  @override
  String get occurredAt => lot.occurredAt;
  @override
  DateTime get createdAt => lot.createdAt;
}

class _SplitEvent implements _HoldingEvent {
  final InvestmentSplitModel split;
  _SplitEvent(this.split);
  @override
  String get occurredAt => split.occurredAt;
  @override
  DateTime get createdAt => split.createdAt;
}

class _HoldingSummaryCard extends StatelessWidget {
  final InvestmentHoldingModel holding;
  final Position position;
  final double? realizedTotal;
  final double unrealized;
  final PriceQuote priceQuote;
  final Map<String, double> dividendsByCurrency;
  final TransactionModel? lastDividend;

  const _HoldingSummaryCard({
    required this.holding,
    required this.position,
    required this.realizedTotal,
    required this.unrealized,
    required this.priceQuote,
    required this.dividendsByCurrency,
    required this.lastDividend,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ccy = holding.currencyCode;
    final price = priceQuote.price;
    final marketValue = (price != null && position.netQuantity > 0)
        ? price * position.netQuantity
        : null;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(16),
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
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      holding.displayName,
                      style: GoogleFonts.ibmPlexSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${holding.exchange} · ${holding.currencyCode}',
                      style: GoogleFonts.ibmPlexSans(
                        fontSize: 12,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              PriceSourceBadge(source: priceQuote.source),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _StatTile(
                  label: 'Cantidad neta',
                  value: formatQty(position.netQuantity),
                ),
              ),
              Expanded(
                child: _StatTile(
                  label: 'Costo prom.',
                  value: position.weightedAvgCost > 0
                      ? '${formatMoney(position.weightedAvgCost)} $ccy'
                      : '—',
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _StatTile(
                  label: 'Precio actual',
                  value: price == null ? '—' : '${formatMoney(price)} $ccy',
                ),
              ),
              Expanded(
                child: _StatTile(
                  label: 'Valor de mercado',
                  value: marketValue == null
                      ? '—'
                      : '${formatMoney(marketValue)} $ccy',
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _PnLTile(
                  label: 'P&L no realizado',
                  amount: unrealized,
                  currencyCode: ccy,
                  basis: position.netQuantity > 0
                      ? position.weightedAvgCost * position.netQuantity
                      : 0,
                  available: price != null && position.netQuantity > 0,
                ),
              ),
              Expanded(
                child: _PnLTile(
                  label: 'P&L realizado',
                  amount: realizedTotal ?? 0,
                  currencyCode: ccy,
                  basis: 0,
                  available: realizedTotal != null,
                ),
              ),
            ],
          ),
          if (dividendsByCurrency.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _StatTile(
                    label: 'Dividendos',
                    value: dividendsByCurrency.entries
                        .map((e) => '${formatMoney(e.value)} ${e.key}')
                        .join(' · '),
                  ),
                ),
                Expanded(
                  child: _StatTile(
                    label: 'Último dividendo',
                    value: lastDividend == null
                        ? '—'
                        : '${_formatLotDate(lastDividend!.date)} · ${formatMoney(lastDividend!.amount / 100.0)} ${lastDividend!.currencyCode}',
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  String _formatLotDate(String iso) {
    final parsed = DateTime.tryParse(iso);
    if (parsed == null) return iso;
    return formatDateDisplay(parsed);
  }
}

class _StatTile extends StatelessWidget {
  final String label;
  final String value;

  const _StatTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.ibmPlexSans(
            fontSize: 11,
            letterSpacing: 0.4,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: GoogleFonts.ibmPlexSans(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _PnLTile extends StatelessWidget {
  final String label;
  final double amount;
  final String currencyCode;
  final double basis;
  final bool available;

  const _PnLTile({
    required this.label,
    required this.amount,
    required this.currencyCode,
    required this.basis,
    required this.available,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (!available) {
      return _StatTile(label: label, value: '—');
    }
    final color = amount > 0
        ? Colors.green.shade600
        : (amount < 0 ? theme.colorScheme.error : theme.colorScheme.onSurface);
    final sign = amount > 0 ? '+' : '';
    final pct = basis > 0 ? (amount / basis) * 100 : null;
    final pctText = pct == null
        ? ''
        : ' (${amount > 0 ? '+' : ''}${pct.toStringAsFixed(2)}%)';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.ibmPlexSans(
            fontSize: 11,
            letterSpacing: 0.4,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '$sign${formatMoney(amount)} $currencyCode$pctText',
          style: GoogleFonts.ibmPlexSans(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }
}

class PriceSourceBadge extends StatelessWidget {
  final String source;

  const PriceSourceBadge({required this.source, super.key});

  @override
  Widget build(BuildContext context) {
    if (source == 'none') return const SizedBox.shrink();
    final theme = Theme.of(context);
    final (label, color) = switch (source) {
      'market' => ('Mercado', Colors.green.shade600),
      'manual' => ('Manual', Colors.orange.shade700),
      'last_lot' => ('Último lote', theme.colorScheme.onSurfaceVariant),
      _ => (source, theme.colorScheme.onSurfaceVariant),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: AppTheme.radiusFull,
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
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

String formatQty(double q) {
  if (q.isNaN || q.isInfinite) return '—';
  if (q == q.truncateToDouble()) return q.toInt().toString();
  return q.toStringAsFixed(4);
}

String formatMoney(double v) {
  return v.toStringAsFixed(2);
}

class _LotCard extends StatelessWidget {
  final InvestmentLotModel lot;
  final String holdingCurrencyCode;
  final String? accountName;
  final VoidCallback onTap;

  const _LotCard({
    required this.lot,
    required this.holdingCurrencyCode,
    required this.accountName,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isBuy = lot.isBuy;
    final color = isBuy
        ? Theme.of(context).colorScheme.error
        : Colors.green.shade600;
    final icon = isBuy
        ? Icons.arrow_downward_rounded
        : Icons.arrow_upward_rounded;
    final dateLabel = _safeDate(lot.occurredAt);
    final qty = _formatQty(lot.quantity);
    final price = lot.price.toStringAsFixed(2);

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainer,
          borderRadius: AppTheme.radiusMedium,
          border: Border.all(
            color: Theme.of(context).colorScheme.surfaceContainerHigh,
          ),
        ),
        child: ListTile(
          onTap: onTap,
          leading: CircleAvatar(
            backgroundColor: color.withValues(alpha: 0.12),
            child: Icon(icon, color: color, size: 20),
          ),
          title: Text(
            '${isBuy ? 'Compra' : 'Venta'} · $qty @ $price $holdingCurrencyCode',
            style: GoogleFonts.ibmPlexSans(
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          subtitle: Text(
            [dateLabel, ?accountName].join(' · '),
            style: GoogleFonts.ibmPlexSans(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          trailing: Icon(
            Icons.chevron_right_rounded,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            size: 20,
          ),
        ),
      ),
    );
  }

  String _formatQty(double q) {
    if (q == q.truncateToDouble()) return q.toInt().toString();
    return q.toStringAsFixed(4);
  }

  String _safeDate(String iso) {
    final parsed = DateTime.tryParse(iso);
    if (parsed == null) return iso;
    return formatDateDisplay(parsed);
  }
}

class _SplitCard extends StatelessWidget {
  final InvestmentSplitModel split;
  final VoidCallback onTap;

  const _SplitCard({required this.split, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.tertiary;
    final dateLabel = _safeDate(split.occurredAt);
    final n = _stripDouble(split.ratioNum);
    final d = _stripDouble(split.ratioDen);
    final kind = split.isReverse ? 'reverso' : 'forward';

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: AppTheme.radiusMedium,
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: ListTile(
          onTap: onTap,
          leading: CircleAvatar(
            backgroundColor: color.withValues(alpha: 0.12),
            child: Icon(Icons.call_split_rounded, color: color, size: 20),
          ),
          title: Text(
            'Split $n a $d ($kind)',
            style: GoogleFonts.ibmPlexSans(
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          subtitle: Text(
            split.notes == null || split.notes!.isEmpty
                ? dateLabel
                : '$dateLabel · ${split.notes}',
            style: GoogleFonts.ibmPlexSans(
              fontSize: 12,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          trailing: Icon(
            Icons.chevron_right_rounded,
            color: theme.colorScheme.onSurfaceVariant,
            size: 20,
          ),
        ),
      ),
    );
  }

  String _stripDouble(double v) {
    if (v == v.truncateToDouble()) return v.toInt().toString();
    return v.toStringAsFixed(4);
  }

  String _safeDate(String iso) {
    final parsed = DateTime.tryParse(iso);
    if (parsed == null) return iso;
    return formatDateDisplay(parsed);
  }
}
