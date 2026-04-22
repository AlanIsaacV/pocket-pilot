import 'package:pocket_pilot/src/features/investments/domain/investment_lot.dart';

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

/// Build the aggregate [Position] for a list of lots.
///
/// - Lots with `deletedAt != null` or `validity != 'valid'` are ignored.
/// - Survivors are sorted ascending by `(occurredAt, createdAt)` to make the
///   result deterministic regardless of input order.
/// - `weightedAvgCost` is the GLOBAL average over all valid buys (fees
///   included, prorated per unit); not recomputed from the remaining FIFO
///   slices.
/// - `fifoRemainingLots` reflects the state after all sells have been applied
///   chronologically. If sells exceed buys the result is simply empty; the
///   caller may inspect `netQuantity < 0` to detect the corrupt state.
Position computePosition(List<InvestmentLotModel> lots) {
  final survivors = lots
      .where((l) => l.deletedAt == null && l.validity == 'valid')
      .toList()
    ..sort(_compareByOccurredAndCreated);

  double totalBuyQty = 0;
  double totalBuyCost = 0;
  double totalSellQty = 0;
  final queue = <_MutableSlice>[];

  for (final lot in survivors) {
    if (lot.isBuy) {
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
    } else {
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
      // If remaining > 0 here, the sell exceeded available. We silently
      // tolerate it in computePosition; pnl_math raises the explicit
      // exception instead.
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

int _compareByOccurredAndCreated(InvestmentLotModel a, InvestmentLotModel b) {
  final byDate = a.occurredAt.compareTo(b.occurredAt);
  if (byDate != 0) return byDate;
  return a.createdAt.compareTo(b.createdAt);
}

class _MutableSlice {
  final String lotId;
  double qtyRemaining;
  final double effectivePricePerUnit;
  final String occurredAt;

  _MutableSlice({
    required this.lotId,
    required this.qtyRemaining,
    required this.effectivePricePerUnit,
    required this.occurredAt,
  });
}
