import 'dart:convert';

import 'package:pocket_pilot/src/features/user_preferences/data/user_preference_local_store.dart';
import 'package:pocket_pilot/src/features/user_preferences/domain/user_preference.dart';

const String kPrefStatementImportReminders =
    'notifications.statement_import_reminders';

/// A device-local monthly reminder to import an account statement.
class StatementImportReminder {
  final String accountId;
  final int dayOfMonth;

  const StatementImportReminder({
    required this.accountId,
    required this.dayOfMonth,
  });
}

/// Device-local storage for monthly statement-import reminders.
///
/// The value is intentionally not enqueued in the sync outbox: reminders are
/// configured for this device's notification schedule, not shared state.
class StatementImportPreferences {
  final UserPreferenceLocalStore _store;

  const StatementImportPreferences({required UserPreferenceLocalStore store})
    : _store = store;

  Future<List<StatementImportReminder>> getReminders() async {
    final preference = await _store.getByKey(kPrefStatementImportReminders);
    final raw = preference?.prefValue;
    if (raw == null || raw.isEmpty) return const [];

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return const [];
      final reminders = <StatementImportReminder>[];
      decoded.forEach((accountId, rawDay) {
        final day = rawDay is int ? rawDay : int.tryParse('$rawDay');
        if (accountId.isNotEmpty && day != null && day >= 1 && day <= 31) {
          reminders.add(
            StatementImportReminder(accountId: accountId, dayOfMonth: day),
          );
        }
      });
      reminders.sort((a, b) => a.accountId.compareTo(b.accountId));
      return reminders;
    } on FormatException {
      return const [];
    }
  }

  Future<void> setReminder(String accountId, int dayOfMonth) async {
    if (accountId.isEmpty || dayOfMonth < 1 || dayOfMonth > 31) {
      throw ArgumentError('La cuenta y el día deben ser válidos.');
    }
    final values = await _readValues();
    values[accountId] = dayOfMonth;
    await _writeValues(values);
  }

  Future<void> removeReminder(String accountId) async {
    final values = await _readValues();
    if (!values.containsKey(accountId)) return;
    values.remove(accountId);
    await _writeValues(values);
  }

  Future<Map<String, int>> _readValues() async {
    final reminders = await getReminders();
    return {
      for (final reminder in reminders) reminder.accountId: reminder.dayOfMonth,
    };
  }

  Future<void> _writeValues(Map<String, int> values) async {
    final now = DateTime.now().toUtc();
    final existing = await _store.getByKey(kPrefStatementImportReminders);
    await _store.upsert(
      UserPreferenceModel(
        prefKey: kPrefStatementImportReminders,
        prefValue: jsonEncode(values),
        createdAt: existing?.createdAt ?? now,
        updatedAt: now,
      ),
    );
  }
}
