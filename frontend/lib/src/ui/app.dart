import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:pocket_pilot/src/core/sync/scheduled_generation_orchestrator.dart';
import 'package:pocket_pilot/src/core/notifications/notification_scheduler_service.dart';
import 'package:pocket_pilot/src/core/theme/app_theme.dart';
import 'package:pocket_pilot/src/core/theme/theme_preference_controller.dart';
import 'package:pocket_pilot/src/features/ai_assistant/ui/ai_overlay.dart';
import 'package:pocket_pilot/src/features/ai_assistant/ui/ai_session_controller.dart';

class PocketPilotApp extends StatefulWidget {
  final GoRouter router;

  const PocketPilotApp({super.key, required this.router});

  @override
  State<PocketPilotApp> createState() => _PocketPilotAppState();
}

class _PocketPilotAppState extends State<PocketPilotApp>
    with WidgetsBindingObserver {
  DateTime? _lastSyncTime;
  static const _syncThrottle = Duration(seconds: 30);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final notificationScheduler = context
          .read<NotificationSchedulerService>();
      unawaited(_refreshNotificationPermission(notificationScheduler));

      final now = DateTime.now();
      if (_lastSyncTime == null ||
          now.difference(_lastSyncTime!) >= _syncThrottle) {
        _lastSyncTime = now;
        context.read<ScheduledGenerationOrchestrator>().runCycle();
      }
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      context.read<AISessionController>().endSession();
    }
  }

  Future<void> _refreshNotificationPermission(
    NotificationSchedulerService scheduler,
  ) async {
    final status = await scheduler.refreshPermissionStatus();
    if (status == NotificationPermissionStatus.granted) {
      await scheduler.rescheduleAllNotifications();
    }
  }

  @override
  Widget build(BuildContext context) {
    final themePreference = context.watch<ThemePreferenceController>();

    return MaterialApp.router(
      title: 'Pocket Pilot',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themePreference.themeMode,
      routerConfig: widget.router,
      builder: (context, child) {
        return Stack(
          children: [child ?? const SizedBox.shrink(), const AIOverlay()],
        );
      },
    );
  }
}
