import 'package:pocket_pilot/src/features/investments/domain/investment_lot.dart';
import 'package:pocket_pilot/src/features/investments/domain/investment_split.dart';

/// A remaining (un-consumed) buy slice after FIFO consumption.
typedef FifoRemainingLot = ({
  String lotId,
  double quantityRemaining,
  double effectivePricePerUnit,
  String occurredAt,
});

/// Aggregate position derived from a holding's lots.
typedef Position = ({
  double netQuantity,
  double weightedAvgCost,
  List<FifoRemainingLot> fifoRemainingLots,
});

/// Epsilon for "slice exhausted" detection in FIFO math. Double arithmetic can
/// leave tiny residues; we treat anything below this as zero.
const double _epsilon = 1e-9;

/// Build the aggregate [Position] for a list of lots, optionally adjusting
/// for stock [splits].
///
/// - Lots with `deletedAt != null` or `validity != 'valid'` are ignored.
/// - Splits with `deletedAt != null` are ignored.
/// - Surviving events `(lots ∪ splits)` are sorted ascending by
///   `(occurredAt, createdAt)` so the walk is deterministic regardless of
///   input order.
/// - Walk semantics:
///     * **buy**: enqueue FIFO slice; accumulate global buy qty + cost.
///     * **sell**: consume FIFO from the head; accumulate global sell qty.
///     * **split**: every queued slice has `qty *= ratio` and
///       `effectivePrice /= ratio`. Global buy/sell qty also scale by `ratio`
///       so `netQuantity` post-walk is in the post-split share count. Cost
///       totals stay the same — the avg cost = totalBuyCost / totalBuyQty
///       naturally divides by the ratio.
/// - `weightedAvgCost` is the GLOBAL average over all valid buys (fees
///   included, prorated per unit), expressed in the post-split share count.
/// - `fifoRemainingLots` reflects the queue state after every event has been
///   applied. If sells exceed buys the result is simply empty; the caller may
///   inspect `netQuantity < 0` to detect the corrupt state.
Position computePosition(
  List<InvestmentLotModel> lots, {
  List<InvestmentSplitModel> splits = const [],
}) {
  final events = <_Event>[
    for (final l in lots)
      if (l.deletedAt == null && l.validity == 'valid')
        l.isBuy
            ? _Event.buy(l)
            : _Event.sell(l),
    for (final s in splits)
      if (s.deletedAt == null) _Event.split(s),
  ]..sort(_compareEvents);

  double totalBuyQty = 0;
  double totalBuyCost = 0;
  double totalSellQty = 0;
  final queue = <_MutableSlice>[];

  for (final ev in events) {
    switch (ev.kind) {
      case _EventKind.buy:
        final lot = ev.lot!;
        final effectiveCost = lot.quantity * lot.price + lot.feeCents / 100.0;
        totalBuyQty += lot.quantity;
        totalBuyCost += effectiveCost;
        queue.add(_MutableSlice(
          lotId: lot.id,
          qtyRemaining: lot.quantity,
          effectivePricePerUnit:
              lot.quantity > 0 ? effectiveCost / lot.quantity : 0.0,
          occurredAt: lot.occurredAt,
        ));
        break;
      case _EventKind.sell:
        final lot = ev.lot!;
        totalSellQty += lot.quantity;
        double remaining = lot.quantity;
        while (remaining > _epsilon && queue.isNotEmpty) {
          final head = queue.first;
          if (head.qtyRemaining > remaining + _epsilon) {
            head.qtyRemaining -= remaining;
            remaining = 0;
          } else {
            remaining -= head.qtyRemaining;
            queue.removeAt(0);
          }
        }
        break;
      case _EventKind.split:
        final s = ev.split!;
        if (s.ratioDen == 0) break; // defensive — validation forbids it
        final ratio = s.ratioNum / s.ratioDen;
        for (final slice in queue) {
          slice.qtyRemaining *= ratio;
          slice.effectivePricePerUnit /= ratio;
        }
        totalBuyQty *= ratio;
        totalSellQty *= ratio;
        // totalBuyCost stays — the avg = cost/qty divides by ratio.
        break;
    }
  }

  final fifoRemaining = queue
      .where((s) => s.qtyRemaining > _epsilon)
      .map((s) => (
            lotId: s.lotId,
            quantityRemaining: s.qtyRemaining,
            effectivePricePerUnit: s.effectivePricePerUnit,
            occurredAt: s.occurredAt,
          ))
      .toList();

  return (
    netQuantity: totalBuyQty - totalSellQty,
    weightedAvgCost: totalBuyQty > 0 ? totalBuyCost / totalBuyQty : 0.0,
    fifoRemainingLots: fifoRemaining,
  );
}

/// True when any lot in the input has `validity != 'valid'` (and is not
/// soft-deleted). Useful for surfacing a "N lotes inválidos" banner.
bool hasInvalidLots(List<InvestmentLotModel> lots) {
  return lots.any((l) => l.deletedAt == null && l.validity != 'valid');
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
  final String occurredAt;

  _MutableSlice({
    required this.lotId,
    required this.qtyRemaining,
    required this.effectivePricePerUnit,
    required this.occurredAt,
  });
}
