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
  }) async {
    final rows = await _local.getCategorySeries(
      currencyCode: currencyCode,
      windowStart: windowStart,
      windowEnd: windowEnd,
      windowMid: windowMid,
      currentYm: currentYm,
    );
    return rows.map((r) => _toSeries(r, months, currencyCode)).toList();
  }

  Future<CategoryHistoryDTO> getHistory({
    required String categoryId,
    required String currencyCode,
    required int months,
    required DateTime now,
  }) async {
    final window = StatisticsWindow.fromNow(months: months, now: now);

    final seriesRows = await _local.getCategorySeries(
      currencyCode: currencyCode,
      windowStart: window.windowStart,
      windowEnd: window.windowEnd,
      windowMid: window.windowMid,
      currentYm: window.currentYm,
    );
    final summaryRow = seriesRows.firstWhere(
      (r) => r['category_id'] == categoryId,
      orElse: () => <String, dynamic>{},
    );
    // If no activity in the window, fabricate an empty summary so the
    // screen can still render (e.g. user arrived via deep link).
    final summary = summaryRow.isEmpty
        ? _emptySeries(categoryId, currencyCode)
        : _toSeries(summaryRow, months, currencyCode);

    final pointRows = await _local.getMonthlySeries(
      categoryId: categoryId,
      currencyCode: currencyCode,
      windowStart: window.windowStart,
      windowEnd: window.windowEnd,
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

  // ---- helpers -----------------------------------------------------

  CategorySeriesDTO _toSeries(
    Map<String, dynamic> r,
    int months,
    String currencyCode,
  ) {
    final kind = r['kind'] as String;
    final totalSigned = _asInt(r['total_cents']);
    final currentSigned = _asInt(r['current_month_cents']);
    final firstHalfSigned = _asInt(r['first_half_cents']);
    final secondHalfSigned = _asInt(r['second_half_cents']);

    final total = _signFlip(totalSigned, kind);
    final current = _signFlip(currentSigned, kind);
    final first = _signFlip(firstHalfSigned, kind);
    final second = _signFlip(secondHalfSigned, kind);

    return CategorySeriesDTO(
      categoryId: r['category_id'] as String,
      name: r['name'] as String,
      color: (r['color'] as String?) ?? '',
      icon: (r['icon'] as String?) ?? '',
      kind: kind,
      currencyCode: currencyCode,
      totalCents: total,
      avgMonthlyCents: months > 0 ? total ~/ months : 0,
      currentMonthCents: current,
      trend: computeTrend(
        firstHalfCents: first,
        secondHalfCents: second,
      ),
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
