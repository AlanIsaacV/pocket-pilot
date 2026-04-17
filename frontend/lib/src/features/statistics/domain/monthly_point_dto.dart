// features/statistics/domain/monthly_point_dto.dart
class MonthlyPointDTO {
  final String yearMonth; // 'YYYY-MM'
  final int amountCents;  // already sign-flipped for income

  const MonthlyPointDTO({
    required this.yearMonth,
    required this.amountCents,
  });
}
