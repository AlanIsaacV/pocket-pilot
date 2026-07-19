// ============================================================
// TransactionTemplatesListTab — Contenido de tab de plantillas
// ============================================================
//
// Widget sin Scaffold para usar dentro de un TabBarView.
// Muestra plantillas con badge de tipo, info de frecuencia y monto.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'package:pocket_pilot/src/core/theme/app_theme.dart';
import 'package:pocket_pilot/src/features/transaction_templates/domain/transaction_template.dart';
import 'package:pocket_pilot/src/features/transaction_templates/ui/transaction_template_view_model.dart';
import 'package:pocket_pilot/src/ui/widgets/confirm_dialog.dart';
import 'package:pocket_pilot/src/ui/widgets/dismissible_background.dart';
import 'package:pocket_pilot/src/ui/widgets/pp_screen_state.dart';

class TransactionTemplatesListTab extends StatelessWidget {
  const TransactionTemplatesListTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<TransactionTemplateViewModel>(
      builder: (context, vm, _) {
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
                errorMessage: vm.templates.isEmpty ? vm.errorMessage : null,
                isEmpty: vm.templates.isEmpty,
                emptyIcon: Icons.schedule_outlined,
                emptyLabel: 'No hay plantillas aún',
                emptySubLabel: 'Presiona + para crear una',
                onRefresh: vm.refresh,
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                  physics: const AlwaysScrollableScrollPhysics(),
                  itemCount: vm.templates.length,
                  itemBuilder: (context, index) {
                    final template = vm.templates[index];
                    return _TemplateRow(
                      template: template,
                      onEdit: () => _openEdit(context, template, vm),
                      onDelete: () => _confirmDelete(context, template, vm),
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

  void _openEdit(
    BuildContext context,
    TransactionTemplateModel template,
    TransactionTemplateViewModel vm,
  ) {
    context
        .push('/transactions/templates/${template.id}/edit', extra: template)
        .then((result) {
          if (result == true && context.mounted) {
            vm.loadOnAppear();
          }
        });
  }

  Future<void> _confirmDelete(
    BuildContext context,
    TransactionTemplateModel template,
    TransactionTemplateViewModel vm,
  ) async {
    final confirm = await showConfirmDialog(
      context,
      title: 'Eliminar plantilla',
      message: 'Se eliminará "${template.name}".',
      confirmLabel: 'Eliminar',
      destructive: true,
    );
    if (confirm == true && context.mounted) {
      await vm.deleteTemplate(template.id);
    }
  }
}

// ============================================================
// Fila de plantilla
// ============================================================

class _TemplateRow extends StatelessWidget {
  final TransactionTemplateModel template;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _TemplateRow({
    required this.template,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final row = Padding(
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
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 4,
          ),
          leading: _TypeBadge(type: template.type),
          title: Text(
            template.name,
            style: GoogleFonts.ibmPlexSans(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          subtitle: Text(
            _scheduleLabel(template),
            style: GoogleFonts.ibmPlexSans(
              fontSize: 11,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (template.amountCents != null)
                Text(
                  _formatAmount(template.amountCents!, template.currencyCode),
                  style: GoogleFonts.ibmPlexSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: _amountColor(context, template.type),
                  ),
                ),
              const SizedBox(width: 4),
              Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ],
          ),
          onTap: onEdit,
        ),
      ),
    );

    return Dismissible(
      key: ValueKey('delete-${template.id}'),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) async {
        onDelete();
        return false;
      },
      background: const DismissibleBackground(
        label: 'Eliminar',
        icon: Icons.delete_outline_rounded,
      ),
      child: row,
    );
  }

  String _scheduleLabel(TransactionTemplateModel t) {
    if (t.frequency == null) return 'Manual';
    final freq = switch (t.frequency) {
      'DAILY' => 'Diaria',
      'WEEKLY' => 'Semanal',
      'MONTHLY' => 'Mensual',
      'YEARLY' => 'Anual',
      _ => t.frequency!,
    };
    if (t.nextDate != null) {
      return '$freq · desde ${t.nextDate}';
    }
    return freq;
  }

  String _formatAmount(int cents, String currency) {
    final amount = cents / 100;
    final formatted = amount == amount.truncateToDouble()
        ? amount.toInt().toString()
        : amount.toStringAsFixed(2);
    return '$currency $formatted';
  }

  Color _amountColor(BuildContext context, String type) {
    return switch (type) {
      'income' => Theme.of(context).colorScheme.tertiary,
      'expense' => Theme.of(context).colorScheme.error,
      _ => Theme.of(context).colorScheme.primary,
    };
  }
}

// ============================================================
// Badge de tipo (icono con fondo de color)
// ============================================================

class _TypeBadge extends StatelessWidget {
  final String type;

  const _TypeBadge({required this.type});

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (type) {
      'income' => (
        Icons.arrow_downward_rounded,
        Theme.of(context).colorScheme.tertiary,
      ),
      'expense' => (
        Icons.arrow_upward_rounded,
        Theme.of(context).colorScheme.error,
      ),
      _ => (Icons.swap_horiz_rounded, Theme.of(context).colorScheme.primary),
    };

    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: AppTheme.radiusFull,
      ),
      child: Icon(icon, color: color, size: 18),
    );
  }
}
