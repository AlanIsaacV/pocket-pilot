import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'package:pocket_pilot/src/core/theme/app_theme.dart';
import 'package:pocket_pilot/src/features/accounts/data/account_local_store.dart';
import 'package:pocket_pilot/src/features/accounts/domain/account.dart';
import 'package:pocket_pilot/src/features/investments/domain/investment_holding.dart';
import 'package:pocket_pilot/src/features/investments/domain/investment_lot.dart';
import 'package:pocket_pilot/src/features/investments/ui/investment_view_model.dart';
import 'package:pocket_pilot/src/features/transactions/ui/form_date_utils.dart';
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

    await vm.loadHolding(widget.holdingId);
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

  void _onEditHolding() {
    final holding = _holding;
    if (holding == null) return;
    context
        .push(
          '/accounts/holdings/${widget.holdingId}/edit',
          extra: holding,
        )
        .then((_) => _load());
  }

  Future<void> _onArchiveHolding() async {
    final holding = _holding;
    if (holding == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Archivar holding'),
        content: Text(
          'Se archivará el holding "${holding.symbol}" y todas sus operaciones.',
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
    if (confirm != true || !mounted) return;

    await context.read<InvestmentViewModel>().archiveHolding(holding);
    if (!mounted) return;
    context.pop(true);
  }

  Map<String, double> _computePosition(List<InvestmentLotModel> lots) {
    double buys = 0;
    double sells = 0;
    double costBuys = 0;
    for (final lot in lots) {
      if (lot.isBuy) {
        buys += lot.quantity;
        costBuys += lot.quantity * lot.price;
      } else {
        sells += lot.quantity;
      }
    }
    final net = buys - sells;
    final weightedAvg = buys > 0 ? costBuys / buys : 0.0;
    return {'net': net, 'weightedAvg': weightedAvg};
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<InvestmentViewModel>();
    final holding = _holding;
    final lots = vm.lotsFor(widget.holdingId);
    final sortedLots = [...lots]
      ..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
    final isLoading = vm.isLoadingHolding(widget.holdingId);

    final stats = _computePosition(lots);

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
          if (holding != null) _HoldingSummary(holding: holding, stats: stats),
          Expanded(
            child: PpScreenState(
              isLoading: isLoading && lots.isEmpty,
              isEmpty: !isLoading && lots.isEmpty,
              emptyIcon: Icons.receipt_long_outlined,
              emptyLabel: 'Sin operaciones aún',
              emptySubLabel: 'Añade una compra o venta',
              onRefresh: _load,
              child: ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                itemCount: sortedLots.length,
                itemBuilder: (ctx, index) {
                  final lot = sortedLots[index];
                  final account = _accountsById[lot.accountId];
                  return _LotCard(
                    lot: lot,
                    holdingCurrencyCode: holding?.currencyCode ?? '',
                    accountName: account?.name,
                    onTap: () => _onEditLot(lot),
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
            ],
          ),
        ),
      ),
    ).then((kind) {
      if (kind != null) _onAddLot(kind);
    });
  }
}

class _HoldingSummary extends StatelessWidget {
  final InvestmentHoldingModel holding;
  final Map<String, double> stats;

  const _HoldingSummary({required this.holding, required this.stats});

  @override
  Widget build(BuildContext context) {
    final net = stats['net'] ?? 0.0;
    final avg = stats['weightedAvg'] ?? 0.0;
    final theme = Theme.of(context);

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
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _StatTile(
                  label: 'Cantidad neta',
                  value: _formatQty(net),
                ),
              ),
              Expanded(
                child: _StatTile(
                  label: 'Costo prom.',
                  value: avg > 0
                      ? '${avg.toStringAsFixed(2)} ${holding.currencyCode}'
                      : '—',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatQty(double q) {
    if (q == q.truncateToDouble()) return q.toInt().toString();
    return q.toStringAsFixed(4);
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
    final color =
        isBuy ? Theme.of(context).colorScheme.error : Colors.green.shade600;
    final icon =
        isBuy ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded;
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
            [
              dateLabel,
              ?accountName,
            ].join(' · '),
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
