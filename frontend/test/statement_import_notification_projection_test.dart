import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_pilot/src/core/notifications/notification_repository.dart';
import 'package:pocket_pilot/src/core/notifications/statement_import_preferences.dart';

void main() {
  const reminder = StatementImportReminder(
    accountId: 'rappicard',
    dayOfMonth: 15,
  );
  final start = DateTime(2026, 7, 10);
  final end = DateTime(2026, 8, 9);

  test('projects STATEMENT_IMPORT for the configured next occurrence', () {
    final events = projectStatementImportEvents(
      reminders: const [reminder],
      activeAccountNames: const {'rappicard': 'RappiCard'},
      windowStart: start,
      windowEnd: end,
    );
    expect(events.single.type, 'STATEMENT_IMPORT');
    expect(events.single.sourceId, 'rappicard');
    expect(events.single.date, DateTime(2026, 7, 15));
  });

  test('does not project STATEMENT_IMPORT when unconfigured', () {
    final events = projectStatementImportEvents(
      reminders: const [],
      activeAccountNames: const {'rappicard': 'RappiCard'},
      windowStart: start,
      windowEnd: end,
    );
    expect(events, isEmpty);
  });

  test('re-projection produces the same source-date-type dedup key', () {
    final first = projectStatementImportEvents(
      reminders: const [reminder],
      activeAccountNames: const {'rappicard': 'RappiCard'},
      windowStart: start,
      windowEnd: end,
    );
    final second = projectStatementImportEvents(
      reminders: const [reminder],
      activeAccountNames: const {'rappicard': 'RappiCard'},
      windowStart: start,
      windowEnd: end,
    );
    final keys = [
      ...first,
      ...second,
    ].map((event) => '${event.sourceId}|${event.date}|${event.type}').toSet();
    expect(keys, hasLength(1));
  });
}
