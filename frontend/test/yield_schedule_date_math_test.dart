import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_pilot/src/features/yield_configs/domain/yield_schedule_date_math.dart';

void main() {
  test('monthly previous anchor from 2026-03-31 is 2026-02-28', () {
    expect(
      previousScheduleDate('monthly', '2026-03-31', termDays: null),
      '2026-02-28',
    );
  });

  test('at_maturity next date uses term_days', () {
    expect(
      nextScheduleDate('at_maturity', '2026-06-30', termDays: 90),
      '2026-09-28',
    );
  });

  test('days elapsed for monthly from 2026-03-31 is 31', () {
    expect(daysElapsedForPayout('monthly', '2026-03-31', termDays: null), 31);
  });

  test('daily next and previous are symmetric', () {
    final next = nextScheduleDate('daily', '2026-04-10', termDays: null);
    expect(next, '2026-04-11');
    expect(previousScheduleDate('daily', next, termDays: null), '2026-04-10');
  });
}
