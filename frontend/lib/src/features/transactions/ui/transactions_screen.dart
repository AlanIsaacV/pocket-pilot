// ============================================================
// TransactionsScreen — Lista de transacciones agrupada por mes
// ============================================================

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'package:pocket_pilot/src/core/theme/app_theme.dart';
import 'package:pocket_pilot/src/features/transactions/domain/transaction.dart';
import 'package:pocket_pilot/src/features/transactions/ui/form_widgets.dart';
import 'package:pocket_pilot/src/features/transactions/ui/transactions_view_model.dart';
import 'package:pocket_pilot/src/ui/widgets/pp_screen_state.dart';

class TransactionsScreen extends StatelessWidget {
  const TransactionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Transacciones')),
      body: Consumer<TransactionsViewModel>(
        builder: (context, vm, _) {
          return Column(
            children: [
              if (vm.isSyncing && !vm.isLoading)
                LinearProgressIndicator(
                  color: Theme.of(context).colorScheme.primary,
                  backgroundColor: Theme.of(
                    context,
                  ).colorScheme.surfaceContainer,
                  minHeight: 2,
                ),
              Expanded(
                child: PpScreenState(
                  isLoading: vm.isLoading,
                  errorMessage: vm.transactions.isEmpty
                      ? vm.errorMessage
                      : null,
                  isEmpty: vm.transactions.isEmpty,
                  emptyIcon: Icons.receipt_long_outlined,
                  emptyLabel: 'No hay transacciones aún',
                  emptySubLabel: 'Presiona + para registrar una',
                  onRefresh: vm.refresh,
                  child: _TransactionList(transactions: vm.transactions, vm: vm),
                ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddOptions(context),
        tooltip: 'Agregar',
        child: const Icon(Icons.add),
      ),
    );
  }

  void _showAddOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: AppTheme.radiusFull,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Nuevo registro',
                style: GoogleFonts.ibmPlexSans(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              SheetItem(
                icon: Icons.receipt_long_outlined,
                label: 'Nueva transacción',
                onTap: () {
                  Navigator.of(context).pop();
                  context.go('/transactions/new');
                },
              ),
              SheetItem(
                icon: Icons.swap_horiz_rounded,
                label: 'Nueva transferencia',
                onTap: () {
                  Navigator.of(context).pop();
                  context.go('/transactions/transfer');
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// Lista con secciones por mes
// ============================================================

class _TransactionList extends StatelessWidget {
  final List<TransactionModel> transactions;
  final TransactionsViewModel vm;

  const _TransactionList({required this.transactions, required this.vm});

  @override
  Widget build(BuildContext context) {
    // Agrupa por "YYYY-MM" manteniendo el orden.
    final groups = <String, List<TransactionModel>>{};
    for (final t in transactions) {
      final key =
          '${t.parsedDate.year}-${t.parsedDate.month.toString().padLeft(2, '0')}';
      groups.putIfAbsent(key, () => []).add(t);
    }

    final sections = groups.entries.toList();

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 96),
      itemCount: sections.fold<int>(0, (sum, e) => sum + 1 + e.value.length),
      itemBuilder: (context, index) {
        int offset = 0;
        for (final section in sections) {
          if (index == offset) {
            return _MonthHeader(monthKey: section.key);
          }
          offset++;
          final itemIndex = index - offset;
          if (itemIndex < section.value.length) {
            final t = section.value[itemIndex];
            return Dismissible(
              key: ValueKey(t.id),
              direction: DismissDirection.endToStart,
              background: _DeleteBackground(),
              confirmDismiss: (_) => _confirmDelete(context, t),
              onDismissed: (_) async {
                try {
                  await vm.deleteTransaction(
                    t.id,
                    linkedTransactionId: t.linkedTransactionId,
                  );
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          t.isTransfer
                              ? 'Transferencia eliminada'
                              : 'Transacción eliminada',
                        ),
                      ),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('No se pudo eliminar: $e')),
                    );
                  }
                }
              },
              child: _TransactionTile(
                transaction: t,
                onTap: () {
                  if (t.isTransfer) {
                    _openTransferEdit(context, t);
                  } else {
                    context
                        .push('/transactions/${t.id}/edit', extra: t)
                        .then((result) {
                      if (result == true && context.mounted) {
                        vm.loadOnAppear();
                      }
                    });
                  }
                },
              ),
            );
          }
          offset += section.value.length;
        }
        return const SizedBox.shrink();
      },
    );
  }

