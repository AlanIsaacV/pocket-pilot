import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_pilot/src/features/investments/domain/investment_holding.dart';
import 'package:pocket_pilot/src/features/investments/domain/investment_lot.dart';
import 'package:pocket_pilot/src/features/investments/domain/market_price.dart';
import 'package:pocket_pilot/src/features/investments/domain/portfolio_distribution.dart';

InvestmentHoldingModel makeHolding({
  String id = 'h1',
  String symbol = 'AAPL',
  String exchange = 'NASDAQ',
  String displayName = 'Apple Inc.',
  String currencyCode = 'USD',
  String status = 'active',
  double? manualPrice,
  DateTime? deletedAt,
}) {
  return InvestmentHoldingModel(
    id: id,
    symbol: symbol,
    exchange: exchange,
    displayName: displayName,
    currencyCode: currencyCode,
    assetType: 'stock',
    status: status,
    manualPrice: manualPrice,
    createdAt: DateTime.utc(2026, 1, 1),
    updatedAt: DateTime.utc(2026, 1, 1),
    deletedAt: deletedAt,
  );
}

InvestmentLotModel makeLot({
  String id = 'l1',
  String holdingId = 'h1',
  String kind = 'buy',
  double quantity = 1,
  double price = 0,
  String occurredAt = '2026-01-01',
  String validity = 'valid',
  DateTime? deletedAt,
}) {
  return InvestmentLotModel(
    id: id,
    holdingId: holdingId,
    accountId: 'a1',
    kind: kind,
    quantity: quantity,
    price: price,
    feeCents: 0,
    occurredAt: occurredAt,
    validity: validity,
    createdAt: DateTime.utc(2026, 1, 1),
    updatedAt: DateTime.utc(2026, 1, 1),
    deletedAt: deletedAt,
  );
}

MarketPriceModel makePrice({
  String symbol = 'AAPL',
  String exchange = 'NASDAQ',
  double price = 100,
  String currencyCode = 'USD',
}) {
  return MarketPriceModel(
    symbol: symbol,
    exchange: exchange,
    currencyCode: currencyCode,
    price: price,
    priceDate: '2026-04-21',
    source: 'yahoo',
    fetchedAt: DateTime.utc(2026, 4, 21),
    updatedAt: DateTime.utc(2026, 4, 21),
  );
}

