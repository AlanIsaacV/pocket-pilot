// ============================================================
// OnboardingPermissionScreen — explica el permiso y abre Ajustes
// ============================================================
//
// Pantalla informativa antes/cuando el usuario aún no ha concedido el acceso
// a notificaciones. Pide explícitamente y enlaza al panel de sistema.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:pocket_pilot/src/features/notification_capture/ui/notification_inbox_view_model.dart';

class OnboardingPermissionScreen extends StatefulWidget {
  const OnboardingPermissionScreen({super.key});

  @override
  State<OnboardingPermissionScreen> createState() =>
      _OnboardingPermissionScreenState();
}

class _OnboardingPermissionScreenState
    extends State<OnboardingPermissionScreen> with WidgetsBindingObserver {
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
    if (state == AppLifecycleState.resumed && mounted) {
      // Al volver de Ajustes, refrescamos para ver si concedió el permiso.
      context.read<NotificationInboxViewModel>().refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<NotificationInboxViewModel>();
    final theme = Theme.of(context);
    final isAndroid = Platform.isAndroid;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Captura de notificaciones'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
          onPressed: () => context.pop(),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.notifications_active_rounded,
              size: 48,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              'Auto-registro desde notificaciones',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Cuando concedas el permiso, Pocket Pilot leerá las notificaciones '
              'de tu app del banco (BBVA México en esta versión) y te sugerirá '
              'transacciones para que apruebes con un toque.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            _BulletPoint(
              icon: Icons.shield_outlined,
              text:
                  'Si un parser local hace match, la notificación nunca sale del dispositivo.',
            ),
            _BulletPoint(
              icon: Icons.cloud_upload_outlined,
              text:
                  'Si no hace match, puedes activar (opcional) el parseo asistido por IA '
                  'en Ajustes → Captura de notificaciones. Está desactivado por defecto.',
            ),
            _BulletPoint(
              icon: Icons.verified_user_outlined,
              text:
                  'Cada sugerencia debe ser aprobada por ti antes de convertirse en '
                  'una transacción real.',
            ),
            const SizedBox(height: 28),
            if (!isAndroid)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'iOS no permite leer notificaciones de otras apps. Esta '
                  'feature solo funciona en Android.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onErrorContainer,
                  ),
                ),
              )
            else
              _PermissionStatusCard(
                granted: vm.permissionGranted,
                onOpenSettings: () => vm.openPermissionSettings(),
              ),
          ],
        ),
      ),
    );
  }
}

class _BulletPoint extends StatelessWidget {
  final IconData icon;
  final String text;

  const _BulletPoint({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: theme.colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(text, style: theme.textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}

class _PermissionStatusCard extends StatelessWidget {
  final bool granted;
  final VoidCallback onOpenSettings;

  const _PermissionStatusCard({
    required this.granted,
    required this.onOpenSettings,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = granted
        ? theme.colorScheme.primary
        : theme.colorScheme.tertiary;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                granted ? Icons.check_circle_rounded : Icons.info_outline,
                color: color,
                size: 22,
              ),
              const SizedBox(width: 8),
              Text(
                granted ? 'Permiso concedido' : 'Permiso pendiente',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            granted
                ? 'Pocket Pilot está leyendo notificaciones de los bancos en allowlist. '
                    'Las verás aparecer en la bandeja conforme lleguen.'
                : 'Toca el botón para abrir Ajustes → Acceso a notificaciones y activa '
                    '"Pocket Pilot" en la lista.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onOpenSettings,
              icon: const Icon(Icons.settings_outlined, size: 18),
              label: Text(granted ? 'Revisar Ajustes' : 'Abrir Ajustes'),
            ),
          ),
        ],
      ),
    );
  }
}
