import 'package:pocket_pilot/src/core/db/database_helper.dart';
import 'package:pocket_pilot/src/core/notifications/in_app_notification.dart';
import 'package:pocket_pilot/src/core/notifications/statement_import_preferences.dart';
import 'package:pocket_pilot/src/features/transaction_templates/domain/schedule_date_math.dart';

/// Pure statement-import projection used by the SQLite-backed repository.
List<InAppNotification> projectStatementImportEvents({
  required List<StatementImportReminder> reminders,
  required Map<String, String> activeAccountNames,
  required DateTime windowStart,
  required DateTime windowEnd,
}) {
  final events = <InAppNotification>[];
  for (final reminder in reminders) {
    final accountName = activeAccountNames[reminder.accountId];
    if (accountName == null) continue;
    for (var year = windowStart.year, month = windowStart.month; ;) {
      final maxDay = DateTime(year, month + 1, 0).day;
      final date = DateTime(year, month, reminder.dayOfMonth.clamp(1, maxDay));
      if (!date.isBefore(windowStart) && !date.isAfter(windowEnd)) {
        events.add(
          InAppNotification(
            id: '',
            title: 'Importa el estado de cuenta de $accountName',
            subtitle: 'Mantén tus movimientos al día.',
            date: date,
            type: 'STATEMENT_IMPORT',
            sourceId: reminder.accountId,
            createdAt: DateTime.now(),
          ),
        );
      }
      if (year == windowEnd.year && month == windowEnd.month) break;
      month++;
      if (month == 13) {
        month = 1;
        year++;
      }
    }
  }
  return events;
}

/// Read-only repository that projects future financial events from SQLite.
///
/// Queries `accounts` and `transaction_templates` directly (no LocalStore)
/// because it is a cross-cutting read-only projection. Never writes.
class NotificationRepository {
  final DatabaseHelper _db;
  final StatementImportPreferences _statementImportPreferences;

  NotificationRepository({
    required DatabaseHelper db,
    required StatementImportPreferences statementImportPreferences,
  }) : _db = db,
       _statementImportPreferences = statementImportPreferences;

  // ---------------------------------------------------------------------------
  // Internal helpers
  // ---------------------------------------------------------------------------

  /// Projects [dueDay] into the given [year]/[month], clamping to month end.
  /// Returns a date-only DateTime (no time component).
  DateTime _projectDueDay(int dueDay, int year, int month) {
    final maxDay = DateTime(year, month + 1, 0).day;
    final clamped = dueDay > maxDay ? maxDay : dueDay;
    return DateTime(year, month, clamped);
  }

  /// Iterates from [nextDate] by [frequency], collecting occurrences within
  /// [windowStart]..[windowEnd]. Stops at [endDate] if non-null.
  ///
  /// Uses [nextScheduleDate] from schedule_date_math.dart (string-based API).
  /// Fast-forwards stale cursors for MONTHLY/YEARLY to avoid unnecessary loops.
  List<DateTime> _projectTemplateOccurrences(
    String nextDate,
    String frequency,
    String? endDate,
    DateTime windowStart,
    DateTime windowEnd,
  ) {
    final results = <DateTime>[];
    final endLimit = endDate != null ? DateTime.parse(endDate) : null;
    var cursor = nextDate;

    // Fast-forward stale cursors: skip months/years arithmetically.
    var cursorDt = DateTime.parse(cursor);
    if (cursorDt.isBefore(windowStart)) {
      if (frequency == 'MONTHLY') {
        final monthsDiff =
            (windowStart.year - cursorDt.year) * 12 +
            (windowStart.month - cursorDt.month) -
            1;
        if (monthsDiff > 0) {
          for (var i = 0; i < monthsDiff; i++) {
            cursor = nextScheduleDate(frequency, cursor);
          }
          cursorDt = DateTime.parse(cursor);
        }
      } else if (frequency == 'YEARLY') {
        final yearsDiff = windowStart.year - cursorDt.year - 1;
        if (yearsDiff > 0) {
          for (var i = 0; i < yearsDiff; i++) {
            cursor = nextScheduleDate(frequency, cursor);
          }
          cursorDt = DateTime.parse(cursor);
        }
      }
    }

    // Iterate until past window end (with safety limit to avoid infinite loops).
    const maxIterations = 500;
    for (var i = 0; i < maxIterations; i++) {
      cursorDt = DateTime.parse(cursor);

      if (cursorDt.isAfter(windowEnd)) break;
      if (endLimit != null && cursorDt.isAfter(endLimit)) break;

      if (!cursorDt.isBefore(windowStart)) {
        results.add(cursorDt);
      }

      cursor = nextScheduleDate(frequency, cursor);
    }

    return results;
  }

