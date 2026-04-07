import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:pocket_pilot/src/core/sync/scheduled_generation_orchestrator.dart';
import 'package:pocket_pilot/src/core/theme/app_colors.dart';
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
          children: [
            child ?? const SizedBox.shrink(),
            const AIOverlay(),
            const Positioned(left: 16, bottom: 80, child: _AILaunchButton()),
          ],
        );
      },
    );
  }
}

class _AILaunchButton extends StatelessWidget {
  const _AILaunchButton();

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AISessionController>();
    if (controller.state != AISessionState.idle) {
      return const SizedBox.shrink();
    }

    return FloatingActionButton(
      heroTag: 'ai_assistant',
      mini: true,
      backgroundColor: AppColors.primary,
      onPressed: controller.openSession,
      child: const Icon(Icons.mic, color: AppColors.backgroundDark),
    );
  }
}
