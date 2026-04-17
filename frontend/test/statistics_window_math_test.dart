import 'package:flutter_test/flutter_test.dart';

import 'package:pocket_pilot/src/features/statistics/domain/window_math.dart';

void main() {
  group('StatisticsWindow.fromNow', () {
    test('6-month window ending in April 2026', () {
      final w = StatisticsWindow.fromNow(
        months: 6,
        now: DateTime.utc(2026, 4, 17),
      );
      expect(w.months, 6);
      expect(w.windowStart, '2025-11-01'); // N-1 = 5 months back from April
      expect(w.windowEnd, '2026-05-01');   // first day of next month
      expect(w.currentYm, '2026-04');
      // windowMid = start of month at index N~/2 = 3 from windowStart
      expect(w.windowMid, '2026-02-01');
    });

    test('3-month window ending in April 2026', () {
      final w = StatisticsWindow.fromNow(
        months: 3,
        now: DateTime.utc(2026, 4, 1),
      );
      expect(w.windowStart, '2026-02-01');
      expect(w.windowEnd, '2026-05-01');
      expect(w.currentYm, '2026-04');
      expect(w.windowMid, '2026-03-01'); // N~/2 = 1
    });

    test('12-month window crossing years', () {
      final w = StatisticsWindow.fromNow(
        months: 12,
        now: DateTime.utc(2026, 4, 17),
      );
      expect(w.windowStart, '2025-05-01'); // 11 months back
      expect(w.windowEnd, '2026-05-01');
      expect(w.currentYm, '2026-04');
      expect(w.windowMid, '2025-11-01'); // index 6
    });

    test('month sequence is contiguous and length N', () {
      final w = StatisticsWindow.fromNow(
        months: 6,
        now: DateTime.utc(2026, 4, 17),
      );
      expect(w.monthsInWindow, [
        '2025-11',
        '2025-12',
        '2026-01',
        '2026-02',
        '2026-03',
        '2026-04',
      ]);
    });
  });
}
