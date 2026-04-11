// ============================================================
// AccountsScreen — Cuentas y Metas con tabs superiores
// ============================================================

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'package:pocket_pilot/src/core/theme/app_theme.dart';
import 'package:pocket_pilot/src/features/accounts/domain/account.dart';
import 'package:pocket_pilot/src/features/accounts/ui/accounts_view_model.dart';
import 'package:pocket_pilot/src/features/budgets/ui/budget_view_model.dart';
import 'package:pocket_pilot/src/features/budgets/ui/budgets_list_tab.dart';
import 'package:pocket_pilot/src/features/goals/ui/goal_view_model.dart';
import 'package:pocket_pilot/src/features/goals/ui/goals_list_tab.dart';
import 'package:pocket_pilot/src/features/transactions/ui/form_widgets.dart';
import 'package:pocket_pilot/src/ui/widgets/notification_bell.dart';
import 'package:pocket_pilot/src/ui/widgets/pp_screen_state.dart';

const _typeOrder = [
  'bank',
  'cash',
  'credit_card',
  'loan',
  'investment',
  'crypto',
  'other',
];

const _typeLabels = {
  'bank': 'Banco',
  'cash': 'Efectivo',
  'credit_card': 'Tarjeta de credito',
  'loan': 'Prestamo',
  'investment': 'Inversion',
  'crypto': 'Criptomonedas',
  'other': 'Otra cuenta',
};

const _typeIcons = {
  'bank': Icons.account_balance_outlined,
  'cash': Icons.payments_outlined,
  'credit_card': Icons.credit_card_outlined,
  'loan': Icons.request_quote_outlined,
  'investment': Icons.trending_up_rounded,
  'crypto': Icons.currency_bitcoin,
  'other': Icons.account_balance_wallet_outlined,
};

class AccountsScreen extends StatefulWidget {
  const AccountsScreen({super.key});

  @override
  State<AccountsScreen> createState() => _AccountsScreenState();
}

