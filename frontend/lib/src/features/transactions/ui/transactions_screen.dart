// ============================================================
// TransactionsScreen — Transacciones, Plantillas, Rendimientos y Deudas con tabs
// ============================================================

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'package:pocket_pilot/src/core/db/database_helper.dart';
import 'package:pocket_pilot/src/features/accounts/data/account_local_store.dart';
import 'package:pocket_pilot/src/features/accounts/domain/account.dart';
import 'package:pocket_pilot/src/features/categories/data/category_local_store.dart';
import 'package:pocket_pilot/src/features/categories/domain/category.dart';
import 'package:pocket_pilot/src/features/categories/ui/category_icon_data.dart';
import 'package:pocket_pilot/src/core/theme/app_theme.dart';
import 'package:pocket_pilot/src/features/transaction_templates/ui/transaction_template_view_model.dart';
import 'package:pocket_pilot/src/features/transaction_templates/ui/transaction_templates_list_tab.dart';
import 'package:pocket_pilot/src/features/transactions/domain/transaction.dart';
import 'package:pocket_pilot/src/features/transactions/ui/form_widgets.dart';
import 'package:pocket_pilot/src/features/transactions/ui/transaction_filter_view_model.dart';
import 'package:pocket_pilot/src/features/transactions/ui/transactions_view_model.dart';
import 'package:pocket_pilot/src/features/transactions/ui/widgets/filter_sheet.dart';
import 'package:pocket_pilot/src/features/yield_configs/ui/yield_config_view_model.dart';
import 'package:pocket_pilot/src/features/yield_configs/ui/yield_configs_list_tab.dart';
import 'package:pocket_pilot/src/features/debts/ui/debt_view_model.dart';
import 'package:pocket_pilot/src/features/debts/ui/debts_list_tab.dart';
import 'package:pocket_pilot/src/ui/widgets/notification_bell.dart';
import 'package:pocket_pilot/src/ui/widgets/pp_screen_state.dart';

class TransactionsScreen extends StatefulWidget {
  const TransactionsScreen({super.key});

