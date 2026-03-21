// ============================================================
// TransactionsScreen — Lista de transacciones
// ============================================================

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:pocket_pilot/src/features/transactions/domain/transaction.dart';
import 'package:pocket_pilot/src/features/transactions/ui/transactions_view_model.dart';

class TransactionsScreen extends StatelessWidget {
  const TransactionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Transacciones'),
      ),
      body: Consumer<TransactionsViewModel>(
        builder: (context, vm, _) {
          return Column(
            children: [
              if (vm.isSyncing && !vm.isLoading)
                const LinearProgressIndicator(),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: vm.refresh,
                  child: _buildBody(context, vm),
                ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Registro de transacciones — Próximamente'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        },
        tooltip: 'Agregar transacción',
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildBody(BuildContext context, TransactionsViewModel vm) {
    if (vm.isLoading) {
      return LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: SizedBox(
            height: constraints.maxHeight,
            child: const Center(child: CircularProgressIndicator()),
          ),
        ),
      );
    }

    if (vm.transactions.isEmpty && vm.errorMessage != null) {
      return LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: SizedBox(
            height: constraints.maxHeight,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline, size: 48),
                    const SizedBox(height: 16),
                    Text(vm.errorMessage!, textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    const Text(
                      'Desliza hacia abajo para reintentar',
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    if (vm.transactions.isEmpty) {
      return LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: SizedBox(
            height: constraints.maxHeight,
            child: const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.receipt_long_outlined,
                    size: 64,
                    color: Colors.grey,
                  ),
                  SizedBox(height: 16),
                  Text(
                    'No hay transacciones aún',
                    style: TextStyle(color: Colors.grey),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Presiona + para registrar una',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 88),
      itemCount: vm.transactions.length,
      itemBuilder: (context, index) =>
          _TransactionTile(transaction: vm.transactions[index]),
    );
  }
}

// ============================================================
// Widget privado: fila de una transacción
// ============================================================

class _TransactionTile extends StatelessWidget {
  final TransactionModel transaction;

  const _TransactionTile({required this.transaction});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final amountColor =
        transaction.isIncome ? Colors.green.shade700 : colorScheme.error;

    final date = transaction.parsedDate;
    final formattedDate = '${date.day} ${_monthAbbr(date.month)} ${date.year}';

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      leading: CircleAvatar(
        backgroundColor: transaction.isIncome
            ? Colors.green.shade50
            : colorScheme.errorContainer,
        child: Icon(
          transaction.isIncome ? Icons.arrow_downward : Icons.arrow_upward,
          color: amountColor,
          size: 20,
        ),
      ),
      title: Text(
        transaction.description.isNotEmpty
            ? transaction.description
            : 'Sin descripción',
        style: theme.textTheme.bodyLarge,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        formattedDate,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: Text(
        transaction.formattedAmount,
        style: theme.textTheme.titleMedium?.copyWith(
          color: amountColor,
          fontWeight: FontWeight.bold,
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
