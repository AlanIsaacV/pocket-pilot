import 'package:app_settings/app_settings.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:pocket_pilot/src/core/notifications/notification_preferences.dart';
import 'package:pocket_pilot/src/core/notifications/notification_scheduler_service.dart';

class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState extends State<NotificationSettingsScreen>
    with WidgetsBindingObserver {
  bool _loading = true;
  bool _saving = false;
  NotificationPreferences _preferences = NotificationPreferences.defaults;
  NotificationPermissionStatus _permissionStatus =
      NotificationPermissionStatus.undetermined;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshPermissionStatus();
    }
  }

  Future<void> _load() async {
    final preferencesStore = context.read<NotificationPreferencesStore>();
    final scheduler = context.read<NotificationSchedulerService>();
    final preferences = await preferencesStore.getPreferences();
    final permissionStatus = await scheduler.refreshPermissionStatus();
    if (!mounted) return;
    setState(() {
      _preferences = preferences;
      _permissionStatus = permissionStatus;
      _loading = false;
    });
  }

  Future<void> _refreshPermissionStatus() async {
    final permissionStatus = await context
        .read<NotificationSchedulerService>()
        .refreshPermissionStatus();
    if (!mounted) return;
    setState(() => _permissionStatus = permissionStatus);
  }

  Future<void> _save(NotificationPreferences preferences) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await context.read<NotificationPreferencesStore>().savePreferences(
        preferences,
      );
      if (!mounted) return;
      await context
          .read<NotificationSchedulerService>()
          .rescheduleAllNotifications();
      if (!mounted) return;
      setState(() => _preferences = preferences);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudieron guardar los recordatorios.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickTime() async {
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: _preferences.notifyHour,
        minute: _preferences.notifyMinute,
      ),
    );
    if (time == null) return;
    await _save(
      NotificationPreferences(
        enabledTypes: _preferences.enabledTypes,
        notifyHour: time.hour,
        notifyMinute: time.minute,
        anticipationDays: _preferences.anticipationDays,
      ),
    );
  }

  void _setEnabled(String type, bool enabled) {
    _save(
      NotificationPreferences(
        enabledTypes: {..._preferences.enabledTypes, type: enabled},
        notifyHour: _preferences.notifyHour,
        notifyMinute: _preferences.notifyMinute,
        anticipationDays: _preferences.anticipationDays,
      ),
    );
  }

  void _setAnticipation(String type, int days) {
    _save(
      NotificationPreferences(
        enabledTypes: _preferences.enabledTypes,
        notifyHour: _preferences.notifyHour,
        notifyMinute: _preferences.notifyMinute,
        anticipationDays: {..._preferences.anticipationDays, type: days},
      ),
    );
  }

  Future<void> _openNotificationSettings() async {
    try {
      await AppSettings.openAppSettings(type: AppSettingsType.notification);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudieron abrir los ajustes del sistema.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Recordatorios de pagos')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                if (_permissionStatus ==
                    NotificationPermissionStatus.denied) ...[
                  _PermissionDeniedBanner(
                    onOpenSettings: _openNotificationSettings,
                  ),
                  const SizedBox(height: 16),
                ],
                Text(
                  'Elige qué recordatorios quieres recibir y cuándo avisarte.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.schedule_outlined),
                    title: const Text('Hora del recordatorio'),
                    subtitle: Text(
                      MaterialLocalizations.of(context).formatTimeOfDay(
                        TimeOfDay(
                          hour: _preferences.notifyHour,
                          minute: _preferences.notifyMinute,
                        ),
                      ),
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    enabled: !_saving,
                    onTap: _saving ? null : _pickTime,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Tipos de recordatorio',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                ..._reminderTypes.map(
                  (type) => _ReminderTypeCard(
                    type: type,
                    enabled: _preferences.isEnabled(type.id),
                    anticipationDays: _preferences.anticipationFor(type.id),
                    saving: _saving,
                    onEnabledChanged: (enabled) =>
                        _setEnabled(type.id, enabled),
                    onAnticipationChanged: (days) =>
                        _setAnticipation(type.id, days),
                  ),
                ),
              ],
            ),
    );
  }
}

class _PermissionDeniedBanner extends StatelessWidget {
  final Future<void> Function() onOpenSettings;

  const _PermissionDeniedBanner({required this.onOpenSettings});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      color: colors.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.notifications_off_outlined,
              color: colors.onErrorContainer,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Notificaciones desactivadas',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: colors.onErrorContainer,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Actívalas en los ajustes del sistema para recibir recordatorios.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colors.onErrorContainer,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: onOpenSettings,
                    child: const Text('Abrir ajustes'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReminderTypeCard extends StatelessWidget {
  final _ReminderType type;
  final bool enabled;
  final int anticipationDays;
  final bool saving;
  final ValueChanged<bool> onEnabledChanged;
  final ValueChanged<int> onAnticipationChanged;

  const _ReminderTypeCard({
    required this.type,
    required this.enabled,
    required this.anticipationDays,
    required this.saving,
    required this.onEnabledChanged,
    required this.onAnticipationChanged,
  });

  @override
  Widget build(BuildContext context) {
    final controlsEnabled = enabled && !saving;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 12),
        child: Column(
          children: [
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              secondary: Icon(type.icon),
              title: Text(type.label),
              subtitle: Text(type.description),
              value: enabled,
              onChanged: saving ? null : onEnabledChanged,
            ),
            const Divider(),
            Row(
              children: [
                const Icon(Icons.calendar_today_outlined, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    anticipationDays == 0
                        ? 'Avisar el mismo día'
                        : 'Avisar $anticipationDays ${anticipationDays == 1 ? 'día antes' : 'días antes'}',
                  ),
                ),
                IconButton(
                  tooltip: 'Reducir anticipación',
                  onPressed: controlsEnabled && anticipationDays > 0
                      ? () => onAnticipationChanged(anticipationDays - 1)
                      : null,
                  icon: const Icon(Icons.remove_circle_outline_rounded),
                ),
                IconButton(
                  tooltip: 'Aumentar anticipación',
                  onPressed: controlsEnabled
                      ? () => onAnticipationChanged(anticipationDays + 1)
                      : null,
                  icon: const Icon(Icons.add_circle_outline_rounded),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ReminderType {
  final String id;
  final String label;
  final String description;
  final IconData icon;

  const _ReminderType(this.id, this.label, this.description, this.icon);
}

const _reminderTypes = [
  _ReminderType(
    'CREDIT_CARD',
    'Tarjetas de crédito',
    'Pagos próximos de tus tarjetas.',
    Icons.credit_card_outlined,
  ),
  _ReminderType(
    'SUBSCRIPTION',
    'Suscripciones',
    'Cobros próximos de tus suscripciones.',
    Icons.autorenew_rounded,
  ),
  _ReminderType(
    'OBLIGATION',
    'Obligaciones',
    'Pagos pendientes y otros compromisos.',
    Icons.receipt_long_outlined,
  ),
  _ReminderType(
    'STATEMENT_IMPORT',
    'Estados de cuenta',
    'Recordatorios para importar tus estados de cuenta.',
    Icons.upload_file_outlined,
  ),
];
