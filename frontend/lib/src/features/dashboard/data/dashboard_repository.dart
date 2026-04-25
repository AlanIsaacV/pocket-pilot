import 'package:pocket_pilot/src/features/dashboard/data/dashboard_local_store.dart';
import 'package:pocket_pilot/src/features/dashboard/domain/account_balance_dto.dart';
import 'package:pocket_pilot/src/features/dashboard/domain/category_spend_dto.dart';
import 'package:pocket_pilot/src/features/dashboard/domain/credit_card_oracle.dart';
import 'package:pocket_pilot/src/features/dashboard/domain/credit_card_payment_dto.dart';
import 'package:pocket_pilot/src/features/dashboard/domain/dashboard_metrics.dart';
import 'package:pocket_pilot/src/features/dashboard/domain/nature_spend_dto.dart';
import 'package:pocket_pilot/src/features/dashboard/domain/tag_spend_dto.dart';
import 'package:pocket_pilot/src/features/goals/domain/goal.dart';
import 'package:pocket_pilot/src/features/investments/data/investment_holding_local_store.dart';
import 'package:pocket_pilot/src/features/investments/data/investment_lot_local_store.dart';
import 'package:pocket_pilot/src/features/investments/data/investment_split_local_store.dart';
import 'package:pocket_pilot/src/features/investments/data/market_price_local_store.dart';
import 'package:pocket_pilot/src/features/investments/domain/investment_holding.dart';
import 'package:pocket_pilot/src/features/investments/domain/investment_lot.dart';
import 'package:pocket_pilot/src/features/investments/domain/investment_split.dart';
import 'package:pocket_pilot/src/features/investments/domain/market_price.dart';
import 'package:pocket_pilot/src/features/investments/domain/portfolio_distribution.dart';

class DashboardRepository {
  final DashboardLocalStore _local;
  final CreditCardOracle _oracle;
  final DateTime Function() _nowProvider;
  final InvestmentHoldingLocalStore? _holdingStore;
  final InvestmentLotLocalStore? _lotStore;
  final InvestmentSplitLocalStore? _splitStore;
  final MarketPriceLocalStore? _marketPriceStore;

  DashboardRepository({
    required DashboardLocalStore local,
    CreditCardOracle? oracle,
    DateTime Function()? nowProvider,
    InvestmentHoldingLocalStore? holdingStore,
    InvestmentLotLocalStore? lotStore,
    InvestmentSplitLocalStore? splitStore,
    MarketPriceLocalStore? marketPriceStore,
  }) : _local = local,
       _oracle = oracle ?? CreditCardOracle(),
       _nowProvider = nowProvider ?? DateTime.now,
       _holdingStore = holdingStore,
       _lotStore = lotStore,
       _splitStore = splitStore,
       _marketPriceStore = marketPriceStore;

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

