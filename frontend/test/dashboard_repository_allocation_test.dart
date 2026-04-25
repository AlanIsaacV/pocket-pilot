import 'package:flutter_test/flutter_test.dart';

import 'package:pocket_pilot/src/core/db/database_helper.dart';
import 'package:pocket_pilot/src/features/dashboard/data/dashboard_local_store.dart';
import 'package:pocket_pilot/src/features/dashboard/data/dashboard_repository.dart';
import 'package:pocket_pilot/src/features/dashboard/domain/account_balance_dto.dart';
import 'package:pocket_pilot/src/features/dashboard/domain/credit_card_account_cycle_dto.dart';
import 'package:pocket_pilot/src/features/dashboard/domain/credit_card_movement_dto.dart';
import 'package:pocket_pilot/src/features/goals/domain/goal.dart';
import 'package:pocket_pilot/src/features/investments/data/investment_holding_local_store.dart';
import 'package:pocket_pilot/src/features/investments/data/investment_lot_local_store.dart';
import 'package:pocket_pilot/src/features/investments/data/investment_split_local_store.dart';
import 'package:pocket_pilot/src/features/investments/data/market_price_local_store.dart';

void main() {
  group('calculateAllMetrics — allocation buckets', () {
    test('post-buy invariant: net worth = pre-buy minus fees', () async {
      // Antes: cuenta USD con $1000 (100,000 cents).
      // Compra: 5 × $100 = $500 + $5 fee = $505 total → balance $495.
      // Holdings: 5 × AAPL @ $100 (resolver fallback al precio del lote
      // cuando no hay market_price). Market value = $500.
      // Net worth post-buy = $495 + $500 = $995. Diferencia vs pre-buy = $5
      // (los fees) — esa es la invariante.
      final repo = _buildRepo(
        balances: const [
          AccountBalanceDTO(
            accountId: 'usd-1',
            accountName: 'Brokerage',
            accountType: 'investment',
            currencyCode: 'USD',
            balanceCents: 49500,
          ),
        ],
        holdings: [
          _holding(id: 'h1', symbol: 'AAPL', currency: 'USD'),
        ],
        lotsByHolding: {
          'h1': [
            _lot(id: 'l1', holdingId: 'h1', kind: 'buy', qty: 5, price: 100),
          ],
        },
        prices: const {},
      );

      final result = await repo.calculateAllMetrics();
      final usd = result['USD']!;

      expect(usd.marketValueOfHoldingsCents, 50000);
      expect(usd.netWorthCents, 99500);
    });

    test('multi-currency keeps holdings separate', () async {
      final repo = _buildRepo(
        balances: const [
          AccountBalanceDTO(
            accountId: 'usd-1',
            accountName: 'USD',
            accountType: 'bank',
            currencyCode: 'USD',
            balanceCents: 100000,
          ),
          AccountBalanceDTO(
            accountId: 'mxn-1',
            accountName: 'MXN',
            accountType: 'bank',
            currencyCode: 'MXN',
            balanceCents: 200000,
          ),
        ],
        holdings: [
          _holding(id: 'h1', symbol: 'AAPL', currency: 'USD'),
          _holding(id: 'h2', symbol: 'AMXL', exchange: 'BMV', currency: 'MXN'),
        ],
        lotsByHolding: {
          'h1': [_lot(id: 'l1', holdingId: 'h1', qty: 10, price: 50)],
          'h2': [_lot(id: 'l2', holdingId: 'h2', qty: 100, price: 20)],
        },
        prices: const {},
      );

      final result = await repo.calculateAllMetrics();

      expect(result['USD']!.marketValueOfHoldingsCents, 50000);
      expect(result['USD']!.netWorthCents, 100000 + 50000);
      expect(result['MXN']!.marketValueOfHoldingsCents, 200000);
      expect(result['MXN']!.netWorthCents, 200000 + 200000);
    });

    test('no holdings → market value 0, netWorth equals balances sum',
        () async {
      final repo = _buildRepo(
        balances: const [
          AccountBalanceDTO(
            accountId: 'b1',
            accountName: 'B',
            accountType: 'bank',
            currencyCode: 'USD',
            balanceCents: 75000,
          ),
        ],
      );

      final result = await repo.calculateAllMetrics();
      expect(result['USD']!.marketValueOfHoldingsCents, 0);
      expect(result['USD']!.netWorthCents, 75000);
    });

    test('yields contribute to bucket but not double-count net worth',
        () async {
      // Cuenta MXN con $5000 (incluye un pagaré de $2000 ya contado en
      // balance). El bucket de yields = $2000; el bucket "liquid para
      // barra" calculado en UI será $5000 - $2000 = $3000 free liquid.
      // Pero netWorth = $5000 (no se suma yields aparte).
      final repo = _buildRepo(
        balances: const [
          AccountBalanceDTO(
            accountId: 'bbva-1',
            accountName: 'BBVA',
            accountType: 'bank',
            currencyCode: 'MXN',
            balanceCents: 500000,
          ),
        ],
        yieldsByCurrency: const {'MXN': 200000},
      );

      final result = await repo.calculateAllMetrics();
      final mxn = result['MXN']!;

      expect(mxn.liquidAssetsCents, 500000);
      expect(mxn.yieldsValueCents, 200000);
      expect(mxn.netWorthCents, 500000); // sin doble conteo
    });

    test('debt and revolving exposed from credit cards', () async {
      final repo = _buildRepo(
        balances: const [
          AccountBalanceDTO(
            accountId: 'b1',
            accountName: 'Bank',
            accountType: 'bank',
            currencyCode: 'MXN',
            balanceCents: 300000,
          ),
          AccountBalanceDTO(
            accountId: 'c1',
            accountName: 'TC',
            accountType: 'credit_card',
            currencyCode: 'MXN',
            balanceCents: -40000,
            creditLimitCents: 100000,
          ),
          AccountBalanceDTO(
            accountId: 'l1',
            accountName: 'Loan',
            accountType: 'loan',
            currencyCode: 'MXN',
            balanceCents: -150000,
          ),
        ],
      );

      final result = await repo.calculateAllMetrics();
      final mxn = result['MXN']!;

      // debt = |credit_card -40000| + |loan -150000| = 190000
      expect(mxn.debtCents, 190000);
      // revolving = limit 100000 + balance -40000 = 60000
      expect(mxn.revolvingCreditCents, 60000);
      // netWorth = 300000 - 40000 - 150000 = 110000 (sin holdings)
      expect(mxn.netWorthCents, 110000);
    });

    test('post-split market value reflects adjusted qty × post-split price',
        () async {
      // Holding AAPL: buy 10 @ $100. 2:1 split posterior. Yahoo da $60
      // (post-split). Invariante: market value = 20 × $60 = $1200, no
      // 10 × $60 = $600.
      final repo = _buildRepo(
        balances: const [
          AccountBalanceDTO(
            accountId: 'usd-1',
            accountName: 'Brokerage',
            accountType: 'investment',
            currencyCode: 'USD',
            balanceCents: 0,
          ),
        ],
        holdings: [_holding(id: 'h1', symbol: 'AAPL', currency: 'USD')],
        lotsByHolding: {
          'h1': [_lot(id: 'l1', holdingId: 'h1', qty: 10, price: 100)],
        },
        splitsByHolding: {
          'h1': [
            _split(
              id: 'sp1',
              holdingId: 'h1',
              ratioNum: 2,
              ratioDen: 1,
              occurredAt: '2026-02-01',
            ),
          ],
        },
        prices: {
          'AAPL:NASDAQ': _price(
            symbol: 'AAPL',
            exchange: 'NASDAQ',
            price: 60,
            currencyCode: 'USD',
          ),
        },
      );

      final result = await repo.calculateAllMetrics();
      final usd = result['USD']!;

      expect(usd.marketValueOfHoldingsCents, 120000);
      expect(usd.netWorthCents, 120000);
    });

    test('holdings ignore accountIds filter (globals); rest respects it',
        () async {
      // Filtro selecciona solo MXN. La query de balances ya viene filtrada
      // (el fake honra accountIds), pero los holdings se cargan completos
      // porque son globales.
      final repo = _buildRepo(
        balancesByFilter: (ids) {
          final mxn = const AccountBalanceDTO(
            accountId: 'mxn-1',
            accountName: 'MXN',
            accountType: 'bank',
            currencyCode: 'MXN',
            balanceCents: 100000,
          );
          final usd = const AccountBalanceDTO(
            accountId: 'usd-1',
            accountName: 'USD',
            accountType: 'bank',
            currencyCode: 'USD',
            balanceCents: 50000,
          );
          if (ids == null) return [mxn, usd];
          return [if (ids.contains('mxn-1')) mxn, if (ids.contains('usd-1')) usd];
        },
        holdings: [_holding(id: 'h1', symbol: 'AAPL', currency: 'USD')],
        lotsByHolding: {
          'h1': [_lot(id: 'l1', holdingId: 'h1', qty: 1, price: 200)],
        },
      );

      final filtered = await repo.calculateAllMetrics(accountIds: {'mxn-1'});
      // Solo MXN entra en balances filtrados, pero los holdings USD siguen
      // contribuyendo a la moneda USD (que aparece sin balance bancario).
      expect(filtered['MXN']!.netWorthCents, 100000);
      expect(filtered['USD']!.marketValueOfHoldingsCents, 20000);
      expect(filtered['USD']!.liquidAssetsCents, 0);
      expect(filtered['USD']!.netWorthCents, 20000);
    });
  });
}

