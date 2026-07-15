// features/statistics/data/statistics_repository.dart
//
// Orchestrates StatisticsLocalStore + BudgetLocalStore to produce the
// Statistics domain objects. All sign flips, trend computation, avg
// division, and zero-filling live here (not in SQL).

import 'package:flutter/foundation.dart';

import 'package:pocket_pilot/src/features/budgets/data/budget_local_store.dart';
import 'package:pocket_pilot/src/features/budgets/domain/budget.dart';
import 'package:pocket_pilot/src/features/budgets/domain/budget_status.dart';
import 'package:pocket_pilot/src/features/statistics/data/statistics_local_store.dart';
import 'package:pocket_pilot/src/features/statistics/domain/category_history_dto.dart';
import 'package:pocket_pilot/src/features/statistics/domain/category_series_dto.dart';
import 'package:pocket_pilot/src/features/statistics/domain/monthly_point_dto.dart';
import 'package:pocket_pilot/src/features/statistics/domain/tag_category_slice_dto.dart';
import 'package:pocket_pilot/src/features/statistics/domain/tag_history_dto.dart';
import 'package:pocket_pilot/src/features/statistics/domain/tag_summary_dto.dart';
import 'package:pocket_pilot/src/features/statistics/domain/trend.dart';
import 'package:pocket_pilot/src/features/statistics/domain/window_math.dart';

class StatisticsRepository {
  final StatisticsLocalStore _local;
  final BudgetLocalStore _budgetLocal;

  StatisticsRepository({
    required StatisticsLocalStore local,
    required BudgetLocalStore budgetLocal,
  })  : _local = local,
        _budgetLocal = budgetLocal;

  /// Returns summary rows for every category with activity in the
  /// window, already sign-flipped for income and annotated with trend.
  Future<List<CategorySeriesDTO>> getSeriesList({
    required String currencyCode,
    required String windowStart,
    required String windowEnd,
    required String windowMid,
    required String currentYm,
    required int months,
    Set<String>? accountIds,
  }) async {
    final rows = await _local.getCategorySeries(
      currencyCode: currencyCode,
      windowStart: windowStart,
      windowEnd: windowEnd,
      windowMid: windowMid,
      currentYm: currentYm,
      accountIds: accountIds,
    );
    return rows.map((r) => _toSeries(r, months, currencyCode)).toList();
  }

  Future<CategoryHistoryDTO> getHistory({
    required String categoryId,
    required String currencyCode,
    required String from,
    required String to,
    Set<String>? accountIds,
  }) async {
    final window = StatisticsWindow.fromRange(from: from, to: to);

    final seriesRows = await _local.getCategorySeries(
      currencyCode: currencyCode,
      windowStart: window.windowStart,
      windowEnd: window.windowEnd,
      windowMid: window.windowMid,
      currentYm: window.currentYm,
      accountIds: accountIds,
    );
    final summaryRow = seriesRows.firstWhere(
      (r) => r['category_id'] == categoryId,
      orElse: () => <String, dynamic>{},
    );
    // If no activity in the window, fabricate an empty summary so the
    // screen can still render (e.g. user arrived via deep link).
    final summary = summaryRow.isEmpty
        ? _emptySeries(categoryId, currencyCode)
        : _toSeries(summaryRow, window.months, currencyCode);

    final pointRows = await _local.getMonthlySeries(
      categoryId: categoryId,
      currencyCode: currencyCode,
      windowStart: window.windowStart,
      windowEnd: window.windowEnd,
      accountIds: accountIds,
    );
    final byYm = <String, int>{
      for (final r in pointRows)
        r['ym'] as String: _signFlip(_asInt(r['amount_cents']), summary.kind),
    };
    final points = window.monthsInWindow
        .map(
          (ym) => MonthlyPointDTO(
            yearMonth: ym,
            amountCents: byYm[ym] ?? 0,
          ),
        )
        .toList(growable: false);

    final budget = await _loadBudget(categoryId, currencyCode);

    return CategoryHistoryDTO(
      summary: summary,
      points: points,
      budget: budget,
    );
  }

