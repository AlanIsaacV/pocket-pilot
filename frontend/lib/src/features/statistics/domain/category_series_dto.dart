// features/statistics/domain/category_series_dto.dart
import 'package:pocket_pilot/src/features/statistics/domain/trend.dart';

class CategorySeriesDTO {
  final String categoryId;
  final String name;
  final String color;          // hex (e.g. "#A6E3A1")
  final String icon;
  final String kind;           // 'expense' | 'income'
  final String currencyCode;
  final int totalCents;        // already sign-flipped for income
  final int avgMonthlyCents;   // totalCents ~/ N
  final int currentMonthCents; // already sign-flipped for income
  final Trend trend;

  const CategorySeriesDTO({
    required this.categoryId,
    required this.name,
    required this.color,
    required this.icon,
    required this.kind,
    required this.currencyCode,
    required this.totalCents,
    required this.avgMonthlyCents,
    required this.currentMonthCents,
    required this.trend,
  });
}