  @override
  State<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends State<TransactionsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
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
        title: const Text('Transacciones'),
        actions: const [NotificationBell()],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Transacciones'),
            Tab(text: 'Plantillas'),
            Tab(text: 'Rendimientos'),
            Tab(text: 'Deudas'),
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
        children: const [
          _TransactionsListTab(),
          TransactionTemplatesListTab(),
          YieldConfigsListTab(),
          DebtsListTab(),
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
    final vm = context.read<TransactionsViewModel>();
    final templateVM = context.read<TransactionTemplateViewModel>();
    final yieldVM = context.read<YieldConfigViewModel>();
    final debtVM = context.read<DebtViewModel>();
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
                icon: Icons.receipt_long_outlined,
                label: 'Nueva transacción',
                onTap: () {
                  Navigator.of(context).pop();
                  context.push('/transactions/new').then((_) {
                    if (context.mounted) vm.loadOnAppear();
                  });
                },
              ),
              SheetItem(
                icon: Icons.swap_horiz_rounded,
                label: 'Nueva transferencia',
                onTap: () {
                  Navigator.of(context).pop();
                  context.push('/transactions/transfer').then((_) {
                    if (context.mounted) vm.loadOnAppear();
                  });
                },
              ),
              SheetItem(
                icon: Icons.schedule_outlined,
                label: 'Nueva plantilla',
                onTap: () {
                  Navigator.of(context).pop();
                  context.push('/transactions/templates/new').then((result) {
                    if (result == true && context.mounted) {
                      templateVM.loadOnAppear();
                    }
                  });
                },
              ),
              SheetItem(
                icon: Icons.trending_up_rounded,
                label: 'Nuevo rendimiento',
                onTap: () {
                  Navigator.of(context).pop();
                  context.push('/transactions/yields/new').then((result) {
                    if (result == true && context.mounted) {
                      yieldVM.loadOnAppear();
                    }
                  });
                },
              ),
              SheetItem(
                icon: Icons.handshake_outlined,
                label: 'Agregar deuda',
                onTap: () {
                  Navigator.of(context).pop();
                  context.push('/transactions/debts/new').then((result) {
                    if (result == true && context.mounted) {
                      debtVM.refresh();
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
// Tab de transacciones (contenido original)
// ============================================================

class _TransactionsListTab extends StatefulWidget {
  const _TransactionsListTab();

  @override
  State<_TransactionsListTab> createState() => _TransactionsListTabState();
}

class _TransactionsListTabState extends State<_TransactionsListTab> {
  Map<String, CategoryModel> _categoryMap = {};
  Map<String, AccountModel> _accountMap = {};
  bool _lookupsLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadLookups();
  }

  Future<void> _loadLookups() async {
    final db = context.read<DatabaseHelper>();
    final categoryStore = CategoryLocalStore(db: db);
    final accountStore = AccountLocalStore(db: db);

    final categories = await categoryStore.getCategories();
    final accounts = await accountStore.getAccounts();

    if (!mounted) return;
    setState(() {
      _categoryMap = {for (final c in categories) c.id: c};
      _accountMap = {for (final a in accounts) a.id: a};
      _lookupsLoaded = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<TransactionsViewModel>(
      builder: (context, vm, _) {
        final filterVM = context.watch<TransactionFilterViewModel>();
        final hasFilters = filterVM.resolvedFilter.hasAdvancedFilters ||
            filterVM.activePageIndex != 0 ||
            filterVM.quickSelection != QuickRange.d30;

        return Stack(
          children: [
            Column(
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
                    isLoading: vm.isLoading || !_lookupsLoaded,
                    errorMessage: vm.transactions.isEmpty
                        ? vm.errorMessage
                        : null,
                    isEmpty: vm.transactions.isEmpty,
                    emptyIcon: hasFilters
                        ? Icons.filter_list_off_rounded
                        : Icons.receipt_long_outlined,
                    emptyLabel: hasFilters
                        ? 'No hay transacciones con estos filtros'
                        : 'No hay transacciones aún',
                    emptySubLabel: hasFilters
                        ? 'Intenta cambiar los filtros'
                        : 'Presiona + para registrar una',
                    onRefresh: vm.refresh,
                    child: _TransactionList(
                      transactions: vm.transactions,
                      vm: vm,
                      categoryMap: _categoryMap,
                      accountMap: _accountMap,
                    ),
                  ),
                ),
              ],
            ),
            const FilterSheet(),
          ],
        );
      },
    );
  }
}

// ============================================================
// Lista con secciones por mes
// ============================================================

class _TransactionList extends StatelessWidget {
  final List<TransactionModel> transactions;
  final TransactionsViewModel vm;
  final Map<String, CategoryModel> categoryMap;
  final Map<String, AccountModel> accountMap;

  const _TransactionList({
    required this.transactions,
    required this.vm,
    required this.categoryMap,
    required this.accountMap,
  });

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
      padding: const EdgeInsets.only(bottom: 160),
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
                category: t.categoryId != null
                    ? categoryMap[t.categoryId]
                    : null,
                account: accountMap[t.accountId],
                onTap: () {
                  _handleTransactionTap(context, t);
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

  Future<void> _handleTransactionTap(
    BuildContext context,
    TransactionModel transaction,
  ) async {
    if (transaction.isTransfer) {
      _openTransferEdit(context, transaction);
      return;
    }

    final account = await _findAccountById(context, transaction.accountId);
    if (!context.mounted) return;

    if (account != null) {
      final isInitial = await vm.isInitialBalanceTransaction(
        transaction: transaction,
        accountType: account.type,
      );
      if (!context.mounted) return;

      if (isInitial) {
        context.push('/accounts/${account.id}/edit', extra: account).then((
          result,
        ) {
          if (result == true && context.mounted) {
            vm.loadOnAppear();
          }
        });
        return;
      }
    }

    context
        .push('/transactions/${transaction.id}/edit', extra: transaction)
        .then((result) {
          if (result == true && context.mounted) {
            vm.loadOnAppear();
          }
        });
  }

  Future<AccountModel?> _findAccountById(
    BuildContext context,
    String id,
  ) async {
    final db = context.read<DatabaseHelper>();
    return AccountLocalStore(db: db).getById(id);
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
  final CategoryModel? category;
  final AccountModel? account;
  final VoidCallback onTap;

  const _TransactionTile({
    required this.transaction,
    required this.onTap,
    this.category,
    this.account,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final Color iconBgColor;
    final Color amountColor;
    final IconData icon;

    final isAdjustment =
        transaction.nature == 'adjustment' && transaction.categoryId == null;

    if (isAdjustment) {
      iconBgColor = cs.secondary.withValues(alpha: 0.1);
      amountColor = cs.onSurfaceVariant;
      icon = Icons.sync_alt_rounded;
    } else if (transaction.isTransfer) {
      iconBgColor = cs.secondary.withValues(alpha: 0.1);
      amountColor = transaction.isTransferIn ? cs.primary : cs.onSurfaceVariant;
      icon = Icons.swap_horiz_rounded;
    } else if (transaction.isIncome) {
      iconBgColor = cs.onTertiary.withValues(alpha: 0.12);
      amountColor = cs.onTertiary;
      icon = category != null
          ? CategoryIconData.iconFromHex(category!.icon)
          : Icons.arrow_downward_rounded;
    } else {
      iconBgColor = cs.error.withValues(alpha: 0.1);
      amountColor = cs.error;
      icon = category != null
          ? CategoryIconData.iconFromHex(category!.icon)
          : Icons.arrow_upward_rounded;
    }

    final date = transaction.parsedDate;
    final formattedDate = '${date.day} ${_monthAbbr(date.month)} ${date.year}';

    final String categoryName;
    if (isAdjustment) {
      categoryName = 'Ajuste de saldo';
    } else if (transaction.isTransfer) {
      categoryName = 'Transferencia';
    } else {
      categoryName = category?.name ?? 'Sin categoría';
    }

    final accountName = account?.name;
    final description = transaction.description;
    final tags = transaction.tags;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
      child: Container(
        decoration: BoxDecoration(
          color: cs.surfaceContainer,
          borderRadius: AppTheme.radiusMedium,
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: const BorderRadius.all(Radius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Icon
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: iconBgColor,
                    borderRadius: AppTheme.radiusFull,
                  ),
                  child: Icon(icon, color: amountColor, size: 17),
                ),
                const SizedBox(width: 12),
                // Left side: category, account, description, tags
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Row 1: Category — Amount
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              categoryName,
                              style: GoogleFonts.ibmPlexSans(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: cs.onSurface,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            transaction.formattedAmount,
                            style: GoogleFonts.ibmPlexSans(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: amountColor,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      // Row 2: Account — Date
                      Row(
                        children: [
                          if (accountName != null) ...[
                            Expanded(
                              child: Text(
                                accountName,
                                style: GoogleFonts.ibmPlexSans(
                                  fontSize: 12,
                                  color: cs.onSurfaceVariant,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ] else
                            const Spacer(),
                          Text(
                            formattedDate,
                            style: GoogleFonts.ibmPlexSans(
                              fontSize: 12,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                      // Row 3: Description (left) | Tags (right)
                      if (tags.isNotEmpty || description.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (description.isNotEmpty)
                              Expanded(
                                child: Text(
                                  description,
                                  style: GoogleFonts.ibmPlexSans(
                                    fontSize: 11,
                                    color: cs.onSurfaceVariant,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              )
                            else
                              const Spacer(),
                            if (tags.isNotEmpty) ...[
                              const SizedBox(width: 8),
                              Wrap(
                                spacing: 4,
                                runSpacing: 4,
                                children: tags.map((tag) {
                                  return Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: cs.surfaceContainerHighest,
                                      borderRadius: AppTheme.radiusFull,
                                    ),
                                    child: Text(
                                      tag,
                                      style: GoogleFonts.ibmPlexSans(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w500,
                                        color: cs.onSurfaceVariant,
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
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

// ============================================================
// Helpers de eliminación
// ============================================================

Future<bool?> _confirmDelete(BuildContext context, TransactionModel t) {
  final isTransfer = t.isTransfer;
  final label = t.description.isNotEmpty
      ? '"${t.description}"'
      : 'esta transacción';
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(
        isTransfer ? 'Eliminar transferencia' : 'Eliminar transacción',
      ),
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
