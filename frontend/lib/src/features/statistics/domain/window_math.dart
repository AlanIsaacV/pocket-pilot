// features/statistics/domain/window_math.dart
//
// Pure time-window bounds for the Statistics / Cashflow screens.
// Built from a user-selected date range (YYYY-MM-DD strings matching
// the SQLite `date` column's lexicographic contract).

class StatisticsWindow {
  final int months;        // count of distinct calendar months touched
  final String windowStart; // inclusive lower bound
  final String windowEnd;   // exclusive upper bound (to + 1 day)
  final String windowMid;   // midpoint date (trend split)
  final String currentYm;   // 'YYYY-MM' of the last month in the range
  final List<String> monthsInWindow; // contiguous 'YYYY-MM' list

  const StatisticsWindow._({
    required this.months,
    required this.windowStart,
    required this.windowEnd,
    required this.windowMid,
    required this.currentYm,
    required this.monthsInWindow,
  });

  /// Build a window from an explicit YYYY-MM-DD range (inclusive on both
  /// ends). The SQL upper bound is computed as `to + 1 day` so `t.date <
  /// windowEnd` includes transactions dated exactly on `to`.
  factory StatisticsWindow.fromRange({
    required String from,
    required String to,
  }) {
    final fromD = _parseYmd(from);
    final toD = _parseYmd(to);
    assert(!toD.isBefore(fromD), 'to must be >= from');

    // Exclusive upper bound: day after `to`.
    final endD = toD.add(const Duration(days: 1));

    // monthsInWindow: every YM from from's month to to's month.
    final list = <String>[];
    var y = fromD.year;
    var m = fromD.month;
    while (y < toD.year || (y == toD.year && m <= toD.month)) {
      list.add(_fmtYm(DateTime.utc(y, m, 1)));
      m++;
      if (m > 12) {
        m = 1;
        y++;
      }
    }
    final months = list.length;

    // windowMid: halfway through the span (day-accurate, for trend split).
    final midDays = toD.difference(fromD).inDays ~/ 2;
    final midD = fromD.add(Duration(days: midDays));

    return StatisticsWindow._(
      months: months,
      windowStart: _fmtDate(fromD),
      windowEnd: _fmtDate(endD),
      windowMid: _fmtDate(midD),
      currentYm: _fmtYm(toD),
      monthsInWindow: List.unmodifiable(list),
    );
  }

  static DateTime _parseYmd(String s) {
    final parts = s.split('-');
    return DateTime.utc(
      int.parse(parts[0]),
      int.parse(parts[1]),
      int.parse(parts[2]),
    );
  }

  static String _fmtDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}'
      '-${d.month.toString().padLeft(2, '0')}'
      '-${d.day.toString().padLeft(2, '0')}';

  static String _fmtYm(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}'
      '-${d.month.toString().padLeft(2, '0')}';
}
