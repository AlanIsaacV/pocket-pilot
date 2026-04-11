// ============================================================
// YieldConfigsListTab — Contenido de tab de rendimientos
// ============================================================
//
// Widget sin Scaffold para usar dentro de un TabBarView.
// Muestra rendimientos con badge de estado, info de frecuencia y APY.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'package:pocket_pilot/src/core/theme/app_theme.dart';
import 'package:pocket_pilot/src/features/yield_configs/domain/yield_config.dart';
import 'package:pocket_pilot/src/features/yield_configs/ui/yield_config_view_model.dart';
import 'package:pocket_pilot/src/ui/widgets/pp_screen_state.dart';

class YieldConfigsListTab extends StatelessWidget {
  const YieldConfigsListTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<YieldConfigViewModel>(
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
                errorMessage:
                    vm.configs.isEmpty ? vm.errorMessage : null,
                isEmpty: vm.configs.isEmpty,
                emptyIcon: Icons.trending_up_rounded,
                emptyLabel: 'No hay rendimientos aún',
                emptySubLabel: 'Presiona + para crear uno',
                onRefresh: vm.refresh,
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                  physics: const AlwaysScrollableScrollPhysics(),
                  itemCount: vm.configs.length,
                  itemBuilder: (context, index) {
                    final config = vm.configs[index];
                    return _YieldRow(
                      config: config,
                      onEdit: () => _openEdit(context, config, vm),
                      onDelete: () => _confirmDelete(context, config, vm),
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
    YieldConfigModel config,
    YieldConfigViewModel vm,
  ) {
    context
        .push('/transactions/yields/${config.id}/edit', extra: config)
        .then((result) {
      if (result == true && context.mounted) {
        vm.loadOnAppear();
      }
    });
  }

  Future<void> _confirmDelete(
    BuildContext context,
    YieldConfigModel config,
    YieldConfigViewModel vm,
  ) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar rendimiento'),
        content: Text('Se eliminará "${config.name}".'),
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
    if (confirm == true && context.mounted) {
      await vm.deleteConfig(config.id);
    }
  }
}

// ============================================================
// Fila de rendimiento
// ============================================================

class _YieldRow extends StatelessWidget {
  final YieldConfigModel config;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _YieldRow({
    required this.config,
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
          leading: _StatusBadge(status: config.status),
          title: Text(
            config.name,
            style: GoogleFonts.ibmPlexSans(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          subtitle: Text(
            _subtitleLabel(config),
            style: GoogleFonts.ibmPlexSans(
              fontSize: 11,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${config.apyRate}% APY',
                style: GoogleFonts.ibmPlexSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.tertiary,
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
      key: ValueKey('delete-${config.id}'),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) async {
        onDelete();
        return false;
      },
      background: _DeleteBackground(),
      child: row,
    );
  }

  String _subtitleLabel(YieldConfigModel c) {
    final freq = switch (c.payoutFrequency) {
      'daily' => 'Diario',
      'weekly' => 'Semanal',
      'monthly' => 'Mensual',
      'at_maturity' => 'Al vencimiento',
      _ => c.payoutFrequency,
    };
    final amount = c.amountCents / 100;
    final formatted = amount == amount.truncateToDouble()
        ? amount.toInt().toString()
        : amount.toStringAsFixed(2);
    return '$freq · \$$formatted';
  }
}

// ============================================================
// Badge de estado (icono con fondo de color)
// ============================================================

class _StatusBadge extends StatelessWidget {
  final String status;

  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (status) {
      'active' => (
          Icons.trending_up_rounded,
          Theme.of(context).colorScheme.tertiary,
        ),
      'paused' => (
          Icons.pause_circle_outline_rounded,
          Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      'completed' => (
          Icons.check_circle_outline_rounded,
          Theme.of(context).colorScheme.primary,
        ),
      _ => (
          Icons.help_outline_rounded,
          Theme.of(context).colorScheme.onSurfaceVariant,
        ),
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

// ============================================================
// Background de swipe "Eliminar"
// ============================================================

class _DeleteBackground extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.error.withValues(alpha: 0.15),
        borderRadius: AppTheme.radiusMedium,
        border: Border.all(
          color: Theme.of(context).colorScheme.error.withValues(alpha: 0.4),
        ),
      ),
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Eliminar',
            style: GoogleFonts.ibmPlexSans(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.error,
            ),
          ),
          const SizedBox(width: 6),
          Icon(
            Icons.delete_outline_rounded,
            color: Theme.of(context).colorScheme.error,
            size: 18,
          ),
        ],
      ),
    );
  }
}
