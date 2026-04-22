import 'package:pocket_pilot/src/features/investments/domain/investment_lot.dart';
import 'package:pocket_pilot/src/features/investments/domain/position_math.dart';

/// Per-sell realized P&L breakdown.
typedef RealizedSellEntry = ({
  String sellLotId,
  String sellOccurredAt,
  double quantitySold,
  double proceeds,
  double costBasisConsumed,
  double pnl,
});

/// Aggregate realized P&L across all sells in a holding.
typedef RealizedPnL = ({
  List<RealizedSellEntry> perSellPnL,
  double totalRealized,
});

const double _epsilon = 1e-9;

/// Walk lots chronologically, consuming buys FIFO for every sell and
/// recording the realized P&L of each sell.
///
/// Filters: soft-deleted lots and lots with `validity != 'valid'` are
/// excluded. Throws [InvestmentMathException.sellExceedsAvailable] if any
/// sell cannot be fully covered by preceding buys — defensive only: the
/// form layer hard-blocks that case, so reaching it indicates corrupt
/// data post multi-device LWW.
RealizedPnL computeRealizedPnL(List<InvestmentLotModel> lots) {
  final survivors = lots
      .where((l) => l.deletedAt == null && l.validity == 'valid')
      .toList()
    ..sort(_compareByOccurredAndCreated);

  final queue = <_MutableSlice>[];
  final entries = <RealizedSellEntry>[];
  double total = 0;

  for (final lot in survivors) {
    if (lot.isBuy) {
      final effectiveCost = lot.quantity * lot.price + lot.feeCents / 100.0;
      queue.add(_MutableSlice(
        lotId: lot.id,
        qtyRemaining: lot.quantity,
        effectivePricePerUnit:
            lot.quantity > 0 ? effectiveCost / lot.quantity : 0.0,
      ));
      continue;
    }

    // Sell
    final proceeds = lot.quantity * lot.price - lot.feeCents / 100.0;
    double remaining = lot.quantity;
    double basis = 0;
    while (remaining > _epsilon && queue.isNotEmpty) {
      final head = queue.first;
      if (head.qtyRemaining > remaining + _epsilon) {
        basis += remaining * head.effectivePricePerUnit;
        head.qtyRemaining -= remaining;
        remaining = 0;
      } else {
        basis += head.qtyRemaining * head.effectivePricePerUnit;
        remaining -= head.qtyRemaining;
        queue.removeAt(0);
      }
    }
    if (remaining > _epsilon) {
      throw InvestmentMathException.sellExceedsAvailable(
        sellLotId: lot.id,
        requested: lot.quantity,
        available: lot.quantity - remaining,
      );
    }
    final pnl = proceeds - basis;
    total += pnl;
    entries.add((
      sellLotId: lot.id,
      sellOccurredAt: lot.occurredAt,
      quantitySold: lot.quantity,
      proceeds: proceeds,
      costBasisConsumed: basis,
      pnl: pnl,
    ));
  }

  return (perSellPnL: entries, totalRealized: total);
}

/// Unrealized P&L for an open position at [currentPrice].
///
/// Returns 0.0 when there's nothing to value — either no shares
/// (`netQuantity <= 0`, which also covers the corrupt "more sold than
/// bought" case) or no price available.
double computeUnrealizedPnL({
  required Position position,
  required double? currentPrice,
}) {
  if (currentPrice == null || position.netQuantity <= 0) return 0.0;
  return (currentPrice - position.weightedAvgCost) * position.netQuantity;
}

/// Errors raised by the investment math when the input is internally
/// inconsistent (e.g., a sell that cannot be covered by prior buys).
class InvestmentMathException implements Exception {
  final String message;
  final String? sellLotId;
  final double? requested;
  final double? available;

  const InvestmentMathException._(
    this.message, {
    this.sellLotId,
    this.requested,
    this.available,
  });

  factory InvestmentMathException.sellExceedsAvailable({
    required String sellLotId,
    required double requested,
    required double available,
  }) {
    return InvestmentMathException._(
      'Venta excede disponible en lote $sellLotId: solicitado=$requested, disponible=$available',
      sellLotId: sellLotId,
      requested: requested,
      available: available,
    );
  }

  @override
  String toString() => 'InvestmentMathException: $message';
}

int _compareByOccurredAndCreated(InvestmentLotModel a, InvestmentLotModel b) {
  final byDate = a.occurredAt.compareTo(b.occurredAt);
  if (byDate != 0) return byDate;
  return a.createdAt.compareTo(b.createdAt);
}

class _MutableSlice {
  final String lotId;
  double qtyRemaining;
  final double effectivePricePerUnit;

  _MutableSlice({
    required this.lotId,
    required this.qtyRemaining,
    required this.effectivePricePerUnit,
  });
}
