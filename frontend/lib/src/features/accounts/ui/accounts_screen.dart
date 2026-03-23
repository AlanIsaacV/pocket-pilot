// ============================================================
// AccountsScreen — Lista de cuentas bancarias / carteras
// ============================================================

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:pocket_pilot/src/features/accounts/domain/account.dart';
import 'package:pocket_pilot/src/features/accounts/ui/accounts_view_model.dart';

class AccountsScreen extends StatelessWidget {
  const AccountsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cuentas'),
      ),
      body: Consumer<AccountsViewModel>(
        builder: (context, vm, _) {
          return Column(
            children: [
              // LinearProgressIndicator sutil: visible cuando hay datos locales
              // mostrándose Y una sync remota corre en background.
              // isLoading == true significa que YA hay un spinner bloqueante abajo,
              // así que no duplicamos indicadores.
              if (vm.isSyncing && !vm.isLoading)
                const LinearProgressIndicator(),

              Expanded(
                // RefreshIndicator: detecta el gesto "pull hacia abajo".
                // onRefresh debe retornar un Future que completa cuando termina.
                // vm.refresh() ignora el throttle de 5s y siempre va al servidor.
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
              content: Text('Creación de cuentas — Próximamente'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        },
        tooltip: 'Agregar cuenta',
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildBody(BuildContext context, AccountsViewModel vm) {
    // Estado de carga inicial: no hay datos locales y la sync está corriendo.
    // LayoutBuilder + SingleChildScrollView hace que RefreshIndicator funcione
    // aunque no haya nada que scrollear (necesita un Scrollable).
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

    // Error bloqueante: la sync falló y no hay datos que mostrar.
    if (vm.accounts.isEmpty && vm.errorMessage != null) {
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
                    Text(
                      vm.errorMessage!,
                      textAlign: TextAlign.center,
                    ),
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

    // Estado vacío: sync completó pero no hay cuentas todavía.
    if (vm.accounts.isEmpty) {
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
                    Icons.account_balance_wallet_outlined,
                    size: 64,
                    color: Colors.grey,
                  ),
                  SizedBox(height: 16),
                  Text(
                    'No tienes cuentas aún',
                    style: TextStyle(color: Colors.grey),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Presiona + para agregar una',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    // Estado con datos: lista scrolleable con physics explícitas para que
    // RefreshIndicator funcione aunque la lista no llegue al borde.
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 88),
      itemCount: vm.accounts.length,
      itemBuilder: (context, index) =>
          _AccountCard(account: vm.accounts[index]),
    );
  }
}

// ============================================================
// Widget privado: tarjeta de una cuenta
// ============================================================

class _AccountCard extends StatelessWidget {
  final AccountModel account;

  const _AccountCard({required this.account});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 8,
        ),
        leading: CircleAvatar(
          backgroundColor: colorScheme.primaryContainer,
          child: Icon(
            _iconForType(account.type),
            color: colorScheme.onPrimaryContainer,
          ),
        ),
        title: Text(
          account.name,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Text(
          _labelForType(account.type),
          style: theme.textTheme.bodySmall,
        ),
        trailing: Icon(
          Icons.chevron_right,
          color: colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  IconData _iconForType(String type) {
    switch (type) {
      case 'bank':
        return Icons.account_balance_outlined;
      case 'credit_card':
        return Icons.credit_card;
      case 'cash':
        return Icons.payments_outlined;
      case 'investment':
        return Icons.trending_up;
      case 'loan':
        return Icons.request_quote_outlined;
      case 'crypto':
        return Icons.currency_bitcoin;
      default:
        return Icons.account_balance_wallet_outlined;
    }
  }

  String _labelForType(String type) {
    switch (type) {
      case 'bank':
        return 'Banco';
      case 'credit_card':
        return 'Tarjeta de crédito';
      case 'cash':
        return 'Efectivo';
      case 'investment':
        return 'Inversión';
      case 'loan':
        return 'Préstamo';
      case 'crypto':
        return 'Criptomonedas';
      default:
        return 'Otra cuenta';
    }
  }
}
