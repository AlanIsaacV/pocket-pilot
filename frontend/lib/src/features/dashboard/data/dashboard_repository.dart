import 'package:pocket_pilot/src/features/dashboard/data/dashboard_local_store.dart';
import 'package:pocket_pilot/src/features/dashboard/domain/account_balance_dto.dart';
import 'package:pocket_pilot/src/features/dashboard/domain/category_spend_dto.dart';
import 'package:pocket_pilot/src/features/dashboard/domain/dashboard_metrics.dart';
import 'package:pocket_pilot/src/features/dashboard/domain/goal_target_dto.dart';

class DashboardRepository {
  final DashboardLocalStore _local;

  DashboardRepository({required DashboardLocalStore local}) : _local = local;

  Future<List<AccountBalanceDTO>> getBalancesPerAccount({
    Set<String>? accountIds,
  }) =>
      _local.getBalancesPerAccount(accountIds: accountIds);

  Future<List<CategorySpendDTO>> getMonthlySpendByCategory(
    String startDate,
    String endDate, {
    Set<String>? accountIds,
    String? currencyCode,
  }) =>
      _local.getMonthlySpendByCategory(
        startDate,
        endDate,
        accountIds: accountIds,
        currencyCode: currencyCode,
      );

  Future<List<GoalTargetDTO>> getTotalTargetInGoals() =>
      _local.getTotalTargetInGoals();

  /// Calculates the four core dashboard metrics grouped by currency.
  ///
  /// Returns a map keyed by currency code. Each entry contains the
  /// metrics computed from accounts and goals in that currency only.
  Future<Map<String, DashboardMetrics>> calculateAllMetrics({
    Set<String>? accountIds,
  }) async {
    final balances = await _local.getBalancesPerAccount(
      accountIds: accountIds,
    );
    final goalTargets = await _local.getTotalTargetInGoals();

    // Build goal target lookup by currency
    final goalsByCurrency = <String, int>{};
    for (final g in goalTargets) {
      goalsByCurrency[g.currencyCode] =
          (goalsByCurrency[g.currencyCode] ?? 0) + g.totalTargetCents;
    }

    // Accumulate metrics per currency
    final netWorth = <String, int>{};
    final liquid = <String, int>{};
    final revolving = <String, int>{};
    final currencies = <String>{};

    for (final b in balances) {
      final cc = b.currencyCode;
      currencies.add(cc);

      netWorth[cc] = (netWorth[cc] ?? 0) + b.balanceCents;

      if (b.accountType == 'bank' || b.accountType == 'cash') {
        liquid[cc] = (liquid[cc] ?? 0) + b.balanceCents;
      }

      if (b.accountType == 'credit_card' && b.creditLimitCents != null) {
        final available = b.creditLimitCents! + b.balanceCents;
        if (available > 0) {
          revolving[cc] = (revolving[cc] ?? 0) + available;
        }
      }
    }

    // Also include currencies that only have goals
    currencies.addAll(goalsByCurrency.keys);

    final result = <String, DashboardMetrics>{};
    for (final cc in currencies) {
      final liquidCents = liquid[cc] ?? 0;
      final goalTarget = goalsByCurrency[cc] ?? 0;
      final safeToSpend = liquidCents - goalTarget;
      final buyingPower = safeToSpend + (revolving[cc] ?? 0);

      result[cc] = DashboardMetrics(
        currencyCode: cc,
        netWorthCents: netWorth[cc] ?? 0,
        liquidAssetsCents: liquidCents,
        safeToSpendCents: safeToSpend,
        buyingPowerCents: buyingPower,
      );
    }

    return result;
  }
}
