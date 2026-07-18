import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:pocket_pilot/src/core/notifications/notification_center_view_model.dart';
import 'package:pocket_pilot/src/core/notifications/notification_scheduler_service.dart';
import 'package:pocket_pilot/src/core/notifications/statement_import_preferences.dart';
import 'package:pocket_pilot/src/features/accounts/data/account_local_store.dart';
import 'package:pocket_pilot/src/features/accounts/domain/account.dart';

class StatementImportReminderSettingsScreen extends StatefulWidget {
  const StatementImportReminderSettingsScreen({super.key});

  @override
  State<StatementImportReminderSettingsScreen> createState() =>
      _StatementImportReminderSettingsScreenState();
}

class _StatementImportReminderSettingsScreenState
    extends State<StatementImportReminderSettingsScreen> {
  bool _loading = true;
  List<AccountModel> _accounts = const [];
  List<StatementImportReminder> _reminders = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final accountStore = context.read<AccountLocalStore>();
    final preferences = context.read<StatementImportPreferences>();
    final accounts = await accountStore.getAccounts();
    final reminders = await preferences.getReminders();
    if (!mounted) return;
    setState(() {
      _accounts = accounts;
      _reminders = reminders;
      _loading = false;
    });
  }

  Future<void> _configureReminder({StatementImportReminder? existing}) async {
    final preferences = context.read<StatementImportPreferences>();
    final scheduler = context.read<NotificationSchedulerService>();
    final notificationCenter = context.read<NotificationCenterViewModel>();
    final configuredIds = _reminders
        .map((reminder) => reminder.accountId)
        .toSet();
    final choices = _accounts
        .where(
          (account) =>
              existing?.accountId == account.id ||
              !configuredIds.contains(account.id),
        )
        .toList();
    if (choices.isEmpty) return;

    final result = await showDialog<StatementImportReminder>(
      context: context,
      builder: (_) =>
          _StatementImportReminderDialog(accounts: choices, initial: existing),
    );
    if (result == null) return;
    if (!mounted) return;

    await preferences.setReminder(result.accountId, result.dayOfMonth);
    await scheduler.rescheduleAllNotifications();
    if (!mounted) return;
    await notificationCenter.load();
    if (!mounted) return;
    await _load();
  }

  Future<void> _removeReminder(StatementImportReminder reminder) async {
    final preferences = context.read<StatementImportPreferences>();
    final scheduler = context.read<NotificationSchedulerService>();
    final notificationCenter = context.read<NotificationCenterViewModel>();
    await preferences.removeReminder(reminder.accountId);
    await scheduler.rescheduleAllNotifications();
    if (!mounted) return;
    await notificationCenter.load();
    if (!mounted) return;
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final accountById = {for (final account in _accounts) account.id: account};
    return Scaffold(
      appBar: AppBar(title: const Text('Recordatorios de estados de cuenta')),
      floatingActionButton: _loading || _accounts.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: _configureReminder,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Agregar'),
            ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              children: [
                Text(
                  'Recibe un recordatorio mensual para importar el estado de cuenta de las cuentas que elijas.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                if (_accounts.isEmpty)
                  const ListTile(
                    leading: Icon(Icons.account_balance_outlined),
                    title: Text('No hay cuentas disponibles'),
                    subtitle: Text(
                      'Crea una cuenta antes de configurar un recordatorio.',
                    ),
                  )
                else if (_reminders.isEmpty)
                  const ListTile(
                    leading: Icon(Icons.event_note_outlined),
                    title: Text('Sin recordatorios configurados'),
                    subtitle: Text(
                      'Agrega una cuenta y el día en que importas su estado de cuenta.',
                    ),
                  )
                else
                  ..._reminders.map((reminder) {
                    final account = accountById[reminder.accountId];
                    if (account == null) return const SizedBox.shrink();
                    return Card(
                      child: ListTile(
                        leading: const Icon(Icons.upload_file_outlined),
                        title: Text(account.name),
                        subtitle: Text(
                          'Recordar el día ${reminder.dayOfMonth} de cada mes',
                        ),
                        onTap: () => _configureReminder(existing: reminder),
                        trailing: IconButton(
                          tooltip: 'Eliminar recordatorio',
                          icon: const Icon(Icons.delete_outline_rounded),
                          onPressed: () => _removeReminder(reminder),
                        ),
                      ),
                    );
                  }),
              ],
            ),
    );
  }
}

class _StatementImportReminderDialog extends StatefulWidget {
  final List<AccountModel> accounts;
  final StatementImportReminder? initial;

  const _StatementImportReminderDialog({required this.accounts, this.initial});

  @override
  State<_StatementImportReminderDialog> createState() =>
      _StatementImportReminderDialogState();
}

class _StatementImportReminderDialogState
    extends State<_StatementImportReminderDialog> {
  late String _accountId;
  late int _dayOfMonth;

  @override
  void initState() {
    super.initState();
    _accountId = widget.initial?.accountId ?? widget.accounts.first.id;
    _dayOfMonth = widget.initial?.dayOfMonth ?? 1;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.initial == null ? 'Agregar recordatorio' : 'Editar recordatorio',
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<String>(
            initialValue: _accountId,
            decoration: const InputDecoration(labelText: 'Cuenta'),
            items: widget.accounts
                .map(
                  (account) => DropdownMenuItem(
                    value: account.id,
                    child: Text(account.name),
                  ),
                )
                .toList(),
            onChanged: (value) => setState(() => _accountId = value!),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<int>(
            initialValue: _dayOfMonth,
            decoration: const InputDecoration(labelText: 'Día del mes'),
            items: List.generate(
              31,
              (index) => DropdownMenuItem(
                value: index + 1,
                child: Text('${index + 1}'),
              ),
            ),
            onChanged: (value) => setState(() => _dayOfMonth = value!),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(
            StatementImportReminder(
              accountId: _accountId,
              dayOfMonth: _dayOfMonth,
            ),
          ),
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}