  // ---------------------------------------------------------------------------
  // Credit card due-date projection
  // ---------------------------------------------------------------------------

  Future<List<Map<String, dynamic>>> _queryCreditCards() async {
    final db = await _db.database;
    return db.rawQuery('''
      SELECT id, name, payment_due_day
      FROM accounts
      WHERE type = 'credit_card'
        AND deleted_at IS NULL
        AND payment_due_day IS NOT NULL
    ''');
  }

  List<DateTime> _projectCreditCardDates(
    int dueDay,
    DateTime windowStart,
    DateTime windowEnd,
  ) {
    final results = <DateTime>[];

    // Project into current month, next month, and the month after (covers ~90 days).
    for (var offset = 0; offset <= 2; offset++) {
      final monthIndex = windowStart.month - 1 + offset;
      final year = windowStart.year + (monthIndex ~/ 12);
      final month = (monthIndex % 12) + 1;
      final projected = _projectDueDay(dueDay, year, month);

      if (!projected.isBefore(windowStart) && !projected.isAfter(windowEnd)) {
        results.add(projected);
      }
    }

    return results;
  }

  Future<Map<String, String>> _queryActiveAccountNames() async {
    final db = await _db.database;
    final rows = await db.rawQuery('''
      SELECT id, name
      FROM accounts
      WHERE deleted_at IS NULL
    ''');
    return {for (final row in rows) row['id'] as String: row['name'] as String};
  }

  // ---------------------------------------------------------------------------
  // Template projection (shared by subscriptions and obligations)
  // ---------------------------------------------------------------------------

  Future<List<Map<String, dynamic>>> _querySubscriptions() async {
    final db = await _db.database;
    return db.rawQuery('''
      SELECT id, name, amount_cents, frequency, next_date, end_date
      FROM transaction_templates
      WHERE deleted_at IS NULL
        AND is_active = 1
        AND is_auto_charge = 1
        AND frequency IS NOT NULL
        AND next_date IS NOT NULL
    ''');
  }

