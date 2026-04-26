// ============================================================
// PendingInboxScreen — bandeja de sugerencias + raw notifications
// ============================================================
//
// Sección 1: PendingTransactions (sugerencias listas para aprobar)
// Sección 2: CapturedNotifications crudas no parseables (informativo)

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'package:pocket_pilot/src/features/notification_capture/domain/captured_notification.dart';
import 'package:pocket_pilot/src/features/notification_capture/domain/pending_transaction.dart';
import 'package:pocket_pilot/src/features/notification_capture/ui/notification_inbox_view_model.dart';
import 'package:pocket_pilot/src/features/notification_capture/ui/pending_review_sheet.dart';

class PendingInboxScreen extends StatelessWidget {
  const PendingInboxScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<NotificationInboxViewModel>();
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Bandeja de captura'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
          onPressed: () => context.pop(),
        ),
        actions: [
          IconButton(
            tooltip: 'Configurar permiso',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.push('/onboarding/notifications'),
          ),
          IconButton(
            tooltip: 'Refrescar',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: vm.isLoading ? null : () => vm.refresh(),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => vm.refresh(),
        child: _buildBody(context, vm, theme),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    NotificationInboxViewModel vm,
    ThemeData theme,
  ) {
    if (vm.isLoading &&
        vm.pendingTransactions.isEmpty &&
        vm.rawNotifications.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (!vm.permissionGranted) {
      return _PermissionDeniedView(
        onOpenSettings: () => context.push('/onboarding/notifications'),
      );
    }

    if (vm.pendingTransactions.isEmpty && vm.rawNotifications.isEmpty) {
      return _EmptyInboxView(theme: theme);
    }

    final children = <Widget>[];

    if (vm.pendingTransactions.isNotEmpty) {
      children.add(_SectionHeader(label: 'Sugerencias', theme: theme));
      for (final pending in vm.pendingTransactions) {
        children.add(_PendingTransactionTile(
          pending: pending,
          onTap: () => _openReviewSheet(context, pending),
        ));
        children.add(const Divider(height: 0, indent: 16, endIndent: 16));
      }
    }

    if (vm.rawNotifications.isNotEmpty) {
      children.add(const SizedBox(height: 8));
      children.add(_SectionHeader(label: 'Sin procesar', theme: theme));
      for (final n in vm.rawNotifications) {
        children.add(_RawNotificationTile(
          notification: n,
          onDismiss: () => vm.dismissRaw(n.id),
        ));
        children.add(const Divider(height: 0, indent: 16, endIndent: 16));
      }
    }

    return ListView(padding: const EdgeInsets.symmetric(vertical: 8), children: children);
  }

  Future<void> _openReviewSheet(
    BuildContext context,
    PendingTransactionModel pending,
  ) async {
    final vm = context.read<NotificationInboxViewModel>();
    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetCtx) => ChangeNotifierProvider.value(
        value: vm,
        child: PendingReviewSheet(pending: pending),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;
  final ThemeData theme;

  const _SectionHeader({required this.label, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Text(
        label,
        style: GoogleFonts.ibmPlexSans(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: theme.colorScheme.onSurfaceVariant,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _PendingTransactionTile extends StatelessWidget {
  final PendingTransactionModel pending;
  final VoidCallback onTap;

  const _PendingTransactionTile({
    required this.pending,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isIncome = pending.transactionType == 'income';
    final amount = (pending.amountCents / 100).toStringAsFixed(2);
    final sign = isIncome ? '+' : '-';

    return ListTile(
      onTap: onTap,
      leading: CircleAvatar(
        backgroundColor: isIncome
            ? Colors.green.withValues(alpha: 0.15)
            : theme.colorScheme.errorContainer,
        child: Icon(
          isIncome
              ? Icons.arrow_downward_rounded
              : Icons.arrow_upward_rounded,
          color: isIncome ? Colors.green : theme.colorScheme.error,
          size: 18,
        ),
      ),
      title: Text(
        pending.merchantDescription?.trim().isNotEmpty == true
            ? pending.merchantDescription!
            : 'Sin descripción',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(
        pending.cardLastDigits != null
            ? '····${pending.cardLastDigits} · Toca para revisar'
            : 'Toca para revisar',
        style: theme.textTheme.bodySmall,
      ),
      trailing: Text(
        '$sign${pending.currencyCode} $amount',
        style: GoogleFonts.ibmPlexSans(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: isIncome ? Colors.green : theme.colorScheme.error,
        ),
      ),
    );
  }
}

class _RawNotificationTile extends StatelessWidget {
  final CapturedNotificationModel notification;
  final VoidCallback onDismiss;

  const _RawNotificationTile({
    required this.notification,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final body = notification.effectiveText;

    return Dismissible(
      key: ValueKey(notification.id),
      direction: DismissDirection.endToStart,
      background: Container(
        color: theme.colorScheme.errorContainer,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Icon(
          Icons.delete_outline_rounded,
          color: theme.colorScheme.onErrorContainer,
        ),
      ),
      onDismissed: (_) => onDismiss(),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: theme.colorScheme.surfaceContainerHigh,
          child: Icon(
            Icons.notifications_outlined,
            color: theme.colorScheme.onSurfaceVariant,
            size: 18,
          ),
        ),
        title: Text(
          notification.title?.trim().isNotEmpty == true
              ? notification.title!
              : notification.packageName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleSmall,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (body.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                body,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 4),
            Text(
              '${_formatTime(notification.postedAt)} · ${_statusLabel(notification.status)}',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        isThreeLine: body.isNotEmpty,
      ),
    );
  }

  String _formatTime(DateTime utc) {
    final local = utc.toLocal();
    final h = local.hour.toString().padLeft(2, '0');
    final m = local.minute.toString().padLeft(2, '0');
    return '${local.day}/${local.month} $h:$m';
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'received':
        return 'sin procesar';
      case 'matched_local':
        return 'matched (local)';
      case 'matched_server':
        return 'matched (servidor)';
      case 'llm_used':
        return 'matched (LLM)';
      case 'unparseable':
        return 'no parseable';
      default:
        return status;
    }
  }
}

class _EmptyInboxView extends StatelessWidget {
  final ThemeData theme;

  const _EmptyInboxView({required this.theme});

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        const SizedBox(height: 80),
        Icon(
          Icons.inbox_outlined,
          size: 56,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(height: 12),
        Center(
          child: Text(
            'Bandeja vacía',
            style: theme.textTheme.titleMedium,
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            'Cuando llegue una notificación de tu banco, aparecerá aquí lista para revisar.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

class _PermissionDeniedView extends StatelessWidget {
  final VoidCallback onOpenSettings;

  const _PermissionDeniedView({required this.onOpenSettings});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 60),
        Icon(
          Icons.notifications_off_outlined,
          size: 56,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(height: 12),
        Center(
          child: Text(
            'Permiso pendiente',
            style: theme.textTheme.titleLarge,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Para que Pocket Pilot pueda sugerir transacciones a partir de tus '
          'notificaciones bancarias, primero necesitas concederle acceso.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: onOpenSettings,
          icon: const Icon(Icons.tune_rounded, size: 18),
          label: const Text('Configurar permiso'),
        ),
      ],
    );
  }
}
