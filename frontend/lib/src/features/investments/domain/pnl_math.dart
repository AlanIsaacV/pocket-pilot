import 'package:pocket_pilot/src/features/investments/domain/investment_lot.dart';
import 'package:pocket_pilot/src/features/investments/domain/investment_split.dart';
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

/// Walk lots and splits chronologically, consuming buys FIFO for every sell
/// (in post-split share count) and recording the realized P&L of each sell.
///
/// `quantitySold` and `proceeds` of every entry are reported in the share
/// count and price valid AT the moment of the sell — i.e. post any splits
/// that happened before the sell, pre any splits that happened after.
///
/// Filters: soft-deleted lots/splits and lots with `validity != 'valid'` are
/// excluded. Throws [InvestmentMathException.sellExceedsAvailable] if any
/// sell cannot be fully covered by the FIFO queue at that moment — defensive
/// only: the form layer hard-blocks that case, so reaching it indicates
/// corrupt data post multi-device LWW.
RealizedPnL computeRealizedPnL(
  List<InvestmentLotModel> lots, {
  List<InvestmentSplitModel> splits = const [],
}) {
  final events = <_Event>[
    for (final l in lots)
      if (l.deletedAt == null && l.validity == 'valid')
        l.isBuy ? _Event.buy(l) : _Event.sell(l),
    for (final s in splits)
      if (s.deletedAt == null) _Event.split(s),
  ]..sort(_compareEvents);

  final queue = <_MutableSlice>[];
  final entries = <RealizedSellEntry>[];
  double total = 0;

  for (final ev in events) {
    switch (ev.kind) {
      case _EventKind.buy:
        final lot = ev.lot!;
        final effectiveCost = lot.quantity * lot.price + lot.feeCents / 100.0;
        queue.add(_MutableSlice(
          lotId: lot.id,
          qtyRemaining: lot.quantity,
          effectivePricePerUnit:
              lot.quantity > 0 ? effectiveCost / lot.quantity : 0.0,
        ));
        break;
      case _EventKind.sell:
        final lot = ev.lot!;
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
        break;
      case _EventKind.split:
        final s = ev.split!;
        if (s.ratioDen == 0) break;
        final ratio = s.ratioNum / s.ratioDen;
        for (final slice in queue) {
          slice.qtyRemaining *= ratio;
          slice.effectivePricePerUnit /= ratio;
        }
        break;
    }
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

enum _EventKind { buy, sell, split }

class _Event {
  final _EventKind kind;
  final String occurredAt;
  final DateTime createdAt;
  final InvestmentLotModel? lot;
  final InvestmentSplitModel? split;

  _Event._({
    required this.kind,
    required this.occurredAt,
    required this.createdAt,
    this.lot,
    this.split,
  });

  factory _Event.buy(InvestmentLotModel lot) => _Event._(
        kind: _EventKind.buy,
        occurredAt: lot.occurredAt,
        createdAt: lot.createdAt,
        lot: lot,
      );
  factory _Event.sell(InvestmentLotModel lot) => _Event._(
        kind: _EventKind.sell,
        occurredAt: lot.occurredAt,
        createdAt: lot.createdAt,
        lot: lot,
      );
  factory _Event.split(InvestmentSplitModel s) => _Event._(
        kind: _EventKind.split,
        occurredAt: s.occurredAt,
        createdAt: s.createdAt,
        split: s,
      );
}

int _compareEvents(_Event a, _Event b) {
  final byDate = a.occurredAt.compareTo(b.occurredAt);
  if (byDate != 0) return byDate;
  return a.createdAt.compareTo(b.createdAt);
}

class _MutableSlice {
  final String lotId;
  double qtyRemaining;
  double effectivePricePerUnit;

  _MutableSlice({
    required this.lotId,
    required this.qtyRemaining,
    required this.effectivePricePerUnit,
  });
}
