// features/statistics/domain/tag_history_dto.dart
//
// Detalle de un solo tag en la ventana actual: totales agregados,
// serie mensual zero-fill, y desglose por categoría.

import 'package:pocket_pilot/src/features/statistics/domain/monthly_point_dto.dart';
import 'package:pocket_pilot/src/features/statistics/domain/tag_category_slice_dto.dart';

class TagHistoryDTO {
  final String tagName;
  final String currencyCode;
  final int totalCents; // signo: gastos +, ingresos -
  final int avgMonthlyCents; // totalCents ~/ months
  final int currentMonthCents;
  final List<MonthlyPointDTO> points; // length == months, zero-filled
  final List<TagCategorySliceDTO> categoryBreakdown; // desc por |amount|

  const TagHistoryDTO({
    required this.tagName,
    required this.currencyCode,
    required this.totalCents,
    required this.avgMonthlyCents,
    required this.currentMonthCents,
    required this.points,
    required this.categoryBreakdown,
  });
}