class _AccountsScreenState extends State<AccountsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cuentas'),
        actions: const [NotificationBell()],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Cuentas'),
            Tab(text: 'Metas'),
            Tab(text: 'Presupuestos'),
          ],
          labelStyle: GoogleFonts.ibmPlexSans(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
          unselectedLabelStyle: GoogleFonts.ibmPlexSans(
            fontSize: 14,
            fontWeight: FontWeight.w400,
          ),
          indicatorSize: TabBarIndicatorSize.label,
          dividerColor: Colors.transparent,
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _AccountsListTab(),
          const GoalsListTab(),
          const BudgetsListTab(),
        ],
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
                    color: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest,
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
                icon: Icons.account_balance_wallet_outlined,
                label: 'Nueva cuenta',
                onTap: () {
                  Navigator.of(context).pop();
                  context.push('/accounts/new').then((result) {
                    if (result == true && context.mounted) {
                      context.read<AccountsViewModel>().loadOnAppear();
                    }
                  });
                },
              ),
              SheetItem(
                icon: Icons.flag_outlined,
                label: 'Nueva meta',
                onTap: () {
                  Navigator.of(context).pop();
                  context.push('/accounts/goals/new').then((result) {
                    if (result == true && context.mounted) {
                      context.read<GoalViewModel>().loadOnAppear();
                    }
                  });
                },
              ),
              SheetItem(
                icon: Icons.pie_chart_outline_rounded,
                label: 'Nuevo presupuesto',
                onTap: () {
                  Navigator.of(context).pop();
                  context.push('/accounts/budgets/new').then((result) {
                    if (result == true && context.mounted) {
                      context.read<BudgetViewModel>().loadOnAppear();
                    }
                  });
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
// Tab de listado de cuentas (contenido original)
// ============================================================

class _AccountsListTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Consumer<AccountsViewModel>(
      builder: (context, vm, _) {
        final byType = vm.accountsByType;
        final archivedByType = vm.archivedAccountsByType;
        final hasArchived = archivedByType.isNotEmpty;

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
                errorMessage:
                    vm.accounts.isEmpty && !hasArchived
                        ? vm.errorMessage
                        : null,
                isEmpty: vm.accounts.isEmpty && !hasArchived,
                emptyIcon: Icons.account_balance_wallet_outlined,
                emptyLabel: 'No tienes cuentas aun',
                emptySubLabel: 'Presiona + para agregar una',
                onRefresh: vm.refresh,
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    // ── Active accounts grouped by type ──
                    for (final type in _typeOrder)
                      if (byType.containsKey(type)) ...[
                        _SectionHeader(
                          title: _typeLabels[type] ?? type,
                          color: Theme.of(context).colorScheme.onSurface,
                          icon: _typeIcons[type] ??
                              Icons.account_balance_wallet_outlined,
                        ),
                        SliverPadding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          sliver: SliverList(
                            delegate: SliverChildBuilderDelegate(
                              (context, index) {
                                final account = byType[type]![index];
                                return Dismissible(
                                  key: ValueKey(account.id),
                                  direction: DismissDirection.endToStart,
                                  background: _ArchiveBackground(),
                                  confirmDismiss: (_) =>
                                      _confirmArchive(context, account.name),
                                  onDismissed: (_) async {
                                    try {
                                      await vm.archiveAccount(account.id);
                                      if (!context.mounted) return;
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            'Cuenta "${account.name}" archivada',
                                          ),
                                        ),
                                      );
                                    } catch (e) {
                                      if (!context.mounted) return;
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            'No se pudo archivar la cuenta: $e',
                                          ),
                                        ),
                                      );
                                    }
                                  },
                                  child: _AccountCard(
                                    account: account,
                                    onTap: () =>
                                        _onAccountTap(context, account),
                                  ),
                                );
                              },
                              childCount: byType[type]!.length,
                            ),
                          ),
                        ),
                      ],

                    // ── Archived accounts section ──
                    if (hasArchived) ...[
                      _SectionHeader(
                        title: 'Archivadas',
                        color:
                            Theme.of(context).colorScheme.onSurfaceVariant,
                        icon: Icons.visibility_off_outlined,
                      ),
                      for (final type in _typeOrder)
                        if (archivedByType.containsKey(type)) ...[
                          _SectionHeader(
                            title: _typeLabels[type] ?? type,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                            icon: _typeIcons[type] ??
                                Icons.account_balance_wallet_outlined,
                          ),
                          SliverPadding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 16),
                            sliver: SliverList(
                              delegate: SliverChildBuilderDelegate(
                                (context, index) {
                                  final account =
                                      archivedByType[type]![index];
                                  return _ArchivedAccountCard(
                                    account: account,
                                    onRestore: () =>
                                        vm.restoreAccount(account.id),
                                  );
                                },
                                childCount: archivedByType[type]!.length,
                              ),
                            ),
                          ),
                        ],
                    ],

                    const SliverToBoxAdapter(child: SizedBox(height: 96)),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  void _onAccountTap(BuildContext context, AccountModel account) {
    context
        .push('/accounts/${account.id}/edit', extra: account)
        .then((result) {
      if (result == true && context.mounted) {
        context.read<AccountsViewModel>().loadOnAppear();
      }
    });
  }

  Future<bool?> _confirmArchive(BuildContext context, String accountName) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Archivar cuenta'),
        content: Text('Se archivara la cuenta "$accountName".'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Archivar'),
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
          color: Theme.of(context).colorScheme.surfaceContainer,
          borderRadius: AppTheme.radiusMedium,
          border: Border.all(
            color: Theme.of(context).colorScheme.surfaceContainerHigh,
            width: 1,
          ),
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
              color: Theme.of(
                context,
              ).colorScheme.primary.withValues(alpha: 0.12),
              borderRadius: AppTheme.radiusFull,
            ),
            child: Icon(
              icon,
              color: Theme.of(context).colorScheme.primary,
              size: 22,
            ),
          ),
          title: Text(
            account.name,
            style: GoogleFonts.ibmPlexSans(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          subtitle: Text(
            typeLabel,
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
      case 'contact':
        return Icons.person_outline;
      default:
        return Icons.account_balance_wallet_outlined;
    }
  }

  String _labelForType(String type) {
    switch (type) {
      case 'bank':
        return 'Banco';
      case 'credit_card':
        return 'Tarjeta de credito';
      case 'cash':
        return 'Efectivo';
      case 'investment':
        return 'Inversion';
      case 'loan':
        return 'Prestamo';
      case 'crypto':
        return 'Criptomonedas';
      case 'contact':
        return 'Contacto';
      default:
        return 'Otra cuenta';
    }
  }
}

// ============================================================
// Header de sección
// ============================================================

class _SectionHeader extends StatelessWidget {
  final String title;
  final Color color;
  final IconData icon;

  const _SectionHeader({
    required this.title,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Row(
          children: [
            Icon(icon, color: color, size: 14),
            const SizedBox(width: 6),
            Text(
              title.toUpperCase(),
              style: GoogleFonts.ibmPlexSans(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.2,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// Background de swipe "Archivar"
// ============================================================

class _ArchiveBackground extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
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

// ============================================================
// Tarjeta de cuenta archivada
// ============================================================

class _ArchivedAccountCard extends StatelessWidget {
  final AccountModel account;
  final VoidCallback onRestore;

  const _ArchivedAccountCard({
    required this.account,
    required this.onRestore,
  });

  @override
  Widget build(BuildContext context) {
    final icon = _typeIcons[account.type] ??
        Icons.account_balance_wallet_outlined;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          borderRadius: AppTheme.radiusFull,
          border: Border.all(
            color: Theme.of(context).colorScheme.surfaceContainerHigh,
            width: 1,
          ),
        ),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 2,
          ),
          leading: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHigh,
              borderRadius: AppTheme.radiusFull,
            ),
            child: Icon(
              icon,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              size: 18,
            ),
          ),
          title: Text(
            account.name,
            style: GoogleFonts.ibmPlexSans(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          trailing: TextButton(
            onPressed: onRestore,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              'RESTAURAR',
              style: GoogleFonts.ibmPlexSans(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.primary,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
