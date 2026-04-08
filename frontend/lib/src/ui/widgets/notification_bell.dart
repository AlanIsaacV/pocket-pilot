import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:pocket_pilot/src/core/notifications/notification_center_view_model.dart';

class NotificationBell extends StatelessWidget {
  const NotificationBell({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<NotificationCenterViewModel>();
    final count = vm.unreadCount;

    return IconButton(
      icon: Badge(
        isLabelVisible: count > 0,
        label: Text(
          count > 9 ? '9+' : count.toString(),
          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
        ),
        child: const Icon(Icons.notifications_outlined),
      ),
      onPressed: () => context.push('/notifications'),
      tooltip: 'Notificaciones',
    );
  }
}
