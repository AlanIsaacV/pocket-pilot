String nextScheduleDate(
  String frequency,
  String currentDate, {
  required int? termDays,
}) {
  final normalized = frequency.trim().toLowerCase();
  final date = DateTime.parse(currentDate);

  switch (normalized) {
    case 'daily':
      return _formatDate(date.add(const Duration(days: 1)));
    case 'weekly':
      return _formatDate(date.add(const Duration(days: 7)));
    case 'monthly':
      return _formatDate(_addMonthsClamped(date, 1));
    case 'at_maturity':
      if (termDays == null || termDays <= 0) {
        throw ArgumentError.value(termDays, 'termDays', 'termDays must be > 0');
      }
      return _formatDate(date.add(Duration(days: termDays)));
    default:
      throw ArgumentError.value(
        frequency,
        'frequency',
        'Unsupported frequency. Expected daily, weekly, monthly, or at_maturity.',
      );
  }
}

String previousScheduleDate(
  String frequency,
  String currentDate, {
  required int? termDays,
}) {
  final normalized = frequency.trim().toLowerCase();
  final date = DateTime.parse(currentDate);

  switch (normalized) {
    case 'daily':
      return _formatDate(date.subtract(const Duration(days: 1)));
    case 'weekly':
      return _formatDate(date.subtract(const Duration(days: 7)));
    case 'monthly':
      return _formatDate(_addMonthsClamped(date, -1));
    case 'at_maturity':
      if (termDays == null || termDays <= 0) {
        throw ArgumentError.value(termDays, 'termDays', 'termDays must be > 0');
      }
      return _formatDate(date.subtract(Duration(days: termDays)));
    default:
      throw ArgumentError.value(
        frequency,
        'frequency',
        'Unsupported frequency. Expected daily, weekly, monthly, or at_maturity.',
      );
  }
}

int daysElapsedForPayout(
  String frequency,
  String cursorDate, {
  required int? termDays,
}) {
  final previous = DateTime.parse(
    previousScheduleDate(frequency, cursorDate, termDays: termDays),
  );
  final cursor = DateTime.parse(cursorDate);
  return cursor.difference(previous).inDays;
}

DateTime _addMonthsClamped(DateTime date, int months) {
  final monthIndex = date.month - 1 + months;
  final year = date.year + (monthIndex ~/ 12);
  var month = (monthIndex % 12) + 1;
  if (month <= 0) {
    month += 12;
  }

  final maxDay = DateTime(year, month + 1, 0).day;
  final day = date.day > maxDay ? maxDay : date.day;
  return DateTime.utc(year, month, day);
}

String _formatDate(DateTime date) {
  final y = date.year.toString().padLeft(4, '0');
  final m = date.month.toString().padLeft(2, '0');
  final d = date.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}
