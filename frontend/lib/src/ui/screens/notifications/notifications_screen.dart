import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:pocket_pilot/src/core/notifications/in_app_notification.dart';
import 'package:pocket_pilot/src/core/notifications/notification_center_view_model.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  @override
  void initState() {
    super.initState();
    // Refresh when entering the screen.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<NotificationCenterViewModel>().load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<NotificationCenterViewModel>();
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notificaciones'),
        actions: [
          if (vm.notifications.isNotEmpty) ...[
            IconButton(
              icon: const Icon(Icons.done_all),
              tooltip: 'Marcar todas como leidas',
              onPressed: () => vm.markAllAsRead(),
            ),
            IconButton(
              icon: const Icon(Icons.delete_sweep),
              tooltip: 'Eliminar todas',
              onPressed: () => _confirmDeleteAll(context, vm),
            ),
          ],
        ],
      ),
      body: vm.isLoading
          ? const Center(child: CircularProgressIndicator())
          : vm.notifications.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.notifications_off_outlined,
                          size: 64, color: theme.colorScheme.outline),
                      const SizedBox(height: 16),
                      Text(
                        'No hay notificaciones',
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 32),
                  itemCount: _buildItems(vm.notifications).length,
                  itemBuilder: (context, index) {
                    final item = _buildItems(vm.notifications)[index];
                    if (item is _SectionHeader) {
                      return _SectionHeaderTile(label: item.label);
                    }
                    final notification = item as InAppNotification;
                    return _NotificationTile(
                      notification: notification,
                      onTap: () => vm.markAsRead(notification.id),
                      onDismissed: () {
                        vm.delete(notification.id);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: const Text('Notificacion eliminada'),
                            action: SnackBarAction(
                              label: 'Deshacer',
                              onPressed: () => vm.restore(notification.id),
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
    );
  }

  List<Object> _buildItems(List<InAppNotification> notifications) {
    final items = <Object>[];
    String? currentSection;

    for (final n in notifications) {
      final section = _sectionLabel(n.date);
      if (section != currentSection) {
        currentSection = section;
        items.add(_SectionHeader(section));
      }
      items.add(n);
    }

    return items;
  }

  String _sectionLabel(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dateOnly = DateTime(date.year, date.month, date.day);
    final diff = today.difference(dateOnly).inDays;

    if (diff == 0) return 'Hoy';
    if (diff == -1) return 'Manana';
    if (diff == 1) return 'Ayer';
    if (diff < 0 && diff >= -7) return 'Proximos 7 dias';
    if (diff > 0 && diff <= 7) return 'Esta semana';
    if (diff < 0) return 'Proximos';
    return 'Anteriores';
  }

  void _confirmDeleteAll(BuildContext context, NotificationCenterViewModel vm) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar todas'),
        content: const Text(
          'Se eliminaran todas las notificaciones. Esta accion no se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              vm.deleteAll();
            },
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader {
  final String label;
  const _SectionHeader(this.label);
}

class _SectionHeaderTile extends StatelessWidget {
  final String label;
  const _SectionHeaderTile({required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        label,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  final InAppNotification notification;
  final VoidCallback onTap;
  final VoidCallback onDismissed;

  const _NotificationTile({
    required this.notification,
    required this.onTap,
    required this.onDismissed,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dismissible(
      key: ValueKey(notification.id),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => onDismissed(),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: theme.colorScheme.error,
        child: Icon(Icons.delete, color: theme.colorScheme.onError),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: theme.colorScheme.surfaceContainerHighest,
          child: Icon(_iconForType(notification.type), size: 20),
        ),
        title: Text(
          notification.title,
          style: TextStyle(
            fontWeight: notification.isRead ? FontWeight.normal : FontWeight.w600,
          ),
        ),
        subtitle: notification.subtitle.isNotEmpty
            ? Text(notification.subtitle)
            : null,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _formatDate(notification.date),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
            if (!notification.isRead) ...[
              const SizedBox(width: 8),
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ],
        ),
        onTap: onTap,
      ),
    );
  }

  IconData _iconForType(String type) {
    switch (type) {
      case 'CREDIT_CARD':
        return Icons.credit_card;
      case 'SUBSCRIPTION':
        return Icons.autorenew;
      case 'OBLIGATION':
        return Icons.payments_outlined;
      default:
        return Icons.notifications_outlined;
    }
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dateOnly = DateTime(date.year, date.month, date.day);
    final diff = today.difference(dateOnly).inDays;

    if (diff == 0) return 'Hoy';
    if (diff == -1) return 'Manana';
    if (diff == 1) return 'Ayer';
    return '${date.day}/${date.month}';
  }
}