  /// Calculates the dashboard metrics grouped by currency.
  ///
  /// Returns a map keyed by currency code. Each entry contains the
  /// metrics computed from accounts, goals, holdings and yields in
  /// that currency only.
  ///
  /// Holdings are intentionally NOT filtered by [accountIds]: they are
  /// global per the investments architecture (lots have account_id but
  /// holdings do not). Liquid, yields, debt and revolving DO respect
  /// the filter.
  ///
  /// `netWorthCents` includes the market value of holdings on top of
  /// account balances; yield principals are not added separately
  /// because they are already part of their account's balance.
  Future<Map<String, DashboardMetrics>> calculateAllMetrics({
    Set<String>? accountIds,
  }) async {
    final balances = await _local.getBalancesPerAccount(accountIds: accountIds);
    final goals = await _local.getActiveGoals();
    final yieldsByCurrency = await _local.getYieldsValueByCurrency(
      accountIds: accountIds,
    );
    final marketValueByCurrency = await _loadMarketValueByCurrency();
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

    final goalsByCurrency = <String, List<GoalModel>>{};
    for (final g in goals) {
      goalsByCurrency.putIfAbsent(g.currencyCode, () => []).add(g);
    }
    final goalMonthlyByCurrency = <String, int>{
      for (final entry in goalsByCurrency.entries)
        entry.key: GoalMath.totalMonthlyRequiredCents(entry.value, now: now),
    };

    final balancesSum = <String, int>{};
    final liquid = <String, int>{};
    final revolving = <String, int>{};
    final debt = <String, int>{};
    final currencies = <String>{};

    for (final b in balances) {
      final cc = b.currencyCode;
      currencies.add(cc);

      balancesSum[cc] = (balancesSum[cc] ?? 0) + b.balanceCents;

      if (b.accountType == 'bank' || b.accountType == 'cash') {
        liquid[cc] = (liquid[cc] ?? 0) + b.balanceCents;
      }

      if (b.accountType == 'credit_card' && b.creditLimitCents != null) {
        final available = b.creditLimitCents! + b.balanceCents;
        if (available > 0) {
          revolving[cc] = (revolving[cc] ?? 0) + available;
        }
      }

      if ((b.accountType == 'credit_card' || b.accountType == 'loan') &&
          b.balanceCents < 0) {
        debt[cc] = (debt[cc] ?? 0) + (-b.balanceCents);
      }
    }

    currencies.addAll(goalsByCurrency.keys);
    currencies.addAll(yieldsByCurrency.keys);
    currencies.addAll(marketValueByCurrency.keys);

    final result = <String, DashboardMetrics>{};
    for (final cc in currencies) {
      final liquidCents = liquid[cc] ?? 0;
      final goalMonthly = goalMonthlyByCurrency[cc] ?? 0;
      final estimatedCardPayment = cardNetByCurrency[cc] ?? 0;
      final safeToSpend = liquidCents - goalMonthly - estimatedCardPayment;
      final revolvingCents = revolving[cc] ?? 0;
      final buyingPower = liquidCents + revolvingCents;
      final marketValue = marketValueByCurrency[cc] ?? 0;
      final balanceTotal = balancesSum[cc] ?? 0;

      result[cc] = DashboardMetrics(
        currencyCode: cc,
        netWorthCents: balanceTotal + marketValue,
        liquidAssetsCents: liquidCents,
        safeToSpendCents: safeToSpend,
        buyingPowerCents: buyingPower,
        marketValueOfHoldingsCents: marketValue,
        yieldsValueCents: yieldsByCurrency[cc] ?? 0,
        debtCents: debt[cc] ?? 0,
        revolvingCreditCents: revolvingCents,
      );
    }

    return result;
  }

  /// Returns the estimated monthly payment for each credit card.
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

  /// Loads holdings + lots + market prices and runs portfolio distribution
  /// to produce per-currency total market value in cents. Returns empty map
  /// if the investment stores are not wired (legacy DI / test scenarios).
  Future<Map<String, int>> _loadMarketValueByCurrency() async {
    final holdingStore = _holdingStore;
    final lotStore = _lotStore;
    final priceStore = _marketPriceStore;
    if (holdingStore == null || lotStore == null || priceStore == null) {
      return const <String, int>{};
    }

    final holdingRows = await holdingStore.queryRows();
    final holdings = holdingRows.map(InvestmentHoldingModel.fromMap).toList();
    final splitStore = _splitStore;

    final lotsByHolding = <String, List<InvestmentLotModel>>{};
    final splitsByHolding = <String, List<InvestmentSplitModel>>{};
    final priceByKey = <String, MarketPriceModel?>{};
    for (final h in holdings) {
      final rows = await lotStore.queryByHolding(h.id);
      lotsByHolding[h.id] = rows.map(InvestmentLotModel.fromMap).toList();
      if (splitStore != null) {
        final splitRows = await splitStore.queryByHolding(h.id);
        splitsByHolding[h.id] =
            splitRows.map(InvestmentSplitModel.fromMap).toList();
      }
      final priceRow = await priceStore.getBySymbolExchange(h.symbol, h.exchange);
      priceByKey['${h.symbol}:${h.exchange}'] =
          priceRow == null ? null : MarketPriceModel.fromMap(priceRow);
    }

    final distribution = computePortfolioDistribution(
      holdings: holdings,
      lotsFor: (id) => lotsByHolding[id] ?? const [],
      splitsFor: (id) => splitsByHolding[id] ?? const [],
      priceFor: (s, e) => priceByKey['$s:$e'],
    );

    final result = <String, int>{};
    for (final entry in distribution.entries) {
      final total = entry.value.fold<double>(0, (a, s) => a + s.marketValue);
      if (total <= 0) continue;
      result[entry.key] = (total * 100).round();
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
