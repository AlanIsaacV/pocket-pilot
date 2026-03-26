// ============================================================
// AccountsScreen — Lista de cuentas bancarias / carteras
// ============================================================

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'package:pocket_pilot/src/core/theme/app_colors.dart';
import 'package:pocket_pilot/src/core/theme/app_theme.dart';
import 'package:pocket_pilot/src/features/accounts/domain/account.dart';
import 'package:pocket_pilot/src/features/accounts/ui/accounts_view_model.dart';
import 'package:pocket_pilot/src/ui/widgets/pp_screen_state.dart';

class AccountsScreen extends StatelessWidget {
  const AccountsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cuentas')),
      body: Consumer<AccountsViewModel>(
        builder: (context, vm, _) {
          return Column(
            children: [
              if (vm.isSyncing && !vm.isLoading)
                LinearProgressIndicator(
                  color: AppColors.primary,
                  backgroundColor: AppColors.surfaceElevatedDark,
                  minHeight: 2,
                ),
              Expanded(
                child: PpScreenState(
                  isLoading: vm.isLoading,
                  errorMessage: vm.accounts.isEmpty ? vm.errorMessage : null,
                  isEmpty: vm.accounts.isEmpty,
                  emptyIcon: Icons.account_balance_wallet_outlined,
                  emptyLabel: 'No tienes cuentas aún',
                  emptySubLabel: 'Presiona + para agregar una',
                  onRefresh: vm.refresh,
                  child: ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                    itemCount: vm.accounts.length,
                    itemBuilder: (context, index) {
                      final account = vm.accounts[index];
                      return Dismissible(
                        key: ValueKey(account.id),
                        direction: DismissDirection.endToStart,
                        background: _DeleteBackground(),
                        confirmDismiss: (_) =>
                            _confirmDelete(context, account.name),
                        onDismissed: (_) async {
                          try {
                            await vm.deleteAccount(account.id);
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Cuenta "${account.name}" eliminada',
                                ),
                              ),
                            );
                          } catch (e) {
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'No se pudo eliminar la cuenta: $e',
                                ),
                              ),
                            );
                          }
                        },
                        child: _AccountCard(
                          account: account,
                          onTap: () => _onAccountTap(context, account),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _onAddTap(context),
        tooltip: 'Agregar cuenta',
        child: const Icon(Icons.add),
      ),
    );
  }

  void _onAddTap(BuildContext context) {
    context.push('/accounts/new').then((result) {
      if (result == true && context.mounted) {
        context.read<AccountsViewModel>().loadOnAppear();
      }
    });
  }

  void _onAccountTap(BuildContext context, AccountModel account) {
    context.push('/accounts/${account.id}/edit', extra: account).then((result) {
      if (result == true && context.mounted) {
        context.read<AccountsViewModel>().loadOnAppear();
      }
    });
  }

  Future<bool?> _confirmDelete(BuildContext context, String accountName) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar cuenta'),
        content: Text('Se eliminará la cuenta "$accountName".'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// Tarjeta de cuenta
// ============================================================

class _AccountCard extends StatelessWidget {
  final AccountModel account;
  final VoidCallback onTap;

  const _AccountCard({required this.account, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final icon = _iconForType(account.type);
    final typeLabel = _labelForType(account.type);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerDark,
          borderRadius: AppTheme.radiusMedium,
          border: Border.all(color: AppColors.surfaceElevatedDark, width: 1),
        ),
        child: ListTile(
          onTap: onTap,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 0,
          ),
          leading: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              borderRadius: AppTheme.radiusFull,
            ),
            child: Icon(icon, color: AppColors.primary, size: 22),
          ),
          title: Text(
            account.name,
            style: GoogleFonts.ibmPlexSans(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimaryDark,
            ),
          ),
          subtitle: Text(
            typeLabel,
            style: GoogleFonts.ibmPlexSans(
              fontSize: 12,
              color: AppColors.textMutedDark,
            ),
          ),
          trailing: Icon(
            Icons.chevron_right_rounded,
            color: AppColors.textMutedDark,
            size: 20,
          ),
        ),
      ),
    );
  }

  IconData _iconForType(String type) {
    switch (type) {
      case 'bank':
        return Icons.account_balance_outlined;
      case 'credit_card':
        return Icons.credit_card_outlined;
      case 'cash':
        return Icons.payments_outlined;
      case 'investment':
        return Icons.trending_up_rounded;
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

class _DeleteBackground extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.18),
        borderRadius: AppTheme.radiusMedium,
        border: Border.all(color: AppColors.error.withValues(alpha: 0.5)),
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
              color: AppColors.error,
            ),
          ),
          const SizedBox(width: 6),
          const Icon(Icons.delete_outline_rounded, color: AppColors.error),
        ],
      ),
    );
  }
}
