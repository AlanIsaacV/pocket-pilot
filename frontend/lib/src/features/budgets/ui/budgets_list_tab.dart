// ============================================================
// BudgetsListTab — Tab de listado de presupuestos
// ============================================================

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'package:pocket_pilot/src/core/db/database_helper.dart';
import 'package:pocket_pilot/src/core/theme/app_theme.dart';
import 'package:pocket_pilot/src/features/budgets/domain/budget.dart';
import 'package:pocket_pilot/src/features/budgets/domain/budget_status.dart';
import 'package:pocket_pilot/src/features/budgets/ui/budget_view_model.dart';
import 'package:pocket_pilot/src/features/categories/data/category_local_store.dart';
import 'package:pocket_pilot/src/features/categories/domain/category.dart';
import 'package:pocket_pilot/src/ui/widgets/category_icon_data.dart';
import 'package:pocket_pilot/src/ui/widgets/confirm_dialog.dart';
import 'package:pocket_pilot/src/ui/widgets/dismissible_background.dart';
import 'package:pocket_pilot/src/ui/widgets/transaction_form_widgets.dart';
import 'package:pocket_pilot/src/ui/widgets/pp_screen_state.dart';

class BudgetsListTab extends StatefulWidget {
  const BudgetsListTab({super.key});

  @override
  State<BudgetsListTab> createState() => _BudgetsListTabState();
}

class _BudgetsListTabState extends State<BudgetsListTab> {
  late final CategoryLocalStore _categoryStore;
  final Map<String, CategoryModel> _categoryCache = {};

