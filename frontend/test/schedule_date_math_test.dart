import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_pilot/src/features/transaction_templates/domain/schedule_date_math.dart';

void main() {
  group('nextScheduleDate', () {
    test('MONTHLY clamps end-of-month when next month is shorter', () {
      expect(nextScheduleDate('MONTHLY', '2024-01-31'), '2024-02-29');
    });

    test('YEARLY clamps Feb 29 to Feb 28 on non-leap year', () {
      expect(nextScheduleDate('YEARLY', '2024-02-29'), '2025-02-28');
    });

    test('DAILY increments by one day', () {
      expect(nextScheduleDate('DAILY', '2024-03-01'), '2024-03-02');
    });

    test('WEEKLY increments by seven days', () {
      expect(nextScheduleDate('WEEKLY', '2024-03-01'), '2024-03-08');
    });

    test('throws ArgumentError for unsupported frequency', () {
      expect(
        () => nextScheduleDate('HOURLY', '2024-03-01'),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
