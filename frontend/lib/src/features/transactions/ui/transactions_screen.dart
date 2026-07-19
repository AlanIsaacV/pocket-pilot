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
import 'package:pocket_pilot/src/ui/widgets/category_icon_data.dart';
import 'package:pocket_pilot/src/core/theme/app_theme.dart';
import 'package:pocket_pilot/src/features/notification_capture/domain/pending_transaction.dart';
import 'package:pocket_pilot/src/features/notification_capture/ui/pending_review_sheet.dart';
import 'package:pocket_pilot/src/features/notification_capture/ui/pending_suggestions_view_model.dart';
import 'package:pocket_pilot/src/features/transaction_templates/ui/transaction_template_view_model.dart';
import 'package:pocket_pilot/src/features/transaction_templates/ui/transaction_templates_list_tab.dart';
import 'package:pocket_pilot/src/features/transactions/domain/transaction.dart';
import 'package:pocket_pilot/src/ui/widgets/confirm_dialog.dart';
import 'package:pocket_pilot/src/ui/widgets/dismissible_background.dart';
import 'package:pocket_pilot/src/ui/widgets/form_widgets.dart';
import 'package:pocket_pilot/src/features/transactions/ui/transaction_filter_view_model.dart';
import 'package:pocket_pilot/src/features/transactions/ui/transactions_view_model.dart';
import 'package:pocket_pilot/src/features/transactions/ui/widgets/filter_sheet.dart';
import 'package:pocket_pilot/src/features/yield_configs/ui/yield_config_view_model.dart';
import 'package:pocket_pilot/src/features/yield_configs/ui/yield_configs_list_tab.dart';
import 'package:pocket_pilot/src/features/debts/ui/debt_view_model.dart';
import 'package:pocket_pilot/src/features/debts/ui/debts_list_tab.dart';
import 'package:pocket_pilot/src/ui/widgets/notification_bell.dart';
import 'package:pocket_pilot/src/ui/widgets/pp_screen_state.dart';
import 'package:pocket_pilot/src/ui/widgets/temporal_page_view.dart';

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
    final archivedAccounts = await accountStore.getArchivedAccounts();

    if (!mounted) return;
    setState(() {
      _categoryMap = {for (final c in categories) c.id: c};
      _accountMap = {
        for (final a in [...accounts, ...archivedAccounts]) a.id: a,
      };
      _lookupsLoaded = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<TransactionsViewModel>(
      builder: (context, vm, _) {
        final filterVM = context.watch<TransactionFilterViewModel>();
        final pendingVM = context.watch<PendingSuggestionsViewModel>();
        final hasFilters =
            filterVM.resolvedFilter.hasAdvancedFilters ||
            filterVM.activePageIndex != 0 ||
            filterVM.quickSelection != QuickRange.d30;

        // Las occurrences pendientes (templates con next_run vencida) viven
        // en `vm.transactions` con status='pending'. Las separamos para
        // mostrarlas dentro de la sección "Por confirmar" (junto con las
        // sugerencias de notificaciones) y evitar duplicarlas en el listado
        // mensual. La data subyacente no cambia: es solo presentación.
        final pendingOccurrences = vm.transactions
            .where((t) => t.status == 'pending')
            .toList(growable: false);
        final confirmedTransactions = vm.transactions
            .where((t) => t.status != 'pending')
            .toList(growable: false);
        final pendingSuggestions = pendingVM.pendingTransactions;
        final hasAnyData =
            vm.transactions.isNotEmpty || pendingSuggestions.isNotEmpty;

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
                    errorMessage: !hasAnyData ? vm.errorMessage : null,
                    isEmpty: !hasAnyData,
                    emptyIcon: hasFilters
                        ? Icons.filter_list_off_rounded
                        : Icons.receipt_long_outlined,
                    emptyLabel: hasFilters
                        ? 'No hay transacciones con estos filtros'
                        : 'No hay transacciones aún',
                    emptySubLabel: hasFilters
                        ? 'Intenta cambiar los filtros'
                        : 'Presiona + para registrar una',
                    onRefresh: () =>
                        Future.wait([vm.refresh(), pendingVM.refresh()]),
                    child: _TransactionList(
                      transactions: confirmedTransactions,
                      pendingOccurrences: pendingOccurrences,
                      pendingSuggestions: pendingSuggestions,
                      vm: vm,
                      pendingVM: pendingVM,
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
  final List<TransactionModel> pendingOccurrences;
  final List<PendingTransactionModel> pendingSuggestions;
  final TransactionsViewModel vm;
  final PendingSuggestionsViewModel pendingVM;
  final Map<String, CategoryModel> categoryMap;
  final Map<String, AccountModel> accountMap;

  const _TransactionList({
    required this.transactions,
    required this.pendingOccurrences,
    required this.pendingSuggestions,
    required this.vm,
    required this.pendingVM,
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

    final children = <Widget>[];
    final pendingTotal = pendingSuggestions.length + pendingOccurrences.length;
    final resolvedSuggestionCount = pendingSuggestions
        .where(
          (suggestion) =>
              suggestion.suggestedAccountId != null &&
              suggestion.suggestedCategoryId != null,
        )
        .length;
    if (pendingTotal > 0) {
      children.add(
        _PendingConfirmHeader(
          count: pendingTotal,
          resolvedSuggestionCount: resolvedSuggestionCount,
          onApproveAllResolved: () =>
              _approveAllResolved(context, resolvedSuggestionCount),
        ),
      );
      for (final s in pendingSuggestions) {
        children.add(_buildSuggestionRow(context, s));
      }
      for (final t in pendingOccurrences) {
        children.add(_buildTransactionRow(context, t));
      }
      children.add(const SizedBox(height: 16));
    }

    for (final section in groups.entries) {
      children.add(_MonthHeader(monthKey: section.key));
      for (final t in section.value) {
        children.add(_buildTransactionRow(context, t));
      }
    }

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 160),
      itemCount: children.length,
      itemBuilder: (context, index) => children[index],
    );
  }

  Widget _buildTransactionRow(BuildContext context, TransactionModel t) {
    return Dismissible(
      key: ValueKey('tx-${t.id}'),
      direction: DismissDirection.endToStart,
      background: const DismissibleBackground(
        label: 'Eliminar',
        icon: Icons.delete_outline_rounded,
      ),
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
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text('No se pudo eliminar: $e')));
          }
        }
      },
      child: _TransactionTile(
        transaction: t,
        category: t.categoryId != null ? categoryMap[t.categoryId] : null,
        account: accountMap[t.accountId],
        onTap: () => _handleTransactionTap(context, t),
        onConfirm: t.status == 'pending'
            ? () => _handleConfirmTap(context, t)
            : null,
      ),
    );
  }

  Widget _buildSuggestionRow(
    BuildContext context,
    PendingTransactionModel suggestion,
  ) {
    return Dismissible(
      key: ValueKey('sg-${suggestion.id}'),
      direction: DismissDirection.endToStart,
      background: const DismissibleBackground(
        label: 'Eliminar',
        icon: Icons.delete_outline_rounded,
      ),
      confirmDismiss: (_) => _confirmDismissSuggestion(context, suggestion),
      onDismissed: (_) async {
        try {
          await pendingVM.dismissPending(suggestion);
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Sugerencia descartada')),
            );
          }
        } catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text('No se pudo descartar: $e')));
          }
        }
      },
      child: _SuggestionTile(
        suggestion: suggestion,
        onTap: () => _openReviewSheet(context, suggestion),
        onConfirm: () => _openReviewSheet(context, suggestion),
        candidateCategories: () => pendingVM.candidateCategoriesFor(suggestion),
        categoryMap: categoryMap,
        onCategorySelected: (categoryId) =>
            _approveWithCategory(context, suggestion, categoryId),
      ),
    );
  }

  Future<void> _approveAllResolved(
    BuildContext context,
    int resolvedSuggestionCount,
  ) async {
    final confirmed = await _confirmApproveAllResolved(
      context,
      resolvedSuggestionCount,
    );
    if (confirmed != true || !context.mounted) return;

    try {
      final result = await pendingVM.approveAllResolved();
      if (!context.mounted) return;
      final message = result.failed == 0
          ? '${result.approved} aprobadas'
          : '${result.approved} aprobadas, ${result.failed} con error';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudieron aprobar: $error')),
        );
      }
    }
  }

  Future<void> _approveWithCategory(
    BuildContext context,
    PendingTransactionModel suggestion,
    String categoryId,
  ) async {
    final accountId = suggestion.suggestedAccountId;
    if (accountId == null) return;

    try {
      await pendingVM.approvePending(
        pending: suggestion,
        accountId: accountId,
        categoryId: categoryId,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Sugerencia aprobada')));
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('No se pudo aprobar: $error')));
      }
    }
  }

  Future<void> _openReviewSheet(
    BuildContext context,
    PendingTransactionModel suggestion,
  ) async {
    // showModalBottomSheet usa el rootNavigator → no hereda los providers
    // del subtree de TransactionsRouteScope. Re-proveemos explícitamente
    // los stores que el sheet consulta en su initState.
    final pVM = context.read<PendingSuggestionsViewModel>();
    final accounts = context.read<AccountLocalStore>();
    final categories = context.read<CategoryLocalStore>();
    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => MultiProvider(
        providers: [
          ChangeNotifierProvider<PendingSuggestionsViewModel>.value(value: pVM),
          Provider<AccountLocalStore>.value(value: accounts),
          Provider<CategoryLocalStore>.value(value: categories),
        ],
        child: PendingReviewSheet(pending: suggestion),
      ),
    );
  }

  Future<void> _handleConfirmTap(
    BuildContext context,
    TransactionModel transaction,
  ) async {
    try {
      await vm.confirmTransaction(
        transaction.id,
        linkedTransactionId: transaction.linkedTransactionId,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Transacción confirmada')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('No se pudo confirmar: $e')));
      }
    }
  }

  Future<void> _handleTransactionTap(
    BuildContext context,
    TransactionModel transaction,
  ) async {
    if (transaction.isTransfer) {
      _openTransferEdit(context, transaction);
      return;
    }

    // Adjustments always open in the transaction editor, never in account edit.
    if (transaction.nature != 'adjustment') {
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

  Future<void> _openTransferEdit(
    BuildContext context,
    TransactionModel t,
  ) async {
    TransactionModel? linked;
    if (t.linkedTransactionId != null) {
      // La pierna complementaria puede estar fuera del listado filtrado;
      // primero se intenta en memoria y, si no aparece, se busca en DB.
      linked =
          vm.findLinked(t.linkedTransactionId!) ??
          await vm.getTransactionById(t.linkedTransactionId!);
    }
    if (!context.mounted) return;

    final outLeg = t.isTransferOut ? t : linked;
    final inLeg = t.isTransferOut ? linked : t;

    if (outLeg == null || inLeg == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se encontró la otra pierna de la transferencia'),
        ),
      );
      return;
    }

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
  final VoidCallback? onConfirm;

  const _TransactionTile({
    required this.transaction,
    required this.onTap,
    this.category,
    this.account,
    this.onConfirm,
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
    final isAutoConfirmed = transaction.source == 'auto_notification';

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
                      if (tags.isNotEmpty ||
                          description.isNotEmpty ||
                          isAutoConfirmed) ...[
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
                            if (isAutoConfirmed || tags.isNotEmpty) ...[
                              const SizedBox(width: 8),
                              Wrap(
                                spacing: 4,
                                runSpacing: 4,
                                children: [
                                  if (isAutoConfirmed)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: cs.primaryContainer,
                                        borderRadius: AppTheme.radiusFull,
                                      ),
                                      child: Text(
                                        'Auto',
                                        style: GoogleFonts.ibmPlexSans(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w600,
                                          color: cs.onPrimaryContainer,
                                        ),
                                      ),
                                    ),
                                  ...tags.map((tag) {
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
                                  }),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ],
                      if (transaction.status == 'pending') ...[
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: cs.tertiaryContainer,
                                borderRadius: AppTheme.radiusFull,
                              ),
                              child: Text(
                                'Pendiente',
                                style: GoogleFonts.ibmPlexSans(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: cs.onTertiaryContainer,
                                ),
                              ),
                            ),
                            const Spacer(),
                            if (onConfirm != null)
                              TextButton.icon(
                                onPressed: onConfirm,
                                icon: const Icon(
                                  Icons.check_circle_outline,
                                  size: 16,
                                ),
                                label: Text(
                                  'Confirmar',
                                  style: GoogleFonts.ibmPlexSans(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                style: TextButton.styleFrom(
                                  foregroundColor: cs.primary,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 0,
                                  ),
                                  minimumSize: const Size(0, 28),
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                              ),
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

Future<bool?> _confirmDismissSuggestion(
  BuildContext context,
  PendingTransactionModel suggestion,
) {
  final label = suggestion.merchantDescription?.trim().isNotEmpty == true
      ? '"${suggestion.merchantDescription}"'
      : 'esta sugerencia';
  return showConfirmDialog(
    context,
    title: 'Descartar sugerencia',
    message:
        'Se descartará $label. La notificación original seguirá guardada localmente sin generar transacción.',
    confirmLabel: 'Descartar',
    destructive: true,
  );
}

Future<bool?> _confirmApproveAllResolved(BuildContext context, int count) {
  return showConfirmDialog(
    context,
    title: 'Aprobar sugerencias resueltas',
    message:
        'Se aprobarán $count sugerencias con cuenta y categoría asignadas.',
    confirmLabel: 'Aprobar',
  );
}

Future<bool?> _confirmDelete(BuildContext context, TransactionModel t) {
  final isTransfer = t.isTransfer;
  final label = t.description.isNotEmpty
      ? '"${t.description}"'
      : 'esta transacción';
  return showConfirmDialog(
    context,
    title: isTransfer ? 'Eliminar transferencia' : 'Eliminar transacción',
    message: isTransfer
        ? 'Se eliminará esta transferencia completa (ambos movimientos).'
        : 'Se eliminará $label.',
    confirmLabel: 'Eliminar',
    destructive: true,
  );
}

// ============================================================
// Sección "Por confirmar" — header + filas de sugerencias
// ============================================================

class _PendingConfirmHeader extends StatelessWidget {
  final int count;
  final int resolvedSuggestionCount;
  final VoidCallback onApproveAllResolved;

  const _PendingConfirmHeader({
    required this.count,
    required this.resolvedSuggestionCount,
    required this.onApproveAllResolved,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: [
          Icon(
            Icons.pending_actions_rounded,
            size: 16,
            color: cs.onSurfaceVariant,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'POR CONFIRMAR ($count)',
              style: GoogleFonts.ibmPlexSans(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.2,
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
          if (resolvedSuggestionCount > 0)
            TextButton(
              onPressed: onApproveAllResolved,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 28),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                'Aprobar $resolvedSuggestionCount resueltas',
                style: GoogleFonts.ibmPlexSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SuggestionTile extends StatefulWidget {
  final PendingTransactionModel suggestion;
  final VoidCallback onTap;
  final VoidCallback onConfirm;
  final Future<List<String>> Function() candidateCategories;
  final Map<String, CategoryModel> categoryMap;
  final ValueChanged<String> onCategorySelected;

  const _SuggestionTile({
    required this.suggestion,
    required this.onTap,
    required this.onConfirm,
    required this.candidateCategories,
    required this.categoryMap,
    required this.onCategorySelected,
  });

  @override
  State<_SuggestionTile> createState() => _SuggestionTileState();
}

class _SuggestionTileState extends State<_SuggestionTile> {
  Future<List<String>>? _candidateCategories;

  @override
  void initState() {
    super.initState();
    _loadCandidateCategories();
  }

  @override
  void didUpdateWidget(covariant _SuggestionTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.suggestion.id != widget.suggestion.id ||
        oldWidget.suggestion.suggestedAccountId !=
            widget.suggestion.suggestedAccountId ||
        oldWidget.suggestion.suggestedCategoryId !=
            widget.suggestion.suggestedCategoryId) {
      _loadCandidateCategories();
    }
  }

  void _loadCandidateCategories() {
    final suggestion = widget.suggestion;
    _candidateCategories =
        suggestion.suggestedAccountId != null &&
            suggestion.suggestedCategoryId == null
        ? widget.candidateCategories()
        : null;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final suggestion = widget.suggestion;
    final isIncome = suggestion.transactionType == 'income';
    final amountColor = isIncome ? cs.onTertiary : cs.error;
    final iconBg = isIncome
        ? cs.onTertiary.withValues(alpha: 0.12)
        : cs.error.withValues(alpha: 0.1);

    final amount = (suggestion.amountCents / 100).toStringAsFixed(2);
    final sign = isIncome ? '+' : '-';
    final description = suggestion.merchantDescription?.trim();
    final title = description != null && description.isNotEmpty
        ? description
        : 'Sin descripción';
    final cardSuffix = suggestion.cardLastDigits != null
        ? '····${suggestion.cardLastDigits}'
        : null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
      child: Container(
        decoration: BoxDecoration(
          color: cs.surfaceContainer,
          borderRadius: AppTheme.radiusMedium,
        ),
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: const BorderRadius.all(Radius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: iconBg,
                    borderRadius: AppTheme.radiusFull,
                  ),
                  child: Icon(
                    Icons.notifications_active_outlined,
                    color: amountColor,
                    size: 17,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              title,
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
                            '$sign${suggestion.currencyCode} $amount',
                            style: GoogleFonts.ibmPlexSans(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: amountColor,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      if (cardSuffix != null)
                        Text(
                          cardSuffix,
                          style: GoogleFonts.ibmPlexSans(
                            fontSize: 12,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: cs.tertiaryContainer,
                              borderRadius: AppTheme.radiusFull,
                            ),
                            child: Text(
                              'Notificación bancaria',
                              style: GoogleFonts.ibmPlexSans(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: cs.onTertiaryContainer,
                              ),
                            ),
                          ),
                          const Spacer(),
                          TextButton.icon(
                            onPressed: widget.onConfirm,
                            icon: const Icon(
                              Icons.check_circle_outline,
                              size: 16,
                            ),
                            label: Text(
                              'Confirmar',
                              style: GoogleFonts.ibmPlexSans(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            style: TextButton.styleFrom(
                              foregroundColor: cs.primary,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 0,
                              ),
                              minimumSize: const Size(0, 28),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                          ),
                        ],
                      ),
                      if (suggestion.suggestedAccountId != null &&
                          suggestion.suggestedCategoryId == null)
                        FutureBuilder<List<String>>(
                          future: _candidateCategories!,
                          builder: (context, snapshot) {
                            final categoryIds = snapshot.data;
                            if (categoryIds == null || categoryIds.isEmpty) {
                              return const SizedBox.shrink();
                            }
                            return Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: [
                                  for (final categoryId in categoryIds)
                                    ChoiceChip(
                                      label: Text(
                                        widget.categoryMap[categoryId]?.name ??
                                            categoryId,
                                      ),
                                      selected: false,
                                      onSelected: (selected) {
                                        if (selected) {
                                          widget.onCategorySelected(categoryId);
                                        }
                                      },
                                    ),
                                ],
                              ),
                            );
                          },
                        ),
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
}
