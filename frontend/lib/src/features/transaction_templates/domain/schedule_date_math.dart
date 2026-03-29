String nextScheduleDate(String frequency, String currentDate) {
  final date = DateTime.parse(currentDate);

  switch (frequency) {
    case 'DAILY':
      return _formatDate(date.add(const Duration(days: 1)));
    case 'WEEKLY':
      return _formatDate(date.add(const Duration(days: 7)));
    case 'MONTHLY':
      return _formatDate(_addMonthsClamped(date, 1));
    case 'YEARLY':
      return _formatDate(_addYearsClamped(date, 1));
    default:
      throw ArgumentError.value(
        frequency,
        'frequency',
        'Unsupported frequency. Expected DAILY, WEEKLY, MONTHLY, or YEARLY.',
      );
  }
}

DateTime _addMonthsClamped(DateTime date, int months) {
  final monthIndex = date.month - 1 + months;
  final year = date.year + (monthIndex ~/ 12);
  final month = (monthIndex % 12) + 1;
  final day = _clampDay(date.day, year, month);

  return DateTime(year, month, day);
}

DateTime _addYearsClamped(DateTime date, int years) {
  final year = date.year + years;
  final month = date.month;
  final day = _clampDay(date.day, year, month);

  return DateTime(year, month, day);
}

int _clampDay(int day, int year, int month) {
  final maxDay = DateTime(year, month + 1, 0).day;
  return day > maxDay ? maxDay : day;
}

String _formatDate(DateTime date) {
  final year = date.year.toString().padLeft(4, '0');
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '$year-$month-$day';
}
