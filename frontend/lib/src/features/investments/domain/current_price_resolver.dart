import 'package:pocket_pilot/src/features/investments/domain/investment_holding.dart';
import 'package:pocket_pilot/src/features/investments/domain/investment_lot.dart';
import 'package:pocket_pilot/src/features/investments/domain/investment_split.dart';
import 'package:pocket_pilot/src/features/investments/domain/market_price.dart';

/// Resolved current price for a holding along with its source.
///
/// `source` is one of: `market`, `manual`, `last_lot`, `none`.
typedef PriceQuote = ({double? price, String source});

/// Resolve the "current price" of a holding with the following precedence:
///   1. [marketPrice] (from the market_prices sync table).
///   2. [InvestmentHoldingModel.manualPrice].
///   3. Price of the most recent valid lot, ADJUSTED for any active splits
///      with `occurredAt > lot.occurredAt` so the returned price is
///      expressed in the post-split share count (consistent with the math).
///   4. null (no source).
PriceQuote resolveCurrentPrice({
  required InvestmentHoldingModel holding,
  required MarketPriceModel? marketPrice,
  required List<InvestmentLotModel> lots,
  List<InvestmentSplitModel> splits = const [],
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
  if (candidates.isEmpty) {
    return (price: null, source: 'none');
  }
  final last = candidates.first;

  // Cumulative ratio across all active splits that happened AFTER the lot.
  // Splits with the same occurredAt as the lot do not apply (the lot price
  // is already in that day's share count).
  double cumulative = 1.0;
  for (final s in splits) {
    if (s.deletedAt != null) continue;
    if (s.ratioDen == 0) continue;
    if (s.occurredAt.compareTo(last.occurredAt) <= 0) continue;
    cumulative *= s.ratioNum / s.ratioDen;
  }
  final adjusted = cumulative > 0 ? last.price / cumulative : last.price;
  return (price: adjusted, source: 'last_lot');
}