void main() {
  group('computePortfolioDistribution', () {
    test('empty input returns empty map', () {
      final result = computePortfolioDistribution(
        holdings: const [],
        lotsFor: (_) => const [],
        priceFor: (_, _) => null,
      );
      expect(result, isEmpty);
    });

    test('single USD holding yields one group with pct=1.0', () {
      final holding = makeHolding(id: 'h1', symbol: 'AAPL');
      final lots = [makeLot(id: 'b1', holdingId: 'h1', quantity: 10, price: 50)];
      final result = computePortfolioDistribution(
        holdings: [holding],
        lotsFor: (id) => id == 'h1' ? lots : const [],
        priceFor: (s, e) => makePrice(symbol: s, exchange: e, price: 200),
      );

      expect(result.keys, ['USD']);
      expect(result['USD'], hasLength(1));
      final slice = result['USD']!.first;
      expect(slice.holdingId, 'h1');
      expect(slice.symbol, 'AAPL');
      expect(slice.marketValue, closeTo(2000, 1e-9));
      expect(slice.percentage, closeTo(1.0, 1e-9));
    });

    test('two USD + one MXN groups by currency with per-group percentages', () {
      final holdings = [
        makeHolding(id: 'h1', symbol: 'AAPL', currencyCode: 'USD'),
        makeHolding(id: 'h2', symbol: 'MSFT', currencyCode: 'USD'),
        makeHolding(id: 'h3', symbol: 'AMXL', exchange: 'BMV', currencyCode: 'MXN'),
      ];
      final lotsByHolding = {
        'h1': [makeLot(id: 'l1', holdingId: 'h1', quantity: 10, price: 10)],
        'h2': [makeLot(id: 'l2', holdingId: 'h2', quantity: 5, price: 10)],
        'h3': [makeLot(id: 'l3', holdingId: 'h3', quantity: 100, price: 10)],
      };
      final pricesBySymbol = {
        'AAPL': 300.0,
        'MSFT': 100.0,
        'AMXL': 20.0,
      };

      final result = computePortfolioDistribution(
        holdings: holdings,
        lotsFor: (id) => lotsByHolding[id] ?? const [],
        priceFor: (s, e) =>
            makePrice(symbol: s, exchange: e, price: pricesBySymbol[s] ?? 0),
      );

      expect(result.keys.toSet(), {'USD', 'MXN'});
      expect(result['USD'], hasLength(2));
      expect(result['MXN'], hasLength(1));

      final usdSum =
          result['USD']!.fold<double>(0, (a, s) => a + s.percentage);
      expect(usdSum, closeTo(1.0, 1e-9));
      final mxnSum =
          result['MXN']!.fold<double>(0, (a, s) => a + s.percentage);
      expect(mxnSum, closeTo(1.0, 1e-9));

      // AAPL market value = 10 * 300 = 3000; MSFT = 5 * 100 = 500 → AAPL first.
      expect(result['USD']!.first.symbol, 'AAPL');
      expect(result['USD']!.first.percentage, closeTo(3000 / 3500, 1e-9));
      expect(result['USD']!.last.symbol, 'MSFT');
    });

    test('net quantity zero (fully sold) is excluded', () {
      final holding = makeHolding(id: 'h1', symbol: 'AAPL');
      final lots = [
        makeLot(id: 'b1', holdingId: 'h1', kind: 'buy', quantity: 10, price: 50),
        makeLot(
          id: 's1',
          holdingId: 'h1',
          kind: 'sell',
          quantity: 10,
          price: 60,
          occurredAt: '2026-02-01',
        ),
      ];
      final result = computePortfolioDistribution(
        holdings: [holding],
        lotsFor: (_) => lots,
        priceFor: (s, e) => makePrice(symbol: s, exchange: e, price: 200),
      );
      expect(result, isEmpty);
    });

    test('net quantity negative (sell > buy) is excluded', () {
      final holding = makeHolding(id: 'h1', symbol: 'AAPL');
      final lots = [
        makeLot(id: 'b1', holdingId: 'h1', kind: 'buy', quantity: 5, price: 50),
        makeLot(
          id: 's1',
          holdingId: 'h1',
          kind: 'sell',
          quantity: 10,
          price: 60,
          occurredAt: '2026-02-01',
        ),
      ];
      final result = computePortfolioDistribution(
        holdings: [holding],
        lotsFor: (_) => lots,
        priceFor: (s, e) => makePrice(symbol: s, exchange: e, price: 200),
      );
      expect(result, isEmpty);
    });

    test('no price and no fallback excludes the holding', () {
      final holding = makeHolding(id: 'h1', symbol: 'AAPL', manualPrice: null);
      final lots = [
        makeLot(
          id: 'b1',
          holdingId: 'h1',
          kind: 'buy',
          quantity: 10,
          price: 0, // price 0 means "last lot price" fallback is 0 → excluded
        ),
      ];
      final result = computePortfolioDistribution(
        holdings: [holding],
        lotsFor: (_) => lots,
        priceFor: (_, _) => null,
      );
      expect(result, isEmpty);
    });

    test('manual price is used when market price is null', () {
      final holding =
          makeHolding(id: 'h1', symbol: 'AAPL', manualPrice: 150);
      final lots = [makeLot(id: 'b1', holdingId: 'h1', quantity: 10, price: 50)];
      final result = computePortfolioDistribution(
        holdings: [holding],
        lotsFor: (_) => lots,
        priceFor: (_, _) => null,
      );
      expect(result['USD'], hasLength(1));
      expect(result['USD']!.first.marketValue, closeTo(1500, 1e-9));
    });

    test('soft-deleted holdings are excluded', () {
      final holding = makeHolding(
        id: 'h1',
        symbol: 'AAPL',
        deletedAt: DateTime.utc(2026, 3, 1),
      );
      final lots = [makeLot(id: 'b1', holdingId: 'h1', quantity: 10, price: 50)];
      final result = computePortfolioDistribution(
        holdings: [holding],
        lotsFor: (_) => lots,
        priceFor: (s, e) => makePrice(symbol: s, exchange: e, price: 200),
      );
      expect(result, isEmpty);
    });

    test('closed holdings are excluded', () {
      final holding =
          makeHolding(id: 'h1', symbol: 'AAPL', status: 'closed');
      final lots = [makeLot(id: 'b1', holdingId: 'h1', quantity: 10, price: 50)];
      final result = computePortfolioDistribution(
        holdings: [holding],
        lotsFor: (_) => lots,
        priceFor: (s, e) => makePrice(symbol: s, exchange: e, price: 200),
      );
      expect(result, isEmpty);
    });

    test('slices within a currency are sorted desc by market value', () {
      final holdings = [
        makeHolding(id: 'h1', symbol: 'AAA'),
        makeHolding(id: 'h2', symbol: 'BBB'),
        makeHolding(id: 'h3', symbol: 'CCC'),
      ];
      final lotsByHolding = {
        'h1': [makeLot(id: 'l1', holdingId: 'h1', quantity: 1, price: 1)],
        'h2': [makeLot(id: 'l2', holdingId: 'h2', quantity: 1, price: 1)],
        'h3': [makeLot(id: 'l3', holdingId: 'h3', quantity: 1, price: 1)],
      };
      final pricesBySymbol = {
        'AAA': 5.0,
        'BBB': 100.0,
        'CCC': 20.0,
      };

      final result = computePortfolioDistribution(
        holdings: holdings,
        lotsFor: (id) => lotsByHolding[id] ?? const [],
        priceFor: (s, e) =>
            makePrice(symbol: s, exchange: e, price: pricesBySymbol[s] ?? 0),
      );

      final symbols = result['USD']!.map((s) => s.symbol).toList();
      expect(symbols, ['BBB', 'CCC', 'AAA']);
    });

    test('market price takes precedence over manual price', () {
      final holding = makeHolding(
        id: 'h1',
        symbol: 'AAPL',
        manualPrice: 999,
      );
      final lots = [makeLot(id: 'b1', holdingId: 'h1', quantity: 1, price: 10)];
      final result = computePortfolioDistribution(
        holdings: [holding],
        lotsFor: (_) => lots,
        priceFor: (s, e) => makePrice(symbol: s, exchange: e, price: 100),
      );
      expect(result['USD']!.first.marketValue, closeTo(100, 1e-9));
    });
  });
}
