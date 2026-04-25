import 'package:flutter_test/flutter_test.dart';

import 'package:pocket_pilot/src/features/investments/domain/current_price_resolver.dart';
import 'package:pocket_pilot/src/features/investments/domain/investment_holding.dart';
import 'package:pocket_pilot/src/features/investments/domain/investment_lot.dart';
import 'package:pocket_pilot/src/features/investments/domain/investment_split.dart';
import 'package:pocket_pilot/src/features/investments/domain/market_price.dart';

InvestmentHoldingModel makeHolding({
  String id = 'h1',
  String symbol = 'AAPL',
  String exchange = 'NASDAQ',
  String currencyCode = 'USD',
  String status = 'active',
  double? manualPrice,
}) =>
    InvestmentHoldingModel(
      id: id,
      symbol: symbol,
      exchange: exchange,
      displayName: symbol,
      currencyCode: currencyCode,
      assetType: 'stock',
      status: status,
      manualPrice: manualPrice,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );

InvestmentLotModel makeLot({
  String id = 'l1',
  String holdingId = 'h1',
  double quantity = 1,
  double price = 100,
  String occurredAt = '2026-01-01',
  String validity = 'valid',
  DateTime? deletedAt,
}) =>
    InvestmentLotModel(
      id: id,
      holdingId: holdingId,
      accountId: 'a1',
      kind: 'buy',
      quantity: quantity,
      price: price,
      feeCents: 0,
      occurredAt: occurredAt,
      validity: validity,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
      deletedAt: deletedAt,
    );

InvestmentSplitModel makeSplit({
  String id = 's1',
  String holdingId = 'h1',
  double ratioNum = 2,
  double ratioDen = 1,
  String occurredAt = '2026-02-01',
  DateTime? deletedAt,
}) =>
    InvestmentSplitModel(
      id: id,
      holdingId: holdingId,
      ratioNum: ratioNum,
      ratioDen: ratioDen,
      occurredAt: occurredAt,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
      deletedAt: deletedAt,
    );

MarketPriceModel makePrice({double price = 200}) => MarketPriceModel(
      symbol: 'AAPL',
      exchange: 'NASDAQ',
      currencyCode: 'USD',
      price: price,
      priceDate: '2026-04-25',
      source: 'yahoo',
      fetchedAt: DateTime.utc(2026, 4, 25),
      updatedAt: DateTime.utc(2026, 4, 25),
    );

void main() {
  group('resolveCurrentPrice precedence', () {
    test('market price wins over manual + last lot', () {
      final q = resolveCurrentPrice(
        holding: makeHolding(manualPrice: 150),
        marketPrice: makePrice(price: 200),
        lots: [makeLot(price: 100)],
      );
      expect(q.price, 200);
      expect(q.source, 'market');
    });

    test('manual price wins over last lot when market is null', () {
      final q = resolveCurrentPrice(
        holding: makeHolding(manualPrice: 150),
        marketPrice: null,
        lots: [makeLot(price: 100)],
      );
      expect(q.price, 150);
      expect(q.source, 'manual');
    });

    test('last lot fallback when neither market nor manual present', () {
      final q = resolveCurrentPrice(
        holding: makeHolding(),
        marketPrice: null,
        lots: [makeLot(price: 100)],
      );
      expect(q.price, 100);
      expect(q.source, 'last_lot');
    });

    test('no source when there are no eligible lots', () {
      final q = resolveCurrentPrice(
        holding: makeHolding(),
        marketPrice: null,
        lots: [],
      );
      expect(q.price, isNull);
      expect(q.source, 'none');
    });

    test('soft-deleted and invalid lots are not eligible candidates', () {
      final q = resolveCurrentPrice(
        holding: makeHolding(),
        marketPrice: null,
        lots: [
          makeLot(id: 'd', price: 100, deletedAt: DateTime.utc(2026, 3, 1)),
          makeLot(id: 'i', price: 90, validity: 'invalid'),
        ],
      );
      expect(q.price, isNull);
      expect(q.source, 'none');
    });
  });

  group('resolveCurrentPrice last_lot fallback adjusted by splits', () {
    test('single 2:1 split after the last lot halves the price', () {
      final q = resolveCurrentPrice(
        holding: makeHolding(),
        marketPrice: null,
        lots: [makeLot(occurredAt: '2026-01-01', price: 100)],
        splits: [makeSplit(occurredAt: '2026-02-01', ratioNum: 2, ratioDen: 1)],
      );
      expect(q.source, 'last_lot');
      expect(q.price, closeTo(50, 1e-9));
    });

    test('multiple splits after the last lot compound', () {
      final q = resolveCurrentPrice(
        holding: makeHolding(),
        marketPrice: null,
        lots: [makeLot(occurredAt: '2026-01-01', price: 100)],
        splits: [
          makeSplit(id: 's1', occurredAt: '2026-02-01', ratioNum: 2, ratioDen: 1),
          makeSplit(id: 's2', occurredAt: '2026-03-01', ratioNum: 3, ratioDen: 1),
        ],
      );
      // 100 / (2 * 3) = 100 / 6
      expect(q.price, closeTo(100 / 6, 1e-9));
    });

    test('reverse 1:10 split after the lot scales price up', () {
      final q = resolveCurrentPrice(
        holding: makeHolding(),
        marketPrice: null,
        lots: [makeLot(occurredAt: '2026-01-01', price: 5)],
        splits: [makeSplit(occurredAt: '2026-02-01', ratioNum: 1, ratioDen: 10)],
      );
      // 5 / (1/10) = 50
      expect(q.price, closeTo(50, 1e-9));
    });

    test('split BEFORE the lot does NOT adjust the fallback', () {
      final q = resolveCurrentPrice(
        holding: makeHolding(),
        marketPrice: null,
        lots: [makeLot(occurredAt: '2026-03-01', price: 100)],
        splits: [makeSplit(occurredAt: '2026-02-01', ratioNum: 2, ratioDen: 1)],
      );
      expect(q.price, closeTo(100, 1e-9));
    });

    test('split on the SAME date as the lot does not adjust', () {
      // The lot price is already in that day's share count.
      final q = resolveCurrentPrice(
        holding: makeHolding(),
        marketPrice: null,
        lots: [makeLot(occurredAt: '2026-02-01', price: 50)],
        splits: [makeSplit(occurredAt: '2026-02-01', ratioNum: 2, ratioDen: 1)],
      );
      expect(q.price, closeTo(50, 1e-9));
    });

    test('soft-deleted split is ignored', () {
      final q = resolveCurrentPrice(
        holding: makeHolding(),
        marketPrice: null,
        lots: [makeLot(occurredAt: '2026-01-01', price: 100)],
        splits: [
          makeSplit(
            occurredAt: '2026-02-01',
            ratioNum: 2,
            ratioDen: 1,
            deletedAt: DateTime.utc(2026, 3, 1),
          ),
        ],
      );
      expect(q.price, closeTo(100, 1e-9));
    });
  });
}
