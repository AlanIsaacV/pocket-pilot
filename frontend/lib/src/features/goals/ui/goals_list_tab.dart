// ============================================================
// GoalsListTab — Tab de listado de metas financieras
// ============================================================

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'package:pocket_pilot/src/core/theme/app_theme.dart';
import 'package:pocket_pilot/src/features/goals/domain/goal.dart';
import 'package:pocket_pilot/src/features/goals/ui/goal_view_model.dart';
import 'package:pocket_pilot/src/ui/widgets/pp_screen_state.dart';

class GoalsListTab extends StatelessWidget {
  const GoalsListTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<GoalViewModel>(
      builder: (context, vm, _) {
        return Column(
          children: [
            if (vm.isSyncing && !vm.isLoading)
              LinearProgressIndicator(
                color: Theme.of(context).colorScheme.primary,
                backgroundColor:
                    Theme.of(context).colorScheme.surfaceContainerHigh,
                minHeight: 2,
              ),
            Expanded(
              child: PpScreenState(
                isLoading: vm.isLoading,
                errorMessage: vm.goals.isEmpty ? vm.errorMessage : null,
                isEmpty: vm.goals.isEmpty,
                emptyIcon: Icons.flag_outlined,
                emptyLabel: 'No tienes metas aun',
                emptySubLabel: 'Presiona + para agregar una',
                onRefresh: vm.refresh,
                child: ListView.builder(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                  itemCount: vm.goals.length,
                  itemBuilder: (context, index) {
                    final goal = vm.goals[index];
                    return Dismissible(
                      key: ValueKey(goal.id),
                      direction: DismissDirection.endToStart,
                      background: _DeleteBackground(),
                      confirmDismiss: (_) =>
                          _confirmDelete(context, goal.name),
                      onDismissed: (_) async {
                        try {
                          await vm.deleteGoal(goal.id);
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Meta "${goal.name}" eliminada',
                              ),
                            ),
                          );
                        } catch (e) {
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'No se pudo eliminar la meta: $e',
                              ),
                            ),
                          );
                        }
                      },
                      child: _GoalCard(
                        goal: goal,
                        onTap: () => _onGoalTap(context, goal),
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

  void _onGoalTap(BuildContext context, GoalModel goal) {
    context
        .push('/accounts/goals/${goal.id}/edit', extra: goal)
        .then((result) {
      if (result == true && context.mounted) {
        context.read<GoalViewModel>().loadOnAppear();
      }
    });
  }

  Future<bool?> _confirmDelete(BuildContext context, String goalName) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar meta'),
        content: Text('Se eliminara la meta "$goalName".'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// Tarjeta de meta con barra de progreso
// ============================================================

class _GoalCard extends StatelessWidget {
  final GoalModel goal;
  final VoidCallback onTap;

  const _GoalCard({required this.goal, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final progress = goal.progressPercentage.clamp(0, 100).toDouble();
    final progressFraction = progress / 100;
    final target = goal.targetAmountCents / 100;
    final monthly = goal.monthlyRequiredCents / 100;
    final months = goal.monthsRemaining;
    final isOverdue = goal.isOverdue;

    final (statusLabel, statusColor) = isOverdue
        ? ('Atrasada', Theme.of(context).colorScheme.error)
        : ('En curso', Theme.of(context).colorScheme.tertiary);

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
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.12),
                      borderRadius: AppTheme.radiusFull,
                    ),
                    child: Icon(
                      Icons.flag_rounded,
                      color: statusColor,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          goal.name,
                          style: GoogleFonts.ibmPlexSans(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Meta: ${goal.targetDate}',
                          style: GoogleFonts.ibmPlexSans(
                            fontSize: 12,
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
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
              Row(
                children: [
                  Text(
                    'Progreso',
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
                      color: Theme.of(context).colorScheme.onSurface,
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
                  backgroundColor:
                      Theme.of(context).colorScheme.surfaceContainerHigh,
                  color: statusColor,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _InfoChip(
                    label: 'Objetivo',
                    value: '${goal.currencyCode} \$${_formatMoney(target)}',
                    context: context,
                  ),
                  const SizedBox(width: 12),
                  _InfoChip(
                    label: 'Faltan',
                    value: '$months ${months == 1 ? 'mes' : 'meses'}',
                    context: context,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    Icons.calendar_month_outlined,
                    size: 14,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Cuota mensual: ${goal.currencyCode} \$${_formatMoney(monthly)}',
                    style: GoogleFonts.ibmPlexSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
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

class _InfoChip extends StatelessWidget {
  final String label;
  final String value;
  final BuildContext context;

  const _InfoChip({
    required this.label,
    required this.value,
    required this.context,
  });

  @override
  Widget build(BuildContext innerContext) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.ibmPlexSans(
              fontSize: 11,
              color: Theme.of(innerContext).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: GoogleFonts.ibmPlexSans(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Theme.of(innerContext).colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// Background de swipe "Eliminar"
// ============================================================

class _DeleteBackground extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
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
