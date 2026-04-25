import 'package:pocket_pilot/src/features/investments/domain/current_price_resolver.dart';
import 'package:pocket_pilot/src/features/investments/domain/investment_holding.dart';
import 'package:pocket_pilot/src/features/investments/domain/investment_lot.dart';
import 'package:pocket_pilot/src/features/investments/domain/investment_split.dart';
import 'package:pocket_pilot/src/features/investments/domain/market_price.dart';
import 'package:pocket_pilot/src/features/investments/domain/position_math.dart';

/// One slice of the portfolio pie for a single holding.
///
/// `percentage` is relative to the total market value of the holding's own
/// currency group — slices in different currencies do not share a denominator.
typedef PortfolioSlice = ({
  String holdingId,
  String symbol,
  String displayName,
  String currencyCode,
  double marketValue,
  double percentage,
});

/// Group active holdings by their currency and compute each one's share of
/// the portfolio by market value.
///
/// Holdings are excluded when any of the following hold true:
/// - `deletedAt != null`
/// - `status != 'active'`
/// - `netQuantity <= 0` (fully sold or corrupt)
/// - the current price resolver yields `null` (no market, manual, or last-lot
///   price available)
///
/// Slices within each currency group are ordered descending by `marketValue`.
/// `percentage` is `marketValue / sum(marketValue of the group)`; if the group
/// total is zero it is dropped from the result.
///
/// [splitsFor] returns the active splits for a given holding. When omitted it
/// defaults to "no splits", preserving the pre-Fase-8 behavior. Both
/// `computePosition` and `resolveCurrentPrice` honor splits so the resulting
/// market value matches the post-split share count multiplied by the
/// post-split price.
Map<String, List<PortfolioSlice>> computePortfolioDistribution({
  required List<InvestmentHoldingModel> holdings,
  required List<InvestmentLotModel> Function(String holdingId) lotsFor,
  required MarketPriceModel? Function(String symbol, String exchange) priceFor,
  List<InvestmentSplitModel> Function(String holdingId)? splitsFor,
}) {
  final byCurrency = <String, List<_RawSlice>>{};

  for (final holding in holdings) {
    if (holding.deletedAt != null) continue;
    if (holding.status != 'active') continue;

    final lots = lotsFor(holding.id);
    final splits = splitsFor?.call(holding.id) ?? const <InvestmentSplitModel>[];
    final position = computePosition(lots, splits: splits);
    if (position.netQuantity <= 0) continue;

    final quote = resolveCurrentPrice(
      holding: holding,
      marketPrice: priceFor(holding.symbol, holding.exchange),
      lots: lots,
      splits: splits,
    );
    final price = quote.price;
    if (price == null) continue;

    final marketValue = position.netQuantity * price;
    if (marketValue <= 0) continue;

    byCurrency
        .putIfAbsent(holding.currencyCode, () => <_RawSlice>[])
        .add(_RawSlice(
          holdingId: holding.id,
          symbol: holding.symbol,
          displayName: holding.displayName,
          currencyCode: holding.currencyCode,
          marketValue: marketValue,
        ));
  }

  final result = <String, List<PortfolioSlice>>{};
  for (final entry in byCurrency.entries) {
    final slices = entry.value;
    final total = slices.fold<double>(0, (a, s) => a + s.marketValue);
    if (total <= 0) continue;
    slices.sort((a, b) => b.marketValue.compareTo(a.marketValue));
    result[entry.key] = [
      for (final s in slices)
        (
          holdingId: s.holdingId,
          symbol: s.symbol,
          displayName: s.displayName,
          currencyCode: s.currencyCode,
          marketValue: s.marketValue,
          percentage: s.marketValue / total,
        ),
    ];
  }

  return result;
}

class _RawSlice {
  final String holdingId;
  final String symbol;
  final String displayName;
  final String currencyCode;
  final double marketValue;

  _RawSlice({
    required this.holdingId,
    required this.symbol,
    required this.displayName,
    required this.currencyCode,
    required this.marketValue,
  });
}
