import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_pilot/src/features/investments/domain/investment_lot.dart';
import 'package:pocket_pilot/src/features/investments/domain/pnl_math.dart';
import 'package:pocket_pilot/src/features/investments/domain/position_math.dart';

InvestmentLotModel makeLot({
  String id = 'l1',
  String holdingId = 'h1',
  String accountId = 'a1',
  String kind = 'buy',
  double quantity = 1,
  double price = 0,
  int feeCents = 0,
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
    occurredAt: occurredAt,
    validity: validity,
    createdAt: createdAt ?? DateTime.utc(2026, 1, 1),
    updatedAt: createdAt ?? DateTime.utc(2026, 1, 1),
    deletedAt: deletedAt,
  );
}

void main() {
  group('computeRealizedPnL', () {
    test('no sells yields zero total realized', () {
      final r = computeRealizedPnL([
        makeLot(id: 'b1', kind: 'buy', quantity: 100, price: 10),
      ]);
      expect(r.totalRealized, 0);
      expect(r.perSellPnL, isEmpty);
    });

    test('single buy and full sell (no fees) returns proceeds minus basis', () {
      final r = computeRealizedPnL([
        makeLot(id: 'b1', kind: 'buy', quantity: 100, price: 10),
        makeLot(
          id: 's1',
          kind: 'sell',
          quantity: 100,
          price: 12,
          occurredAt: '2026-02-01',
        ),
      ]);
      expect(r.perSellPnL, hasLength(1));
      expect(r.perSellPnL.first.pnl, closeTo(200, 1e-9));
      expect(r.totalRealized, closeTo(200, 1e-9));
    });

    test('FIFO with two buys and a partial-crossing sell', () {
      // Buys: 50@10, 50@12; Sell: 70@15
      // cost basis = 50*10 + 20*12 = 740
      // proceeds = 70*15 = 1050; pnl = 310
      final r = computeRealizedPnL([
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
      expect(r.perSellPnL.first.costBasisConsumed, closeTo(740, 1e-9));
      expect(r.perSellPnL.first.proceeds, closeTo(1050, 1e-9));
      expect(r.perSellPnL.first.pnl, closeTo(310, 1e-9));
      expect(r.totalRealized, closeTo(310, 1e-9));
    });

    test('fees on buys inflate cost basis', () {
      // Buy: 100 @ 10, fee=500 cents => effective cost 1005
      // Sell: 100 @ 12, no fee => proceeds 1200; pnl = 195
      final r = computeRealizedPnL([
        makeLot(id: 'b1', kind: 'buy', quantity: 100, price: 10, feeCents: 500),
        makeLot(
          id: 's1',
          kind: 'sell',
          quantity: 100,
          price: 12,
          occurredAt: '2026-02-01',
        ),
      ]);
      expect(r.totalRealized, closeTo(195, 1e-9));
    });

    test('fees on sells reduce proceeds', () {
      // Buy: 100 @ 10 no fee => basis 1000
      // Sell: 100 @ 12, fee=100 cents => proceeds 1199; pnl = 199
      final r = computeRealizedPnL([
        makeLot(id: 'b1', kind: 'buy', quantity: 100, price: 10),
        makeLot(
          id: 's1',
          kind: 'sell',
          quantity: 100,
          price: 12,
          feeCents: 100,
          occurredAt: '2026-02-01',
        ),
      ]);
      expect(r.totalRealized, closeTo(199, 1e-9));
    });

    test('multiple sells across multiple buys', () {
      // Buys: 30@10, 30@12, 40@15 (total 100)
      // Sell 1: 50 @ 13 => eats 30@10 + 20@12 = 540 basis; proceeds 650; pnl 110
      // Sell 2: 30 @ 14 => eats 10@12 + 20@15 = 420 basis; proceeds 420; pnl 0
      final r = computeRealizedPnL([
        makeLot(id: 'b1', kind: 'buy', quantity: 30, price: 10),
        makeLot(
          id: 'b2',
          kind: 'buy',
          quantity: 30,
          price: 12,
          occurredAt: '2026-02-01',
        ),
        makeLot(
          id: 'b3',
          kind: 'buy',
          quantity: 40,
          price: 15,
          occurredAt: '2026-03-01',
        ),
        makeLot(
          id: 's1',
          kind: 'sell',
          quantity: 50,
          price: 13,
          occurredAt: '2026-04-01',
        ),
        makeLot(
          id: 's2',
          kind: 'sell',
          quantity: 30,
          price: 14,
          occurredAt: '2026-05-01',
        ),
      ]);
      expect(r.perSellPnL, hasLength(2));
      expect(r.perSellPnL[0].costBasisConsumed, closeTo(540, 1e-9));
      expect(r.perSellPnL[0].pnl, closeTo(110, 1e-9));
      expect(r.perSellPnL[1].costBasisConsumed, closeTo(420, 1e-9));
      expect(r.perSellPnL[1].pnl, closeTo(0, 1e-9));
      expect(r.totalRealized, closeTo(110, 1e-9));
    });

    test('sell > available throws InvestmentMathException', () {
      expect(
        () => computeRealizedPnL([
          makeLot(id: 'b1', kind: 'buy', quantity: 10, price: 10),
          makeLot(
            id: 's1',
            kind: 'sell',
            quantity: 20,
            price: 12,
            occurredAt: '2026-02-01',
          ),
        ]),
        throwsA(isA<InvestmentMathException>()
            .having((e) => e.sellLotId, 'sellLotId', 's1')
            .having((e) => e.requested, 'requested', 20)
            .having((e) => e.available, 'available', closeTo(10, 1e-9))),
      );
    });

    test('deleted and invalid lots are excluded', () {
      final r = computeRealizedPnL([
        makeLot(id: 'b1', kind: 'buy', quantity: 100, price: 10),
        makeLot(
          id: 's1',
          kind: 'sell',
          quantity: 50,
          price: 12,
          validity: 'invalid',
          occurredAt: '2026-02-01',
        ),
        makeLot(
          id: 's2',
          kind: 'sell',
          quantity: 30,
          price: 14,
          deletedAt: DateTime.utc(2026, 3, 1),
          occurredAt: '2026-03-01',
        ),
      ]);
      expect(r.totalRealized, 0);
      expect(r.perSellPnL, isEmpty);
    });

    test('determinism: shuffled input yields same totalRealized', () {
      final base = [
        makeLot(id: 'b1', kind: 'buy', quantity: 30, price: 10),
        makeLot(
          id: 'b2',
          kind: 'buy',
          quantity: 30,
          price: 12,
          occurredAt: '2026-02-01',
        ),
        makeLot(
          id: 's1',
          kind: 'sell',
          quantity: 40,
          price: 15,
          occurredAt: '2026-03-01',
        ),
      ];
      final pA = computeRealizedPnL(base).totalRealized;
      final pB = computeRealizedPnL(base.reversed.toList()).totalRealized;
      expect(pA, closeTo(pB, 1e-9));
    });
  });

  group('computeUnrealizedPnL', () {
    Position pos({
      double net = 0,
      double avg = 0,
    }) {
      return (
        netQuantity: net,
        weightedAvgCost: avg,
        fifoRemainingLots: const <FifoRemainingLot>[],
      );
    }

    test('returns 0 when netQuantity <= 0', () {
      expect(
        computeUnrealizedPnL(position: pos(net: 0, avg: 10), currentPrice: 15),
        0,
      );
      expect(
        computeUnrealizedPnL(position: pos(net: -5, avg: 10), currentPrice: 15),
        0,
      );
    });

    test('returns 0 when currentPrice is null', () {
      expect(
        computeUnrealizedPnL(
          position: pos(net: 10, avg: 5),
          currentPrice: null,
        ),
        0,
      );
    });

    test('positive and negative based on price vs avg', () {
      expect(
        computeUnrealizedPnL(position: pos(net: 5, avg: 10), currentPrice: 12),
        closeTo(10, 1e-9),
      );
      expect(
        computeUnrealizedPnL(position: pos(net: 5, avg: 10), currentPrice: 8),
        closeTo(-10, 1e-9),
      );
    });

    test('combined with computePosition from a real lot set', () {
      final p = computePosition([
        makeLot(id: 'b1', kind: 'buy', quantity: 100, price: 10),
      ]);
      expect(
        computeUnrealizedPnL(position: p, currentPrice: 12),
        closeTo(200, 1e-9),
      );
    });
  });
}