  @override
  void initState() {
    super.initState();
    _categoryStore = CategoryLocalStore(db: context.read<DatabaseHelper>());
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadCategories());
  }

  Future<void> _loadCategories() async {
    final vm = context.read<BudgetViewModel>();
    for (final status in vm.budgetStatuses) {
      await _ensureCategory(status.budget.categoryId);
    }
    if (mounted) setState(() {});
  }

  Future<CategoryModel?> _ensureCategory(String categoryId) async {
    if (_categoryCache.containsKey(categoryId)) {
      return _categoryCache[categoryId];
    }
    final cat = await _categoryStore.getCategoryById(categoryId);
    if (cat != null) {
      _categoryCache[categoryId] = cat;
    }
    return cat;
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<BudgetViewModel>(
      builder: (context, vm, _) {
        // Refresh category cache when statuses change
        for (final status in vm.budgetStatuses) {
          _ensureCategory(status.budget.categoryId).then((_) {
            if (mounted) setState(() {});
          });
        }

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
                errorMessage: vm.budgetStatuses.isEmpty
                    ? vm.errorMessage
                    : null,
                isEmpty: vm.budgetStatuses.isEmpty,
                emptyIcon: Icons.pie_chart_outline_rounded,
                emptyLabel: 'No tienes presupuestos aun',
                emptySubLabel: 'Presiona + para agregar uno',
                onRefresh: vm.refresh,
                child: ListView.builder(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                  itemCount: vm.budgetStatuses.length,
                  itemBuilder: (context, index) {
                    final status = vm.budgetStatuses[index];
                    final category = _categoryCache[status.budget.categoryId];
                    return Dismissible(
                      key: ValueKey(status.budget.id),
                      direction: DismissDirection.endToStart,
                      background: const DismissibleBackground(
                        label: 'Eliminar',
                        icon: Icons.delete_outline_rounded,
                      ),
                      confirmDismiss: (_) => _confirmDelete(
                        context,
                        category?.name ?? 'Presupuesto',
                      ),
                      onDismissed: (_) async {
                        try {
                          await vm.deleteBudget(status.budget.id);
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Presupuesto "${category?.name ?? ''}" eliminado',
                              ),
                            ),
                          );
                        } catch (e) {
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('No se pudo eliminar: $e')),
                          );
                        }
                      },
                      child: _BudgetCard(
                        status: status,
                        category: category,
                        onTap: () => _onBudgetTap(context, status.budget),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  void _onBudgetTap(BuildContext context, BudgetModel budget) {
    context.push('/accounts/budgets/${budget.id}/edit', extra: budget).then((
      result,
    ) {
      if (result == true && context.mounted) {
        context.read<BudgetViewModel>().loadOnAppear();
      }
    });
  }

  Future<bool?> _confirmDelete(BuildContext context, String name) {
    return showConfirmDialog(
      context,
      title: 'Eliminar presupuesto',
      message: 'Se eliminara el presupuesto de "$name".',
      confirmLabel: 'Eliminar',
      destructive: true,
    );
  }
}

// ============================================================
// Tarjeta de presupuesto con barra de progreso
// ============================================================

class _BudgetCard extends StatelessWidget {
  final BudgetStatus status;
  final CategoryModel? category;
  final VoidCallback onTap;

  const _BudgetCard({
    required this.status,
    required this.category,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final progress = status.progressPercentage.clamp(0, 200).toDouble();
    final progressFraction = (progress / 100).clamp(0.0, 1.0);
    final isExceeded = status.spentAmountCents > status.budget.limitAmountCents;
    final spent = status.spentAmountCents / 100;
    final limit = status.budget.limitAmountCents / 100;
    final remaining = status.remainingAmountCents / 100;

    final (statusLabel, statusColor) = isExceeded
        ? ('Excedido', Theme.of(context).colorScheme.error)
        : ('En curso', Theme.of(context).colorScheme.tertiary);

    final categoryIcon = category != null
        ? CategoryIconData.iconFromHex(category!.icon)
        : Icons.category_outlined;
    final categoryColor = category != null
        ? hexToColor(category!.color)
        : statusColor;
    final categoryName = category?.name ?? 'Sin categoria';
    final periodLabel = status.budget.period == 'MONTHLY' ? 'MENSUAL' : 'ANUAL';

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainer,
            borderRadius: AppTheme.radiusMedium,
            border: Border.all(
              color: Theme.of(context).colorScheme.surfaceContainerHigh,
              width: 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header: icon + name + status badge
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: categoryColor.withValues(alpha: 0.12),
                      borderRadius: AppTheme.radiusFull,
                    ),
                    child: Icon(categoryIcon, color: categoryColor, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          categoryName,
                          style: GoogleFonts.ibmPlexSans(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          periodLabel,
                          style: GoogleFonts.ibmPlexSans(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            letterSpacing: 0.5,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.12),
                      borderRadius: AppTheme.radiusFull,
                    ),
                    child: Text(
                      statusLabel,
                      style: GoogleFonts.ibmPlexSans(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: statusColor,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Progress bar
              Row(
                children: [
                  Text(
                    '${status.budget.currencyCode} \$${_formatMoney(spent)} / \$${_formatMoney(limit)}',
                    style: GoogleFonts.ibmPlexSans(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${progress.toStringAsFixed(0)}%',
                    style: GoogleFonts.ibmPlexSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isExceeded
                          ? Theme.of(context).colorScheme.error
                          : Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: AppTheme.radiusFull,
                child: LinearProgressIndicator(
                  value: progressFraction,
                  minHeight: 6,
                  backgroundColor: Theme.of(
                    context,
                  ).colorScheme.surfaceContainerHigh,
                  color: isExceeded
                      ? Theme.of(context).colorScheme.error
                      : statusColor,
                ),
              ),
              const SizedBox(height: 8),

              // Remaining
              Row(
                children: [
                  Icon(
                    isExceeded
                        ? Icons.warning_amber_rounded
                        : Icons.account_balance_wallet_outlined,
                    size: 14,
                    color: isExceeded
                        ? Theme.of(context).colorScheme.error
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    isExceeded
                        ? 'Excedido por ${status.budget.currencyCode} \$${_formatMoney(remaining.abs())}'
                        : 'Disponible: ${status.budget.currencyCode} \$${_formatMoney(remaining)}',
                    style: GoogleFonts.ibmPlexSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: isExceeded
                          ? Theme.of(context).colorScheme.error
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _formatMoney(double amount) {
    if (amount == amount.truncateToDouble()) {
      return amount.toInt().toString();
    }
    return amount.toStringAsFixed(2);
  }
}
