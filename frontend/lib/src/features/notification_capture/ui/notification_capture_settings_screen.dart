// ============================================================
// NotificationCaptureSettingsScreen — toggles del feature
// ============================================================
//
// Centraliza la configuración del feature de captura de notificaciones:
//   - Permiso del SO (link a Settings de Android).
//   - Ir a la bandeja de sugerencias.
//   - Toggle "Parseo asistido por IA" (envía al backend cuando los parsers
//     locales fallan; opt-in, default OFF).
//   - Toggle "Ayuda a mejorar la aplicación" (autoriza retener samples
//     anonimizados en candidate_parsers; opt-out, default ON, deshabilitado
//     visualmente cuando el primero está OFF porque no aplica).
//
// El primer toggle requiere el segundo deshabilitado cuando OFF — sin LLM no
// hay sample que retener.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'package:pocket_pilot/src/features/notification_capture/data/notification_capture_preferences.dart';
import 'package:pocket_pilot/src/features/notification_capture/data/notification_permission_service.dart';
import 'package:pocket_pilot/src/features/notification_capture/ui/pending_suggestions_view_model.dart';

class NotificationCaptureSettingsScreen extends StatefulWidget {
  const NotificationCaptureSettingsScreen({super.key});

  @override
  State<NotificationCaptureSettingsScreen> createState() =>
      _NotificationCaptureSettingsScreenState();
}

class _NotificationCaptureSettingsScreenState
    extends State<NotificationCaptureSettingsScreen> {
  bool _loading = true;
  bool _shareWithLlm = false;
  bool _helpImproveApp = true;
  bool _autoConfirmEnabled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final prefs = context.read<NotificationCapturePreferences>();
    final share = await prefs.shareWithLlmForParser();
    final help = await prefs.helpImproveApp();
    final autoConfirm = await prefs.autoConfirmEnabled();
    if (!mounted) return;
    setState(() {
      _shareWithLlm = share;
      _helpImproveApp = help;
      _autoConfirmEnabled = autoConfirm;
      _loading = false;
    });
  }

  Future<void> _setShareWithLlm(bool value) async {
    final prefs = context.read<NotificationCapturePreferences>();
    await prefs.setShareWithLlmForParser(value);
    if (!mounted) return;
    setState(() => _shareWithLlm = value);
  }

  Future<void> _setHelpImproveApp(bool value) async {
    final prefs = context.read<NotificationCapturePreferences>();
    await prefs.setHelpImproveApp(value);
    if (!mounted) return;
    setState(() => _helpImproveApp = value);
  }

  Future<void> _setAutoConfirmEnabled(bool value) async {
    final prefs = context.read<NotificationCapturePreferences>();
    await prefs.setAutoConfirmEnabled(value);
    if (!mounted) return;
    setState(() => _autoConfirmEnabled = value);
  }

  Future<void> _openOSPermissionSettings() async {
    final svc = context.read<NotificationPermissionService>();
    await svc.openSettings();
  }

  Future<void> _reprocessUnparseable() async {
    final vm = context.read<PendingSuggestionsViewModel>();
    final messenger = ScaffoldMessenger.of(context);
    final result = await vm.reprocessUnparseable();
    if (!mounted) return;
    final text = result.reopened == 0
        ? 'No hay notificaciones para reintentar.'
        : 'Reintentadas ${result.reopened}, parseadas ${result.matched}.';
    messenger.showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Captura de notificaciones')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
              children: [
                _SectionLabel(label: 'PERMISOS'),
                _Card(
                  child: Column(children: [
                    ListTile(
                      leading: const Icon(Icons.lock_open_rounded),
                      title: const Text('Permiso del sistema'),
                      subtitle: const Text(
                        'Habilita la lectura de notificaciones bancarias en Ajustes de Android.',
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: _openOSPermissionSettings,
                    ),
                    const Divider(height: 1, indent: 56),
                    ListTile(
                      leading: const Icon(Icons.account_balance_rounded),
                      title: const Text('Mis bancos'),
                      subtitle: const Text(
                        'Elige qué apps de tu dispositivo son bancos. La captura solo procesa notificaciones de las apps que marques.',
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () =>
                          context.push('/settings/notification-capture/banks'),
                    ),
                    const Divider(height: 1, indent: 56),
                    ListTile(
                      leading: const Icon(Icons.replay_rounded),
                      title: const Text('Reintentar parseo'),
                      subtitle: const Text(
                        'Vuelve a procesar las notificaciones que el engine no pudo leer antes (útil tras una actualización del parser).',
                      ),
                      onTap: _reprocessUnparseable,
                    ),
                  ]),
                ),
                const SizedBox(height: 16),
                _SectionLabel(label: 'CONFIRMACIÓN AUTOMÁTICA'),
                _Card(
                  child: SwitchListTile(
                    title: const Text('Confirmar transacciones resueltas'),
                    subtitle: const Text(
                      'Registra automáticamente notificaciones leídas '
                      'localmente cuando la cuenta y categoría son claras.',
                    ),
                    value: _autoConfirmEnabled,
                    onChanged: _setAutoConfirmEnabled,
                  ),
                ),
                const SizedBox(height: 16),
                _SectionLabel(label: 'PRIVACIDAD E IA'),
                _Card(
                  child: Column(children: [
                    SwitchListTile(
                      title: const Text('Parseo asistido por IA'),
                      subtitle: const Text(
                        'Cuando una notificación no puede leerse localmente, '
                        'enviarla al servidor para que un modelo de IA extraiga '
                        'los datos. Cuota: 50 al día.',
                      ),
                      value: _shareWithLlm,
                      onChanged: _setShareWithLlm,
                    ),
                    const Divider(height: 1, indent: 16),
                    Opacity(
                      opacity: _shareWithLlm ? 1.0 : 0.5,
                      child: SwitchListTile(
                        title: const Text('Ayuda a mejorar la aplicación'),
                        subtitle: const Text(
                          'Permite usar las notificaciones procesadas por IA, '
                          'sin tu identidad, para mejorar los parsers que '
                          'benefician a todos los usuarios.',
                        ),
                        value: _helpImproveApp,
                        onChanged:
                            _shareWithLlm ? _setHelpImproveApp : null,
                      ),
                    ),
                  ]),
                ),
                const SizedBox(height: 24),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    'El parseo local nunca envía nada a la red. Solo cuando '
                    'estos toggles están activos se contacta con el servidor.',
                    style: GoogleFonts.ibmPlexSans(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
      child: Text(
        label,
        style: GoogleFonts.ibmPlexSans(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.2,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).colorScheme.surfaceContainerHigh,
          width: 1,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: child,
      ),
    );
  }
}