  /// Detalle de un tag para [TagHistoryScreen]. Combina serie mensual
  /// + breakdown por categoría dentro del tag. Comparte la ventana de
  /// `StatisticsWindow.fromRange` con CategoriesTab para mantener
  /// consistencia (mismo cálculo de avg mensual, mismo zero-fill).
  Future<TagHistoryDTO> getTagHistory({
    required String tagName,
    required String currencyCode,
    required String from,
    required String to,
    Set<String>? accountIds,
  }) async {
    final window = StatisticsWindow.fromRange(from: from, to: to);

    final pointRows = await _local.getTagMonthlySeries(
      tagName: tagName,
      currencyCode: currencyCode,
      windowStart: window.windowStart,
      windowEnd: window.windowEnd,
      accountIds: accountIds,
    );
    final byYm = <String, int>{
      for (final r in pointRows) r['ym'] as String: _asInt(r['amount_cents']),
    };
    final points = window.monthsInWindow
        .map(
          (ym) => MonthlyPointDTO(
            yearMonth: ym,
            amountCents: byYm[ym] ?? 0,
          ),
        )
        .toList(growable: false);

    final breakdownRows = await _local.getTagCategoryBreakdown(
      tagName: tagName,
      currencyCode: currencyCode,
      windowStart: window.windowStart,
      windowEnd: window.windowEnd,
      accountIds: accountIds,
    );
    final breakdown = breakdownRows
        .map(
          (r) => TagCategorySliceDTO(
            categoryId: (r['category_id'] as String?) ?? '',
            categoryName: (r['category_name'] as String?) ?? 'Sin categoría',
            categoryColor: (r['category_color'] as String?) ?? '',
            categoryIcon: (r['category_icon'] as String?) ?? '',
            kind: (r['kind'] as String?) ?? 'expense',
            amountCents: _asInt(r['amount_cents']),
          ),
        )
        .toList(growable: false);

    final totalCents = breakdown.fold<int>(0, (s, b) => s + b.amountCents);
    final avg = window.months > 0 ? totalCents ~/ window.months : 0;
    final currentMonth = points.isEmpty ? 0 : points.last.amountCents;

    return TagHistoryDTO(
      tagName: tagName,
      currencyCode: currencyCode,
      totalCents: totalCents,
      avgMonthlyCents: avg,
      currentMonthCents: currentMonth,
      points: points,
      categoryBreakdown: breakdown,
    );
  }

  /// Lista completa de tags con actividad neta positiva (gasto) en la
  /// ventana. Si [currencyCode] es null, agrupa por (tag, currency).
  Future<List<TagSummaryDTO>> listTagsWithTotals({
    required String from,
    required String to,
    Set<String>? accountIds,
    String? currencyCode,
  }) async {
    final window = StatisticsWindow.fromRange(from: from, to: to);
    final rows = await _local.getAllTagsWithTotals(
      windowStart: window.windowStart,
      windowEnd: window.windowEnd,
      accountIds: accountIds,
      currencyCode: currencyCode,
    );
    return rows
        .map(
          (r) => TagSummaryDTO(
            tagName: r['tag_name'] as String,
            currencyCode: r['currency_code'] as String,
            totalCents: _asInt(r['amount_cents']),
          ),
        )
        .toList(growable: false);
  }

  // ---- helpers -----------------------------------------------------

  CategorySeriesDTO _toSeries(
    Map<String, dynamic> r,
    int months,
    String currencyCode,
  ) {
    final kind = r['kind'] as String;
    final total = _signFlip(_asInt(r['total_cents']), kind);
    final current = _signFlip(_asInt(r['current_month_cents']), kind);
    final avg = months > 0 ? total ~/ months : 0;

    return CategorySeriesDTO(
      categoryId: r['category_id'] as String,
      name: r['name'] as String,
      color: (r['color'] as String?) ?? '',
      icon: (r['icon'] as String?) ?? '',
      kind: kind,
      currencyCode: currencyCode,
      totalCents: total,
      avgMonthlyCents: avg,
      currentMonthCents: current,
      trend: computeTrend(currentCents: current, avgCents: avg),
    );
  }

  CategorySeriesDTO _emptySeries(String categoryId, String currencyCode) =>
      CategorySeriesDTO(
        categoryId: categoryId,
        name: '',
        color: '',
        icon: '',
        kind: 'expense',
        currencyCode: currencyCode,
        totalCents: 0,
        avgMonthlyCents: 0,
        currentMonthCents: 0,
        trend: Trend.flat,
      );

  Future<BudgetStatus?> _loadBudget(
    String categoryId,
    String currencyCode,
  ) async {
    try {
      final row = await _budgetLocal.findByCategory(categoryId);
      if (row == null) return null;
      final budget = BudgetModel.fromMap(row);
      if (budget.currencyCode != currencyCode) return null;
      final spent = await _budgetLocal.computeSpentCents(
        budget.categoryId,
        budget.period,
      );
      return BudgetStatus(budget: budget, spentAmountCents: spent);
    } catch (e, st) {
      debugPrint('StatisticsRepository: budget lookup failed: $e\n$st');
      return null;
    }
  }

  static int _signFlip(int value, String kind) =>
      kind == 'income' ? -value : value;

  static int _asInt(Object? raw) {
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    if (raw == null) return 0;
    return int.parse(raw.toString());
  }
}
