import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'package:pocket_pilot/src/core/theme/app_theme.dart';
import 'package:pocket_pilot/src/features/debts/data/debt_repository.dart';
import 'package:pocket_pilot/src/features/debts/domain/contact_balance.dart';
import 'package:pocket_pilot/src/features/debts/ui/debt_view_model.dart';
import 'package:pocket_pilot/src/features/transactions/domain/transaction.dart';

class DebtDetailScreen extends StatefulWidget {
  final String accountId;
  final ContactBalance? initialContact;

  const DebtDetailScreen({
    required this.accountId,
    this.initialContact,
    super.key,
  });

  @override
  State<DebtDetailScreen> createState() => _DebtDetailScreenState();
}

class _DebtDetailScreenState extends State<DebtDetailScreen> {
  ContactBalance? _contact;
  List<TransactionModel>? _transactions;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _contact = widget.initialContact;
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
  }

  Future<void> _loadData() async {
    final repo = context.read<DebtRepository>();
    final vm = context.read<DebtViewModel>();

    final contact =
        await repo.getContactBalanceByAccountId(widget.accountId) ??
        vm.getContactByAccountId(widget.accountId) ??
        _contact;
    final txns = await repo.getContactTransactions(widget.accountId);

    if (!mounted) return;
    setState(() {
      _contact = contact;
      _transactions = txns;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = _contact;

    return Scaffold(
      appBar: AppBar(
        title: Text(c?.contactName ?? 'Detalle de deuda'),
        actions: [
          if (c != null && !c.isDeleted)
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'forgive') {
                  _forgiveDebt();
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'forgive',
                  child: Row(
                    children: [
                      Icon(Icons.volunteer_activism_outlined, size: 20),
                      SizedBox(width: 12),
                      Text('Perdonar deuda'),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
      body: _isLoading
          ? Center(
              child: CircularProgressIndicator(
                color: Theme.of(context).colorScheme.primary,
                strokeWidth: 2,
              ),
            )
          : c == null
          ? Center(
              child: Text(
                'No se encontró el contacto',
                style: GoogleFonts.ibmPlexSans(
                  fontSize: 14,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              children: [
                _BalanceCard(contact: c),
                const SizedBox(height: 24),
                Text(
                  'Historial',
                  style: GoogleFonts.ibmPlexSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                if (_transactions == null || _transactions!.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 32),
                    child: Center(
                      child: Text(
                        'Sin transacciones',
                        style: GoogleFonts.ibmPlexSans(
                          fontSize: 14,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  )
                else
                  ..._transactions!.map((txn) => _TransactionTile(txn: txn)),
              ],
            ),
      floatingActionButton: c != null && !c.isDeleted
          ? FloatingActionButton(
              onPressed: () {
                final vm = context.read<DebtViewModel>();
                context.push('/accounts/debts/new', extra: c).then((
                  result,
                ) async {
                  if (result == true && mounted) {
                    await _loadData();
                    if (mounted) {
                      vm.loadOnAppear();
                    }
                  }
                });
              },
              tooltip: 'Registrar movimiento',
              child: const Icon(Icons.add),
            )
          : null,
    );
  }

  Future<void> _forgiveDebt() async {
    final contact = _contact;
    if (contact == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Perdonar deuda'),
        content: Text(
          'Se eliminará la cuenta de "${contact.contactName}" y la deuda se considerará perdonada.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Perdonar'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final repo = context.read<DebtRepository>();
    await repo.forgiveDebt(contact.accountId);
    if (!mounted) return;
    context.read<DebtViewModel>().loadOnAppear();
    context.pop(true);
  }
}

class _BalanceCard extends StatelessWidget {
  final ContactBalance contact;

  const _BalanceCard({required this.contact});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainer,
        borderRadius: AppTheme.radiusMedium,
        border: Border.all(
          color: Theme.of(context).colorScheme.surfaceContainerHigh,
          width: 1,
        ),
      ),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.primary.withValues(alpha: 0.12),
              borderRadius: AppTheme.radiusFull,
            ),
            child: Icon(
              Icons.person_outline,
              color: Theme.of(context).colorScheme.primary,
              size: 28,
            ),
          ),
          const SizedBox(height: 14),
          ...contact.balances.map((balance) {
            final isPositive = balance.balanceCents > 0;
            final isZero = balance.balanceCents == 0;
            final absAmount = balance.balanceCents.abs() / 100;
            final amountColor = isZero
                ? Theme.of(context).colorScheme.onSurfaceVariant
                : isPositive
                ? const Color(0xFF43A047)
                : Theme.of(context).colorScheme.error;
            final statusLabel = isZero
                ? 'Saldada'
                : isPositive
                ? 'Te debe'
                : 'Le debes';

            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                children: [
                  Text(
                    isZero
                        ? '\$0'
                        : '${isPositive ? '+' : '-'}\$${_formatMoney(absAmount)}',
                    style: GoogleFonts.ibmPlexSans(
                      fontSize: 24,
                      fontWeight: FontWeight.w600,
                      color: amountColor,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${balance.currencyCode} · $statusLabel',
                    style: GoogleFonts.ibmPlexSans(
                      fontSize: 13,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (balance.debtOriginDate != null)
                    Text(
                      'Desde ${_formatDate(balance.debtOriginDate!)}',
                      style: GoogleFonts.ibmPlexSans(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
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

  static String _formatMoney(double amount) {
    if (amount == amount.truncateToDouble()) {
      return amount.toInt().toString();
    }
    return amount.toStringAsFixed(2);
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

class _TransactionTile extends StatelessWidget {
  final TransactionModel txn;

  const _TransactionTile({required this.txn});

  @override
  Widget build(BuildContext context) {
    final (icon, label, isIncoming) = _txnMeta(txn.type);
    final amount = txn.amount / 100;

    final amountColor = isIncoming
        ? const Color(0xFF43A047)
        : Theme.of(context).colorScheme.error;

    return Container(
      margin: const EdgeInsets.only(bottom: 1),
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Theme.of(
              context,
            ).colorScheme.surfaceContainerHigh.withValues(alpha: 0.5),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHigh,
              borderRadius: AppTheme.radiusSmall,
            ),
            child: Icon(icon, size: 18, color: amountColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.ibmPlexSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                if (txn.description.isNotEmpty)
                  Text(
                    txn.description,
                    style: GoogleFonts.ibmPlexSans(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                Text(
                  _formatDate(txn.date),
                  style: GoogleFonts.ibmPlexSans(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Text(
            '${isIncoming ? '+' : '-'}\$${_formatMoney(amount)} ${txn.currencyCode}',
            style: GoogleFonts.ibmPlexSans(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: amountColor,
            ),
          ),
        ],
      ),
    );
  }

  static (IconData, String, bool) _txnMeta(String type) {
    switch (type) {
      case 'transfer_in':
        return (Icons.arrow_downward_rounded, 'Transferencia recibida', true);
      case 'transfer_out':
        return (Icons.arrow_upward_rounded, 'Transferencia enviada', false);
      case 'expense':
        return (Icons.receipt_long_outlined, 'Gasto', false);
      case 'income':
        return (Icons.arrow_downward_rounded, 'Ingreso', true);
      default:
        return (Icons.swap_horiz_rounded, type, true);
    }
  }

  static String _formatMoney(double amount) {
    if (amount == amount.truncateToDouble()) {
      return amount.toInt().toString();
    }
    return amount.toStringAsFixed(2);
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