  void _openTransferEdit(BuildContext context, TransactionModel t) {
    final linked = t.linkedTransactionId != null
        ? vm.findLinked(t.linkedTransactionId!)
        : null;

    // Determine which is out and which is in.
    final TransactionModel? outLeg;
    final TransactionModel? inLeg;
    if (t.isTransferOut) {
      outLeg = t;
      inLeg = linked;
    } else {
      outLeg = linked;
      inLeg = t;
    }

    if (outLeg != null && inLeg != null) {
      context
          .push(
            '/transactions/${t.id}/edit-transfer',
            extra: {'out': outLeg, 'in': inLeg},
          )
          .then((result) {
        if (result == true && context.mounted) {
          vm.loadOnAppear();
        }
      });
    }
  }
}

// ============================================================
// Header de sección mensual
// ============================================================

class _MonthHeader extends StatelessWidget {
  final String monthKey;

  const _MonthHeader({required this.monthKey});

  @override
  Widget build(BuildContext context) {
    final parts = monthKey.split('-');
    final year = int.parse(parts[0]);
    final month = int.parse(parts[1]);
    final label = '${_monthName(month)} $year';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        label.toUpperCase(),
        style: GoogleFonts.ibmPlexSans(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.2,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  String _monthName(int month) {
    const names = [
      'Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio',
      'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre',
    ];
    return names[month - 1];
  }
}

// ============================================================
// Fila de transacción
// ============================================================

class _TransactionTile extends StatelessWidget {
  final TransactionModel transaction;
  final VoidCallback onTap;

  const _TransactionTile({required this.transaction, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final Color iconBgColor;
    final Color amountColor;
    final IconData icon;

    if (transaction.isTransfer) {
      iconBgColor = cs.secondary.withValues(alpha: 0.1);
      amountColor = transaction.isTransferIn ? cs.primary : cs.onSurfaceVariant;
      icon = Icons.swap_horiz_rounded;
    } else if (transaction.isIncome) {
      iconBgColor = cs.primary.withValues(alpha: 0.1);
      amountColor = cs.primary;
      icon = Icons.arrow_downward_rounded;
    } else {
      iconBgColor = cs.error.withValues(alpha: 0.1);
      amountColor = cs.error;
      icon = Icons.arrow_upward_rounded;
    }

    final date = transaction.parsedDate;
    final formattedDate = '${date.day} ${_monthAbbr(date.month)} ${date.year}';

    final subtitle = transaction.isTransfer
        ? 'Transferencia · $formattedDate'
        : formattedDate;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
      child: Container(
        decoration: BoxDecoration(
          color: cs.surfaceContainer,
          borderRadius: AppTheme.radiusMedium,
        ),
        child: ListTile(
          onTap: onTap,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 0,
          ),
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: iconBgColor,
              borderRadius: AppTheme.radiusFull,
            ),
            child: Icon(icon, color: amountColor, size: 18),
          ),
          title: Text(
            transaction.description.isNotEmpty
                ? transaction.description
                : 'Sin descripción',
            style: GoogleFonts.ibmPlexSans(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: cs.onSurface,
            ),
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            subtitle,
            style: GoogleFonts.ibmPlexSans(
              fontSize: 12,
              color: cs.onSurfaceVariant,
            ),
          ),
          trailing: Text(
            transaction.formattedAmount,
            style: GoogleFonts.ibmPlexSans(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: amountColor,
            ),
          ),
        ),
      ),
    );
  }

  String _monthAbbr(int month) {
    const months = [
      'ene', 'feb', 'mar', 'abr', 'may', 'jun',
      'jul', 'ago', 'sep', 'oct', 'nov', 'dic',
    ];
    return months[month - 1];
  }
}

// ============================================================
// Helpers de eliminación
// ============================================================

Future<bool?> _confirmDelete(BuildContext context, TransactionModel t) {
  final isTransfer = t.isTransfer;
  final label = t.description.isNotEmpty ? '"${t.description}"' : 'esta transacción';
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(isTransfer ? 'Eliminar transferencia' : 'Eliminar transacción'),
      content: Text(
        isTransfer
            ? 'Se eliminará esta transferencia completa (ambos movimientos).'
            : 'Se eliminará $label.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(ctx).colorScheme.error,
          ),
          child: const Text('Eliminar'),
        ),
      ],
    ),
  );
}

class _DeleteBackground extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.error.withValues(alpha: 0.18),
        borderRadius: AppTheme.radiusMedium,
        border: Border.all(
          color: Theme.of(context).colorScheme.error.withValues(alpha: 0.5),
        ),
      ),
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Eliminar',
            style: GoogleFonts.ibmPlexSans(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.error,
            ),
          ),
          const SizedBox(width: 6),
          Icon(
            Icons.delete_outline_rounded,
            color: Theme.of(context).colorScheme.error,
          ),
        ],
      ),
    );
  }
}
