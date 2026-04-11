import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'package:pocket_pilot/src/core/theme/app_theme.dart';
import 'package:pocket_pilot/src/features/debts/domain/contact_balance.dart';
import 'package:pocket_pilot/src/features/debts/ui/debt_view_model.dart';
import 'package:pocket_pilot/src/ui/widgets/pp_screen_state.dart';

class DebtsListTab extends StatelessWidget {
  const DebtsListTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<DebtViewModel>(
      builder: (context, vm, _) {
        final active = vm.activeContacts;
        final settled = vm.settledContacts;
        final forgiven = vm.forgivenContacts;

        return Column(
          children: [
            if (vm.isSyncing && !vm.isLoading)
              LinearProgressIndicator(
                color: Theme.of(context).colorScheme.primary,
                backgroundColor: Theme.of(
                  context,
                ).colorScheme.surfaceContainerHigh,
                minHeight: 2,
              ),
            Expanded(
              child: PpScreenState(
                isLoading: vm.isLoading,
                errorMessage: vm.contacts.isEmpty ? vm.errorMessage : null,
                isEmpty: vm.contacts.isEmpty,
                emptyIcon: Icons.group_outlined,
                emptyLabel: 'No tienes deudas registradas',
                emptySubLabel: 'Presiona + y elige Agregar deuda',
                onRefresh: vm.refresh,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                  children: [
                    if (active.isNotEmpty) ...[
                      _SectionHeader(
                        title: 'Deudas activas',
                        count: active.length,
                      ),
                      ...active.map((c) => _DebtCard(contact: c)),
                    ],
                    if (settled.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      _SectionHeader(title: 'Saldadas', count: settled.length),
                      ...settled.map(
                        (c) => Opacity(
                          opacity: 0.75,
                          child: _DebtCard(contact: c),
                        ),
                      ),
                    ],
                    if (forgiven.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      _SectionHeader(
                        title: 'Perdonadas',
                        count: forgiven.length,
                      ),
                      ...forgiven.map(
                        (c) => Opacity(
                          opacity: 0.55,
                          child: _DebtCard(contact: c),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final int count;

  const _SectionHeader({required this.title, required this.count});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, top: 4),
      child: Row(
        children: [
          Text(
            title,
            style: GoogleFonts.ibmPlexSans(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHigh,
              borderRadius: AppTheme.radiusFull,
            ),
            child: Text(
              '$count',
              style: GoogleFonts.ibmPlexSans(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DebtCard extends StatelessWidget {
  final ContactBalance contact;

  const _DebtCard({required this.contact});

  @override
  Widget build(BuildContext context) {
    final subtitle = _buildSubtitle();

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: AppTheme.radiusMedium,
        onTap: () {
          context
              .push('/transactions/debts/${contact.accountId}', extra: contact)
              .then((result) {
                if (result == true && context.mounted) {
                  context.read<DebtViewModel>().refresh();
                }
              });
        },
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainer,
            borderRadius: AppTheme.radiusMedium,
            border: Border.all(
              color: Theme.of(context).colorScheme.surfaceContainerHigh,
              width: 1,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.primary.withValues(alpha: 0.12),
                  borderRadius: AppTheme.radiusFull,
                ),
                child: Icon(
                  Icons.person_outline,
                  color: Theme.of(context).colorScheme.primary,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      contact.contactName,
                      style: GoogleFonts.ibmPlexSans(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: GoogleFonts.ibmPlexSans(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 10),
                    ...contact.balances.map(
                      (b) => _CurrencyBalanceLine(balance: b),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _buildSubtitle() {
    if (contact.isDeleted) {
      return 'Perdonada';
    }

    final primaryActive = contact.primaryActiveBalance;
    if (primaryActive == null) {
      return 'Sin deuda activa';
    }

    final origin = primaryActive.debtOriginDate;
    if (origin == null) {
      return 'Deuda activa';
    }

    return 'Desde ${_formatDate(origin)}';
  }

  static String _formatDate(String isoDate) {
    try {
      final date = DateTime.parse(isoDate);
      final months = [
        '',
        'Ene',
        'Feb',
        'Mar',
        'Abr',
        'May',
        'Jun',
        'Jul',
        'Ago',
        'Sep',
        'Oct',
        'Nov',
        'Dic',
      ];
      return '${date.day} ${months[date.month]} ${date.year}';
    } catch (_) {
      return isoDate;
    }
  }
}

class _CurrencyBalanceLine extends StatelessWidget {
  final ContactCurrencyBalance balance;

  const _CurrencyBalanceLine({required this.balance});

  @override
  Widget build(BuildContext context) {
    final isPositive = balance.balanceCents > 0;
    final isZero = balance.balanceCents == 0;
    final absAmount = balance.balanceCents.abs() / 100;
    final amountText = isZero
        ? '\$0'
        : '${isPositive ? '+' : '-'}\$${_formatMoney(absAmount)}';

    final statusText = isZero
        ? 'Saldada'
        : isPositive
        ? 'Te debe'
        : 'Le debes';

    final color = isZero
        ? Theme.of(context).colorScheme.onSurfaceVariant
        : isPositive
        ? const Color(0xFF43A047)
        : Theme.of(context).colorScheme.error;

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${balance.currencyCode} · $statusText',
              style: GoogleFonts.ibmPlexSans(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Text(
            amountText,
            style: GoogleFonts.ibmPlexSans(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  static String _formatMoney(double amount) {
    if (amount == amount.truncateToDouble()) {
      return amount.toInt().toString();
    }
    return amount.toStringAsFixed(2);
  }
}
