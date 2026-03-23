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
      appBar: AppBar(
        title: const Text('Cuentas'),
      ),
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
                  errorMessage:
                      vm.accounts.isEmpty ? vm.errorMessage : null,
                  isEmpty: vm.accounts.isEmpty,
                  emptyIcon: Icons.account_balance_wallet_outlined,
                  emptyLabel: 'No tienes cuentas aún',
                  emptySubLabel: 'Presiona + para agregar una',
                  onRefresh: vm.refresh,
                  child: ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                    itemCount: vm.accounts.length,
                    itemBuilder: (context, index) =>
                        _AccountCard(account: vm.accounts[index]),
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
    context.go('/accounts/new');
  }
}

// ============================================================
// Tarjeta de cuenta
// ============================================================

class _AccountCard extends StatelessWidget {
  final AccountModel account;

  const _AccountCard({required this.account});

  @override
  Widget build(BuildContext context) {
    final icon = _iconForType(account.type);
    final typeLabel = _labelForType(account.type);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surfaceDark,
          borderRadius: AppTheme.radiusSmall,
          border: Border.all(
            color: AppColors.surfaceElevatedDark,
            width: 1,
          ),
        ),
        child: ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          leading: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              borderRadius: AppTheme.radiusSmall,
            ),
            child: Icon(icon, color: AppColors.primary, size: 22),
          ),
          title: Text(
            account.name,
            style: GoogleFonts.outfit(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimaryDark,
            ),
          ),
          subtitle: Text(
            typeLabel,
            style: GoogleFonts.inter(
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
