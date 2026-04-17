import 'package:pocket_pilot/src/features/dashboard/data/dashboard_local_store.dart';
import 'package:pocket_pilot/src/features/dashboard/domain/account_balance_dto.dart';
import 'package:pocket_pilot/src/features/dashboard/domain/category_spend_dto.dart';
import 'package:pocket_pilot/src/features/dashboard/domain/credit_card_oracle.dart';
import 'package:pocket_pilot/src/features/dashboard/domain/credit_card_payment_dto.dart';
import 'package:pocket_pilot/src/features/dashboard/domain/dashboard_metrics.dart';
import 'package:pocket_pilot/src/features/dashboard/domain/nature_spend_dto.dart';
import 'package:pocket_pilot/src/features/dashboard/domain/tag_spend_dto.dart';
import 'package:pocket_pilot/src/features/goals/domain/goal.dart';

class DashboardRepository {
  final DashboardLocalStore _local;
  final CreditCardOracle _oracle;
  final DateTime Function() _nowProvider;

  DashboardRepository({
    required DashboardLocalStore local,
    CreditCardOracle? oracle,
    DateTime Function()? nowProvider,
  }) : _local = local,
       _oracle = oracle ?? CreditCardOracle(),
       _nowProvider = nowProvider ?? DateTime.now;

  Future<List<AccountBalanceDTO>> getBalancesPerAccount({
    Set<String>? accountIds,
  }) => _local.getBalancesPerAccount(accountIds: accountIds);

  Future<List<CategorySpendDTO>> getMonthlySpendByCategory(
    String startDate,
    String endDate, {
    Set<String>? accountIds,
    String? currencyCode,
  }) => _local.getMonthlySpendByCategory(
    startDate,
    endDate,
    accountIds: accountIds,
    currencyCode: currencyCode,
  );

  Future<List<NatureSpendDTO>> getMonthlySpendByNature(
    String startDate,
    String endDate, {
    Set<String>? accountIds,
    String? currencyCode,
  }) => _local.getMonthlySpendByNature(
    startDate,
    endDate,
    accountIds: accountIds,
    currencyCode: currencyCode,
  );

  Future<List<TagSpendDTO>> getMonthlySpendByTag(
    String startDate,
    String endDate, {
    Set<String>? accountIds,
    String? currencyCode,
  }) => _local.getMonthlySpendByTag(
    startDate,
    endDate,
    accountIds: accountIds,
    currencyCode: currencyCode,
  );

  /// Calculates the four core dashboard metrics grouped by currency.
  ///
  /// Returns a map keyed by currency code. Each entry contains the
  /// metrics computed from accounts and goals in that currency only.
  Future<Map<String, DashboardMetrics>> calculateAllMetrics({
    Set<String>? accountIds,
  }) async {
    final balances = await _local.getBalancesPerAccount(accountIds: accountIds);
    final goals = await _local.getActiveGoals();
    final now = _nowProvider().toUtc();
    final month = DateTime.utc(now.year, now.month, 1);
    final monthEnd = DateTime.utc(now.year, now.month + 1, 0);
    final maxDate = _formatDate(monthEnd);

    final cardAccounts = await _local.getCreditCardAccounts(
      accountIds: accountIds,
    );
    final cardMovements = await _local.getCreditCardMovementsForProjection(
      maxDate,
      accountIds: accountIds,
    );
    final cardNetByCurrency = _oracle
        .estimateNetMonthlyObligation(
          targetMonth: month,
          now: now,
          accounts: cardAccounts,
          movements: cardMovements,
        )
        .netByCurrency;

    // Group goals by currency and compute the monthly required contribution
    // per currency. Only the monthly cuota affects safe-to-spend; the full
    // target represents a long-term savings goal, not a current-month outflow.
    final goalsByCurrency = <String, List<GoalModel>>{};
    for (final g in goals) {
      goalsByCurrency.putIfAbsent(g.currencyCode, () => []).add(g);
    }
    final goalMonthlyByCurrency = <String, int>{
      for (final entry in goalsByCurrency.entries)
        entry.key: GoalMath.totalMonthlyRequiredCents(entry.value, now: now),
    };

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
      final goalMonthly = goalMonthlyByCurrency[cc] ?? 0;
      final estimatedCardPayment = cardNetByCurrency[cc] ?? 0;
      final safeToSpend = liquidCents - goalMonthly - estimatedCardPayment;
      final buyingPower = liquidCents + (revolving[cc] ?? 0);

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

  /// Returns the estimated monthly payment for each credit card.
  ///
  /// Cross-references the oracle's per-account obligations with account
  /// balances to provide card names and currency codes.
  Future<List<CreditCardPaymentDTO>> getCreditCardPayments({
    Set<String>? accountIds,
  }) async {
    final balances = await _local.getBalancesPerAccount(accountIds: accountIds);
    final now = _nowProvider().toUtc();
    final month = DateTime.utc(now.year, now.month, 1);
    final monthEnd = DateTime.utc(now.year, now.month + 1, 0);
    final maxDate = _formatDate(monthEnd);

    final cardAccounts = await _local.getCreditCardAccounts(
      accountIds: accountIds,
    );
    final cardMovements = await _local.getCreditCardMovementsForProjection(
      maxDate,
      accountIds: accountIds,
    );

    final oracleResult = _oracle.estimateNetMonthlyObligation(
      targetMonth: month,
      now: now,
      accounts: cardAccounts,
      movements: cardMovements,
    );

    final balanceByAccountId = <String, AccountBalanceDTO>{};
    for (final b in balances) {
      if (b.accountType == 'credit_card') {
        balanceByAccountId[b.accountId] = b;
      }
    }

    final result = <CreditCardPaymentDTO>[];
    for (final entry in oracleResult.netByAccountId.entries) {
      final balance = balanceByAccountId[entry.key];
      if (balance == null) continue;
      result.add(CreditCardPaymentDTO(
        accountId: entry.key,
        accountName: balance.accountName,
        currencyCode: balance.currencyCode,
        estimatedPaymentCents: entry.value,
      ));
    }

    return result;
  }

  static String _formatDate(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }
}
