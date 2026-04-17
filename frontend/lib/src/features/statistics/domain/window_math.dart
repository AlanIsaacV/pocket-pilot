// features/statistics/domain/window_math.dart
//
// Pure time-window bounds for the Statistics tab. All dates are
// 'YYYY-MM-DD' strings so they compare lexicographically against the
// SQLite `date` column (same contract as `TransactionFilter`).

class StatisticsWindow {
  final int months;        // 3, 6, or 12
  final String windowStart; // inclusive, first day of oldest month
  final String windowEnd;   // exclusive, first day of month AFTER current
  final String windowMid;   // boundary between first/second trend halves
  final String currentYm;   // 'YYYY-MM' of `now`
  final List<String> monthsInWindow; // N contiguous 'YYYY-MM' strings

  const StatisticsWindow._({
    required this.months,
    required this.windowStart,
    required this.windowEnd,
    required this.windowMid,
    required this.currentYm,
    required this.monthsInWindow,
  });

  factory StatisticsWindow.fromNow({
    required int months,
    required DateTime now,
  }) {
    assert(months == 3 || months == 6 || months == 12);
    final y = now.year;
    final m = now.month;

    // First day of current month.
    final startOfCurrent = DateTime.utc(y, m, 1);
    // First day of next month (exclusive upper bound).
    final startOfNext = DateTime.utc(y, m + 1, 1);
    // First day of the oldest month in the window.
    final startOfOldest = DateTime.utc(y, m - (months - 1), 1);
    // Mid boundary: start of month at offset N~/2 from oldest.
    final startOfMid = DateTime.utc(y, m - (months - 1) + (months ~/ 2), 1);

    final list = <String>[];
    for (var i = 0; i < months; i++) {
      final d = DateTime.utc(y, m - (months - 1) + i, 1);
      list.add(_fmtYm(d));
    }

    return StatisticsWindow._(
      months: months,
      windowStart: _fmtDate(startOfOldest),
      windowEnd: _fmtDate(startOfNext),
      windowMid: _fmtDate(startOfMid),
      currentYm: _fmtYm(startOfCurrent),
      monthsInWindow: List.unmodifiable(list),
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
