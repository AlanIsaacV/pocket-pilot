import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'package:pocket_pilot/src/core/theme/app_theme.dart';
import 'package:pocket_pilot/src/features/investments/domain/investment_holding.dart';
import 'package:pocket_pilot/src/features/investments/ui/investment_view_model.dart';
import 'package:pocket_pilot/src/ui/widgets/pp_screen_state.dart';

class HoldingsListTab extends StatelessWidget {
  const HoldingsListTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<InvestmentViewModel>(
      builder: (context, vm, _) {
        final holdings = [...vm.allHoldings]
          ..sort((a, b) => a.symbol.compareTo(b.symbol));

        return Column(
          children: [
            if (vm.isSyncing && !vm.isLoadingAll)
              LinearProgressIndicator(
                color: Theme.of(context).colorScheme.primary,
                backgroundColor:
                    Theme.of(context).colorScheme.surfaceContainerHigh,
                minHeight: 2,
              ),
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
                  itemCount: holdings.length,
                  itemBuilder: (ctx, index) {
                    final holding = holdings[index];
                    return Dismissible(
                      key: ValueKey(holding.id),
                      direction: DismissDirection.endToStart,
                      background: _ArchiveBackground(),
                      confirmDismiss: (_) =>
                          _confirmArchive(ctx, holding.symbol),
                      onDismissed: (_) async {
                        await vm.archiveHolding(holding);
                        if (!ctx.mounted) return;
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Holding "${holding.symbol}" archivado',
                            ),
                          ),
                        );
                      },
                      child: _HoldingCard(
                        holding: holding,
                        onTap: () => _openHolding(ctx, holding),
                      ),
                    );
                  },
                ),
              ),
            ),
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
      context.read<InvestmentViewModel>().loadAll();
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

class _HoldingCard extends StatelessWidget {
  final InvestmentHoldingModel holding;
  final VoidCallback onTap;

  const _HoldingCard({required this.holding, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
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
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
          leading: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color:
                  Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
              borderRadius: AppTheme.radiusFull,
            ),
            child: Icon(
              Icons.stacked_line_chart_rounded,
              color: Theme.of(context).colorScheme.primary,
              size: 22,
            ),
          ),
          title: Text(
            holding.symbol,
            style: GoogleFonts.ibmPlexSans(
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          subtitle: Text(
            [
              holding.displayName,
              holding.exchange,
              holding.currencyCode,
            ].where((e) => e.isNotEmpty).join(' · '),
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