DashboardRepository _buildRepo({
  List<AccountBalanceDTO> balances = const [],
  List<AccountBalanceDTO> Function(Set<String>?)? balancesByFilter,
  List<Map<String, dynamic>> holdings = const [],
  Map<String, List<Map<String, dynamic>>> lotsByHolding = const {},
  Map<String, List<Map<String, dynamic>>> splitsByHolding = const {},
  Map<String, Map<String, dynamic>> prices = const {},
  Map<String, int> yieldsByCurrency = const {},
}) {
  return DashboardRepository(
    local: _FakeLocal(
      balances: balances,
      balancesByFilter: balancesByFilter,
      yieldsByCurrency: yieldsByCurrency,
    ),
    holdingStore: _FakeHoldingStore(rows: holdings),
    lotStore: _FakeLotStore(byHolding: lotsByHolding),
    splitStore: _FakeSplitStore(byHolding: splitsByHolding),
    marketPriceStore: _FakePriceStore(prices: prices),
    nowProvider: () => DateTime.utc(2026, 5, 4),
  );
}

Map<String, dynamic> _holding({
  required String id,
  required String symbol,
  String exchange = 'NASDAQ',
  required String currency,
}) {
  return {
    'id': id,
    'symbol': symbol,
    'exchange': exchange,
    'display_name': symbol,
    'currency_code': currency,
    'asset_type': 'stock',
    'status': 'active',
    'manual_price': null,
    'notes': null,
    'created_at': DateTime.utc(2026, 1, 1).toIso8601String(),
    'updated_at': DateTime.utc(2026, 1, 1).toIso8601String(),
    'deleted_at': null,
  };
}

