// features/statistics/domain/category_history_dto.dart
import 'package:pocket_pilot/src/features/budgets/domain/budget_status.dart';
import 'package:pocket_pilot/src/features/statistics/domain/category_series_dto.dart';
import 'package:pocket_pilot/src/features/statistics/domain/monthly_point_dto.dart';

class CategoryHistoryDTO {
  final CategorySeriesDTO summary;
  final List<MonthlyPointDTO> points; // length == N, zero-filled
  final BudgetStatus? budget;         // null if no budget or currency mismatch

  const CategoryHistoryDTO({
    required this.summary,
    required this.points,
    this.budget,
  });
}
