import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_pilot/src/features/investments/domain/investment_lot.dart';
import 'package:pocket_pilot/src/features/investments/domain/position_math.dart';

InvestmentLotModel makeLot({
  String id = 'l1',
  String holdingId = 'h1',
  String accountId = 'a1',
  String kind = 'buy',
  double quantity = 1,
  double price = 0,
  int feeCents = 0,
  double? fxRate,
  String occurredAt = '2026-01-01',
  String validity = 'valid',
  DateTime? createdAt,
  DateTime? deletedAt,
}) {
  return InvestmentLotModel(
    id: id,
    holdingId: holdingId,
    accountId: accountId,
    kind: kind,
    quantity: quantity,
    price: price,
    feeCents: feeCents,
    fxRate: fxRate,
    occurredAt: occurredAt,
    validity: validity,
    createdAt: createdAt ?? DateTime.utc(2026, 1, 1),
    updatedAt: createdAt ?? DateTime.utc(2026, 1, 1),
    deletedAt: deletedAt,
  );
}

void main() {
  group('computePosition', () {
    test('empty input returns zeros', () {
      final p = computePosition(const []);
      expect(p.netQuantity, 0);
      expect(p.weightedAvgCost, 0);
      expect(p.fifoRemainingLots, isEmpty);
    });

    test('single buy without fee', () {
      final p = computePosition([
        makeLot(id: 'b1', kind: 'buy', quantity: 100, price: 10),
      ]);
      expect(p.netQuantity, 100);
      expect(p.weightedAvgCost, closeTo(10, 1e-9));
      expect(p.fifoRemainingLots, hasLength(1));
      expect(p.fifoRemainingLots.first.quantityRemaining, 100);
      expect(p.fifoRemainingLots.first.effectivePricePerUnit,
          closeTo(10, 1e-9));
    });

    test('single buy with fee inflates effective price per unit', () {
      // qty=100, price=10.00, fee=500 cents = 5.00 currency units
      // effective cost = 1005; per-unit = 10.05
      final p = computePosition([
        makeLot(id: 'b1', kind: 'buy', quantity: 100, price: 10, feeCents: 500),
      ]);
      expect(p.weightedAvgCost, closeTo(10.05, 1e-9));
      expect(
        p.fifoRemainingLots.first.effectivePricePerUnit,
        closeTo(10.05, 1e-9),
      );
    });

    test('two buys at different prices yield global weighted avg', () {
      final p = computePosition([
        makeLot(id: 'b1', kind: 'buy', quantity: 50, price: 10),
        makeLot(
          id: 'b2',
          kind: 'buy',
          quantity: 50,
          price: 12,
          occurredAt: '2026-02-01',
        ),
      ]);
      expect(p.netQuantity, 100);
      expect(p.weightedAvgCost, closeTo(11, 1e-9));
      expect(p.fifoRemainingLots.map((s) => s.lotId), ['b1', 'b2']);
    });

    test('partial sell reduces head but keeps global avg', () {
      final p = computePosition([
        makeLot(id: 'b1', kind: 'buy', quantity: 100, price: 10),
        makeLot(
          id: 's1',
          kind: 'sell',
          quantity: 40,
          price: 12,
          occurredAt: '2026-02-01',
        ),
      ]);
      expect(p.netQuantity, 60);
      expect(p.weightedAvgCost, closeTo(10, 1e-9));
      expect(p.fifoRemainingLots, hasLength(1));
      expect(p.fifoRemainingLots.first.lotId, 'b1');
      expect(p.fifoRemainingLots.first.quantityRemaining, closeTo(60, 1e-9));
    });

    test('sell that crosses head advances FIFO', () {
      final p = computePosition([
        makeLot(id: 'b1', kind: 'buy', quantity: 50, price: 10),
        makeLot(
          id: 'b2',
          kind: 'buy',
          quantity: 50,
          price: 12,
          occurredAt: '2026-02-01',
        ),
        makeLot(
          id: 's1',
          kind: 'sell',
          quantity: 70,
          price: 15,
          occurredAt: '2026-03-01',
        ),
      ]);
      expect(p.netQuantity, 30);
      expect(p.fifoRemainingLots, hasLength(1));
      expect(p.fifoRemainingLots.first.lotId, 'b2');
      expect(p.fifoRemainingLots.first.quantityRemaining, closeTo(30, 1e-9));
      expect(p.weightedAvgCost, closeTo(11, 1e-9));
    });

    test('reversed input yields same result (sort is internal)', () {
      final chrono = [
        makeLot(id: 'b1', kind: 'buy', quantity: 50, price: 10),
        makeLot(
          id: 'b2',
          kind: 'buy',
          quantity: 50,
          price: 12,
          occurredAt: '2026-02-01',
        ),
        makeLot(
          id: 's1',
          kind: 'sell',
          quantity: 70,
          price: 15,
          occurredAt: '2026-03-01',
        ),
      ];
      final reversed = chrono.reversed.toList();
      final pA = computePosition(chrono);
      final pB = computePosition(reversed);
      expect(pA.netQuantity, pB.netQuantity);
      expect(pA.weightedAvgCost, closeTo(pB.weightedAvgCost, 1e-9));
      expect(
        pA.fifoRemainingLots.map((s) => s.lotId).toList(),
        pB.fifoRemainingLots.map((s) => s.lotId).toList(),
      );
    });

    test('soft-deleted lot is ignored', () {
      final p = computePosition([
        makeLot(
          id: 'b1',
          kind: 'buy',
          quantity: 100,
          price: 10,
          deletedAt: DateTime.utc(2026, 2, 1),
        ),
        makeLot(
          id: 'b2',
          kind: 'buy',
          quantity: 50,
          price: 20,
          occurredAt: '2026-01-10',
        ),
      ]);
      expect(p.netQuantity, 50);
      expect(p.weightedAvgCost, closeTo(20, 1e-9));
    });

    test('invalid lot is ignored', () {
      final p = computePosition([
        makeLot(
          id: 'b1',
          kind: 'buy',
          quantity: 100,
          price: 10,
          validity: 'invalid',
        ),
        makeLot(id: 'b2', kind: 'buy', quantity: 50, price: 20),
      ]);
      expect(p.netQuantity, 50);
      expect(p.weightedAvgCost, closeTo(20, 1e-9));
    });

    test('sell > available leaves netQuantity negative and empty FIFO', () {
      final p = computePosition([
        makeLot(id: 'b1', kind: 'buy', quantity: 10, price: 10),
        makeLot(
          id: 's1',
          kind: 'sell',
          quantity: 20,
          price: 12,
          occurredAt: '2026-02-01',
        ),
      ]);
      expect(p.netQuantity, -10);
      expect(p.fifoRemainingLots, isEmpty);
    });

    test('fractional quantities are preserved', () {
      final p = computePosition([
        makeLot(id: 'b1', kind: 'buy', quantity: 0.5, price: 100),
      ]);
      expect(p.netQuantity, closeTo(0.5, 1e-9));
      expect(p.weightedAvgCost, closeTo(100, 1e-9));
      expect(p.fifoRemainingLots.first.quantityRemaining, closeTo(0.5, 1e-9));
    });

    test('same occurredAt uses createdAt as tiebreak', () {
      final older = makeLot(
        id: 'older',
        kind: 'buy',
        quantity: 30,
        price: 10,
        occurredAt: '2026-01-01',
        createdAt: DateTime.utc(2026, 1, 1, 8),
      );
      final newer = makeLot(
        id: 'newer',
        kind: 'buy',
        quantity: 30,
        price: 20,
        occurredAt: '2026-01-01',
        createdAt: DateTime.utc(2026, 1, 1, 12),
      );
      final sell = makeLot(
        id: 's1',
        kind: 'sell',
        quantity: 30,
        price: 25,
        occurredAt: '2026-02-01',
      );
      // Pass in reverse order to verify tie-break.
      final p = computePosition([sell, newer, older]);
      expect(p.netQuantity, 30);
      expect(p.fifoRemainingLots, hasLength(1));
      expect(p.fifoRemainingLots.first.lotId, 'newer');
    });
  });

  group('hasInvalidLots', () {
    test('true when any non-deleted lot is invalid', () {
      expect(
        hasInvalidLots([
          makeLot(id: 'b1'),
          makeLot(id: 'b2', validity: 'invalid'),
        ]),
        isTrue,
      );
    });

    test('false when invalid lot is soft-deleted', () {
      expect(
        hasInvalidLots([
          makeLot(id: 'b1'),
          makeLot(
            id: 'b2',
            validity: 'invalid',
            deletedAt: DateTime.utc(2026, 2, 1),
          ),
        ]),
        isFalse,
      );
    });
  });
}