Map<String, dynamic> _split({
  required String id,
  required String holdingId,
  required double ratioNum,
  required double ratioDen,
  required String occurredAt,
}) {
  return {
    'id': id,
    'holding_id': holdingId,
    'ratio_num': ratioNum,
    'ratio_den': ratioDen,
    'occurred_at': occurredAt,
    'notes': null,
    'created_at': DateTime.utc(2026, 1, 1).toIso8601String(),
    'updated_at': DateTime.utc(2026, 1, 1).toIso8601String(),
    'deleted_at': null,
  };
}

Map<String, dynamic> _price({
  required String symbol,
  required String exchange,
  required double price,
  required String currencyCode,
}) {
  return {
    'symbol': symbol,
    'exchange': exchange,
    'currency_code': currencyCode,
    'price': price,
    'price_date': '2026-04-25',
    'source': 'yahoo',
    'fetched_at': DateTime.utc(2026, 4, 25).toIso8601String(),
    'updated_at': DateTime.utc(2026, 4, 25).toIso8601String(),
  };
}

Map<String, dynamic> _lot({
  required String id,
  required String holdingId,
  String kind = 'buy',
  required double qty,
  required double price,
  int feeCents = 0,
}) {
  return {
    'id': id,
    'holding_id': holdingId,
    'account_id': 'a1',
    'kind': kind,
    'quantity': qty,
    'price': price,
    'fee_cents': feeCents,
    'fx_rate': null,
    'occurred_at': '2026-01-01',
    'validity': 'valid',
    'notes': null,
    'created_at': DateTime.utc(2026, 1, 1).toIso8601String(),
    'updated_at': DateTime.utc(2026, 1, 1).toIso8601String(),
    'deleted_at': null,
  };
}

