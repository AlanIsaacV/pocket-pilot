import 'package:pocket_pilot/src/features/investments/domain/investment_holding.dart';
import 'package:pocket_pilot/src/features/investments/domain/investment_lot.dart';
import 'package:pocket_pilot/src/features/investments/domain/market_price.dart';

/// Resolved current price for a holding along with its source.
///
/// `source` is one of: `market`, `manual`, `last_lot`, `none`.
typedef PriceQuote = ({double? price, String source});

/// Resolve the "current price" of a holding with the following precedence:
///   1. [marketPrice] (from the market_prices sync table)
///   2. [InvestmentHoldingModel.manualPrice]
///   3. Price of the most recent valid lot
///   4. null (no source)
PriceQuote resolveCurrentPrice({
  required InvestmentHoldingModel holding,
  required MarketPriceModel? marketPrice,
  required List<InvestmentLotModel> lots,
}) {
  if (marketPrice != null) {
    return (price: marketPrice.price, source: 'market');
  }
  if (holding.manualPrice != null) {
    return (price: holding.manualPrice, source: 'manual');
  }
  final candidates = lots
      .where((l) => l.deletedAt == null && l.validity == 'valid')
      .toList()
    ..sort((a, b) {
      final byDate = b.occurredAt.compareTo(a.occurredAt);
      if (byDate != 0) return byDate;
      return b.createdAt.compareTo(a.createdAt);
    });
  if (candidates.isNotEmpty) {
    return (price: candidates.first.price, source: 'last_lot');
  }
  return (price: null, source: 'none');
}
