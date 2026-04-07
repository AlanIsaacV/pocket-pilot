import 'dart:convert';
import 'dart:developer' as dev;

import 'package:pocket_pilot/src/features/ai_assistant/domain/ai_tool_result.dart';
import 'package:pocket_pilot/src/features/dashboard/data/dashboard_local_store.dart';
import 'package:pocket_pilot/src/features/dashboard/data/dashboard_repository.dart';

class FinancialSummaryTool {
  final DashboardRepository _dashboardRepo;
  final DashboardLocalStore _dashboardLocal;

  FinancialSummaryTool({
    required DashboardRepository dashboardRepo,
    required DashboardLocalStore dashboardLocal,
  }) : _dashboardRepo = dashboardRepo,
       _dashboardLocal = dashboardLocal;

  Future<AIToolResult> execute(Map<String, dynamic> args) async {
    try {
      final queryType = args['query_type'] as String;
      final accountId = args['account_id'] as String?;
      final categoryId = args['category_id'] as String?;
      final period = args['period'] as String?;

      final now = DateTime.now();
      final year = period != null ? int.parse(period.split('-')[0]) : now.year;
      final month = period != null
          ? int.parse(period.split('-')[1])
          : now.month;
      final startDate = '$year-${month.toString().padLeft(2, '0')}-01';
      final lastDay = DateTime(year, month + 1, 0).day;
      final endDate =
          '$year-${month.toString().padLeft(2, '0')}-${lastDay.toString().padLeft(2, '0')}';

      final accountIds = accountId != null ? <String>{accountId} : null;

      switch (queryType) {
        case 'account_balance':
          final balances = await _dashboardLocal.getBalancesPerAccount(
            accountIds: accountIds,
          );
          final data = balances
              .map(
                (b) => {
                  'account_name': b.accountName,
                  'account_type': b.accountType,
                  'balance_cents': b.balanceCents,
                  'currency_code': b.currencyCode,
                },
              )
              .toList();
          return AIToolResult(
            success: true,
            content: jsonEncode({'balances': data}),
          );

        case 'monthly_expenses':
          final spends = await _dashboardLocal.getMonthlySpendByCategory(
            startDate,
            endDate,
            accountIds: accountIds,
          );
          final expenseOnly = spends.where((s) => s.spentCents > 0).toList();
          final totalCents = expenseOnly.fold<int>(
            0,
            (sum, s) => sum + s.spentCents,
          );
          return AIToolResult(
            success: true,
            content: jsonEncode({
              'period': '$year-${month.toString().padLeft(2, '0')}',
              'total_expense_cents': totalCents,
              'by_category': expenseOnly
                  .map(
                    (s) => {
                      'category_name': s.categoryName ?? 'Sin categoria',
                      'spent_cents': s.spentCents,
                      'currency_code': s.currencyCode,
                    },
                  )
                  .toList(),
            }),
          );

        case 'monthly_income':
          final spends = await _dashboardLocal.getMonthlySpendByCategory(
            startDate,
            endDate,
            accountIds: accountIds,
          );
          final incomeOnly = spends.where((s) => s.spentCents < 0).toList();
          final totalCents = incomeOnly.fold<int>(
            0,
            (sum, s) => sum + s.spentCents.abs(),
          );
          return AIToolResult(
            success: true,
            content: jsonEncode({
              'period': '$year-${month.toString().padLeft(2, '0')}',
              'total_income_cents': totalCents,
            }),
          );

        case 'category_expenses':
          final spends = await _dashboardLocal.getMonthlySpendByCategory(
            startDate,
            endDate,
            accountIds: accountIds,
          );
          var filtered = spends.where((s) => s.spentCents > 0).toList();
          if (categoryId != null) {
            filtered = filtered
                .where((s) => s.categoryId == categoryId)
                .toList();
          }
          return AIToolResult(
            success: true,
            content: jsonEncode({
              'period': '$year-${month.toString().padLeft(2, '0')}',
              'categories': filtered
                  .map(
                    (s) => {
                      'category_id': s.categoryId,
                      'category_name': s.categoryName ?? 'Sin categoria',
                      'spent_cents': s.spentCents,
                      'currency_code': s.currencyCode,
                    },
                  )
                  .toList(),
            }),
          );

        case 'buying_power':
        case 'liquidity':
          final metrics = await _dashboardRepo.calculateAllMetrics(
            accountIds: accountIds,
          );
          final data = metrics.entries
              .map(
                (e) => {
                  'currency_code': e.key,
                  'net_worth_cents': e.value.netWorthCents,
                  'liquid_assets_cents': e.value.liquidAssetsCents,
                  'safe_to_spend_cents': e.value.safeToSpendCents,
                  'buying_power_cents': e.value.buyingPowerCents,
                },
              )
              .toList();
          return AIToolResult(
            success: true,
            content: jsonEncode({'metrics': data}),
          );

        default:
          return AIToolResult(
            success: false,
            content: jsonEncode({
              'error': 'query_type no reconocido: $queryType',
            }),
          );
      }
    } catch (e) {
      dev.log('FinancialSummaryTool error: $e');
      return AIToolResult(
        success: false,
        content: jsonEncode({'error': 'Error en consulta financiera: $e'}),
      );
    }
  }
}
