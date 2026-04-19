import 'package:flutter_test/flutter_test.dart';

import 'package:pocket_pilot/src/features/statistics/domain/window_math.dart';

void main() {
  group('StatisticsWindow.fromRange', () {
    test('single-month range (March 2026)', () {
      final w = StatisticsWindow.fromRange(
        from: '2026-03-01',
        to: '2026-03-31',
      );
      expect(w.months, 1);
      expect(w.windowStart, '2026-03-01');
      expect(w.windowEnd, '2026-04-01'); // to + 1 day
      expect(w.currentYm, '2026-03');
      expect(w.monthsInWindow, ['2026-03']);
    });

    test('full-year range (2024)', () {
      final w = StatisticsWindow.fromRange(
        from: '2024-01-01',
        to: '2024-12-31',
      );
      expect(w.months, 12);
      expect(w.windowStart, '2024-01-01');
      expect(w.windowEnd, '2025-01-01');
      expect(w.currentYm, '2024-12');
      expect(w.monthsInWindow.length, 12);
      expect(w.monthsInWindow.first, '2024-01');
      expect(w.monthsInWindow.last, '2024-12');
    });

    test('cross-year range', () {
      final w = StatisticsWindow.fromRange(
        from: '2025-11-01',
        to: '2026-04-30',
      );
      expect(w.months, 6);
      expect(w.windowStart, '2025-11-01');
      expect(w.windowEnd, '2026-05-01');
      expect(w.currentYm, '2026-04');
      expect(w.monthsInWindow, [
        '2025-11',
        '2025-12',
        '2026-01',
        '2026-02',
        '2026-03',
        '2026-04',
      ]);
    });

    test('day-precision custom range', () {
      final w = StatisticsWindow.fromRange(
        from: '2026-03-15',
        to: '2026-04-20',
      );
      expect(w.months, 2);
      expect(w.windowStart, '2026-03-15');
      expect(w.windowEnd, '2026-04-21');
      expect(w.currentYm, '2026-04');
      expect(w.monthsInWindow, ['2026-03', '2026-04']);
    });
  });
}