  Future<List<Map<String, dynamic>>> _queryObligations() async {
    final db = await _db.database;
    return db.rawQuery('''
      SELECT id, name, amount_cents, frequency, next_date, end_date
      FROM transaction_templates
      WHERE deleted_at IS NULL
        AND is_active = 1
        AND is_auto_charge = 0
        AND frequency IS NOT NULL
        AND next_date IS NOT NULL
        AND nature IN ('obligation', 'required')
    ''');
  }

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Returns all upcoming financial events within [daysToLookAhead] from
  /// [fromDate], sorted by date ascending. Used by the in-app notification
  /// center UI.
  Future<List<InAppNotification>> getUpcomingEvents(
    DateTime fromDate,
    int daysToLookAhead,
  ) async {
    final windowEnd = fromDate.add(Duration(days: daysToLookAhead));
    final events = <InAppNotification>[];

    // 1. Credit cards
    final cards = await _queryCreditCards();
    for (final card in cards) {
      final dueDay = card['payment_due_day'] as int;
      final name = card['name'] as String;
      for (final date in _projectCreditCardDates(dueDay, fromDate, windowEnd)) {
        events.add(
          InAppNotification(
            id: '',
            title: '$name vence el ${date.day}',
            subtitle: '',
            date: date,
            type: 'CREDIT_CARD',
            sourceId: card['id'] as String,
            createdAt: DateTime.now(),
          ),
        );
      }
    }

    // 2. Subscriptions (auto-charge)
    final subs = await _querySubscriptions();
    for (final sub in subs) {
      final name = sub['name'] as String;
      final amountCents = sub['amount_cents'] as int?;
      final sourceId = sub['id'] as String;
      final occurrences = _projectTemplateOccurrences(
        sub['next_date'] as String,
        sub['frequency'] as String,
        sub['end_date'] as String?,
        fromDate,
        windowEnd,
      );
      for (final date in occurrences) {
        events.add(
          InAppNotification(
            id: '',
            title: 'Cargo de $name',
            subtitle: amountCents != null
                ? '\$${(amountCents / 100).toStringAsFixed(2)}'
                : '',
            date: date,
            type: 'SUBSCRIPTION',
            amountCents: amountCents,
            sourceId: sourceId,
            createdAt: DateTime.now(),
          ),
        );
      }
    }

    // 3. Manual obligations
    final obligations = await _queryObligations();
    for (final ob in obligations) {
      final name = ob['name'] as String;
      final amountCents = ob['amount_cents'] as int?;
      final sourceId = ob['id'] as String;
      final occurrences = _projectTemplateOccurrences(
        ob['next_date'] as String,
        ob['frequency'] as String,
        ob['end_date'] as String?,
        fromDate,
        windowEnd,
      );
      for (final date in occurrences) {
        events.add(
          InAppNotification(
            id: '',
            title: 'Pago de $name',
            subtitle: amountCents != null
                ? '\$${(amountCents / 100).toStringAsFixed(2)}'
                : '',
            date: date,
            type: 'OBLIGATION',
            amountCents: amountCents,
            sourceId: sourceId,
            createdAt: DateTime.now(),
          ),
        );
      }
    }

    // 4. Statement-import reminders, configured locally per account.
    final reminders = await _statementImportPreferences.getReminders();
    if (reminders.isNotEmpty) {
      final accountNames = await _queryActiveAccountNames();
      events.addAll(
        projectStatementImportEvents(
          reminders: reminders,
          activeAccountNames: accountNames,
          windowStart: fromDate,
          windowEnd: windowEnd,
        ),
      );
    }

    events.sort((a, b) => a.date.compareTo(b.date));
    return events;
  }

  /// Returns date-only DateTimes of all credit card due dates within the window.
  Future<Set<DateTime>> getCreditCardDueDates(
    DateTime fromDate,
    int daysAhead,
  ) async {
    final windowEnd = fromDate.add(Duration(days: daysAhead));
    final dates = <DateTime>{};

    final cards = await _queryCreditCards();
    for (final card in cards) {
      final dueDay = card['payment_due_day'] as int;
      dates.addAll(_projectCreditCardDates(dueDay, fromDate, windowEnd));
    }

    return dates;
  }

  /// Returns date-only DateTimes of all subscription charge dates within the window.
  Future<Set<DateTime>> getSubscriptionDates(
    DateTime fromDate,
    int daysAhead,
  ) async {
    final windowEnd = fromDate.add(Duration(days: daysAhead));
    final dates = <DateTime>{};

    final subs = await _querySubscriptions();
    for (final sub in subs) {
      dates.addAll(
        _projectTemplateOccurrences(
          sub['next_date'] as String,
          sub['frequency'] as String,
          sub['end_date'] as String?,
          fromDate,
          windowEnd,
        ),
      );
    }

    return dates;
  }

  /// Returns date-only DateTimes of all obligation dates within the window.
  Future<Set<DateTime>> getObligationDates(
    DateTime fromDate,
    int daysAhead,
  ) async {
    final windowEnd = fromDate.add(Duration(days: daysAhead));
    final dates = <DateTime>{};

    final obligations = await _queryObligations();
    for (final ob in obligations) {
      dates.addAll(
        _projectTemplateOccurrences(
          ob['next_date'] as String,
          ob['frequency'] as String,
          ob['end_date'] as String?,
          fromDate,
          windowEnd,
        ),
      );
    }

    return dates;
  }

  /// Returns date-only statement-import reminder dates within the window.
  Future<Set<DateTime>> getStatementImportDates(
    DateTime fromDate,
    int daysAhead,
  ) async {
    final windowEnd = fromDate.add(Duration(days: daysAhead));
    final reminders = await _statementImportPreferences.getReminders();
    final activeAccounts = await _queryActiveAccountNames();
    return projectStatementImportEvents(
      reminders: reminders,
      activeAccountNames: activeAccounts,
      windowStart: fromDate,
      windowEnd: windowEnd,
    ).map((event) => event.date).toSet();
  }
}
