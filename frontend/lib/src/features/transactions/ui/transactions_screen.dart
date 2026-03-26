// ============================================================
// TransactionsScreen — Lista de transacciones agrupada por mes
// ============================================================

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'package:pocket_pilot/src/core/theme/app_theme.dart';
import 'package:pocket_pilot/src/features/transactions/domain/transaction.dart';
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
                  child: _TransactionList(transactions: vm.transactions),
                ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _onAddTap(context),
        tooltip: 'Agregar transacción',
        child: const Icon(Icons.add),
      ),
    );
  }

  void _onAddTap(BuildContext context) {
    context.go('/transactions/new');
  }
}

// ============================================================
// Lista con secciones por mes
// ============================================================

class _TransactionList extends StatelessWidget {
  final List<TransactionModel> transactions;

  const _TransactionList({required this.transactions});

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
            return _TransactionTile(transaction: section.value[itemIndex]);
          }
          offset += section.value.length;
        }
        return const SizedBox.shrink();
      },
    );
  }
}

// ============================================================
// Header de sección mensual
// ============================================================

class _MonthHeader extends StatelessWidget {
  final String monthKey; // "YYYY-MM"

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
      'Enero',
      'Febrero',
      'Marzo',
      'Abril',
      'Mayo',
      'Junio',
      'Julio',
      'Agosto',
      'Septiembre',
      'Octubre',
      'Noviembre',
      'Diciembre',
    ];
    return names[month - 1];
  }
}

// ============================================================
// Fila de transacción
// ============================================================

class _TransactionTile extends StatelessWidget {
  final TransactionModel transaction;

  const _TransactionTile({required this.transaction});

  @override
  Widget build(BuildContext context) {
    final isIncome = transaction.isIncome;
    final amountColor = isIncome
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.error;

    final date = transaction.parsedDate;
    final formattedDate = '${date.day} ${_monthAbbr(date.month)} ${date.year}';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainer,
          borderRadius: AppTheme.radiusMedium,
        ),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 0,
          ),
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: isIncome
                  ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.1)
                  : Theme.of(context).colorScheme.error.withValues(alpha: 0.1),
              borderRadius: AppTheme.radiusFull,
            ),
            child: Icon(
              isIncome
                  ? Icons.arrow_downward_rounded
                  : Icons.arrow_upward_rounded,
              color: amountColor,
              size: 18,
            ),
          ),
          title: Text(
            transaction.description.isNotEmpty
                ? transaction.description
                : 'Sin descripción',
            style: GoogleFonts.ibmPlexSans(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Theme.of(context).colorScheme.onSurface,
            ),
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            formattedDate,
            style: GoogleFonts.ibmPlexSans(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
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
      'ene',
      'feb',
      'mar',
      'abr',
      'may',
      'jun',
      'jul',
      'ago',
      'sep',
      'oct',
      'nov',
      'dic',
    ];
    return months[month - 1];
  }
}