class _FakeLocal extends DashboardLocalStore {
  final List<AccountBalanceDTO> balances;
  final List<AccountBalanceDTO> Function(Set<String>?)? balancesByFilter;
  final Map<String, int> yieldsByCurrency;

  _FakeLocal({
    required this.balances,
    this.balancesByFilter,
    required this.yieldsByCurrency,
  }) : super(db: DatabaseHelper());

  @override
  Future<List<AccountBalanceDTO>> getBalancesPerAccount({
    Set<String>? accountIds,
  }) async {
    final fn = balancesByFilter;
    if (fn != null) return fn(accountIds);
    return balances;
  }

  @override
  Future<List<GoalModel>> getActiveGoals() async => const [];

  @override
  Future<List<CreditCardAccountCycleDTO>> getCreditCardAccounts({
    Set<String>? accountIds,
  }) async => const [];

  @override
  Future<List<CreditCardMovementDTO>> getCreditCardMovementsForProjection(
    String maxDate, {
    Set<String>? accountIds,
    String? currencyCode,
  }) async => const [];

  @override
  Future<Map<String, int>> getYieldsValueByCurrency({
    Set<String>? accountIds,
  }) async => yieldsByCurrency;
}

class _FakeHoldingStore extends InvestmentHoldingLocalStore {
  final List<Map<String, dynamic>> rows;
  _FakeHoldingStore({required this.rows}) : super(db: DatabaseHelper());

  @override
  Future<List<Map<String, dynamic>>> queryRows() async => rows;
}

class _FakeLotStore extends InvestmentLotLocalStore {
  final Map<String, List<Map<String, dynamic>>> byHolding;
  _FakeLotStore({required this.byHolding}) : super(db: DatabaseHelper());

  @override
  Future<List<Map<String, dynamic>>> queryByHolding(String holdingId) async {
    return byHolding[holdingId] ?? const [];
  }
}

class _FakeSplitStore extends InvestmentSplitLocalStore {
  final Map<String, List<Map<String, dynamic>>> byHolding;
  _FakeSplitStore({required this.byHolding}) : super(db: DatabaseHelper());

  @override
  Future<List<Map<String, dynamic>>> queryByHolding(String holdingId) async {
    return byHolding[holdingId] ?? const [];
  }
}

class _FakePriceStore extends MarketPriceLocalStore {
  final Map<String, Map<String, dynamic>> prices;
  _FakePriceStore({required this.prices}) : super(db: DatabaseHelper());

  @override
  Future<Map<String, dynamic>?> getBySymbolExchange(
    String symbol,
    String exchange,
  ) async => prices['${symbol.toUpperCase()}:${exchange.toUpperCase()}'];
}
