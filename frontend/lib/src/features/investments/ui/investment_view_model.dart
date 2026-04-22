import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:pocket_pilot/src/core/sync/scheduled_generation_orchestrator.dart';
import 'package:pocket_pilot/src/core/sync/sync_service.dart';
import 'package:pocket_pilot/src/features/investments/data/investment_holding_repository.dart';
import 'package:pocket_pilot/src/features/investments/data/investment_lot_repository.dart';
import 'package:pocket_pilot/src/features/investments/data/market_price_local_store.dart';
import 'package:pocket_pilot/src/features/investments/domain/investment_holding.dart';
import 'package:pocket_pilot/src/features/investments/domain/investment_lot.dart';
import 'package:pocket_pilot/src/features/investments/domain/market_price.dart';
import 'package:pocket_pilot/src/features/transactions/data/transaction_local_store.dart';
import 'package:pocket_pilot/src/features/transactions/domain/transaction.dart';

class InvestmentViewModel extends ChangeNotifier {
  final InvestmentHoldingRepository _holdingRepo;
  final InvestmentLotRepository _lotRepo;
  final MarketPriceLocalStore _marketPriceStore;
  final TransactionLocalStore _transactionStore;
  final SyncService _syncService;
  final ScheduledGenerationOrchestrator _orchestrator;

  List<InvestmentHoldingModel> _allHoldings = const [];
  final Map<String, List<InvestmentLotModel>> _lotsByHolding = {};
  final Map<String, MarketPriceModel?> _priceBySymbolExchange = {};
  final Map<String, List<TransactionModel>> _dividendsByHolding = {};
  DateTime? _maxFetchedAt;

  bool _isLoadingAll = false;
  String? _loadingHoldingId;
  bool _isSyncing = false;
  String? _errorMessage;
  bool _disposed = false;

  InvestmentViewModel({
    required InvestmentHoldingRepository holdingRepo,
    required InvestmentLotRepository lotRepo,
    required MarketPriceLocalStore marketPriceStore,
    required TransactionLocalStore transactionStore,
    required SyncService syncService,
    required ScheduledGenerationOrchestrator orchestrator,
  }) : _holdingRepo = holdingRepo,
       _lotRepo = lotRepo,
       _marketPriceStore = marketPriceStore,
       _transactionStore = transactionStore,
       _syncService = syncService,
       _orchestrator = orchestrator;

  List<InvestmentHoldingModel> get allHoldings => _allHoldings;

  List<InvestmentLotModel> lotsFor(String holdingId) =>
      _lotsByHolding[holdingId] ?? const [];

  MarketPriceModel? priceFor(String symbol, String exchange) =>
      _priceBySymbolExchange['${symbol.toUpperCase()}:${exchange.toUpperCase()}'];

  List<TransactionModel> dividendsFor(String holdingId) =>
      _dividendsByHolding[holdingId] ?? const [];

  /// Wall-clock of the freshest `market_prices.fetched_at` row cached
  /// locally. `null` when no prices have been synced (user with no
  /// covered symbols, or backend cron not yet active).
  DateTime? get maxFetchedAt => _maxFetchedAt;

  /// Total de dividendos (solo `cleared`) agrupados por currency del tx.
  /// Se usa `currency_code` del tx (no del holding) para que, si el usuario
  /// registró el dividendo en una cuenta de otra moneda, el total refleje
  /// la realidad en esa currency.
  Map<String, double> totalDividendsFor(String holdingId) {
    final result = <String, double>{};
    for (final tx in dividendsFor(holdingId)) {
      if (tx.status != 'cleared') continue;
      final ccy = tx.currencyCode.toUpperCase();
      result[ccy] = (result[ccy] ?? 0) + tx.amount / 100.0;
    }
    return result;
  }

  bool get isLoadingAll => _isLoadingAll;
  bool isLoadingHolding(String holdingId) => _loadingHoldingId == holdingId;
  bool get isSyncing => _isSyncing;
  String? get errorMessage => _errorMessage;

  InvestmentHoldingModel? findHolding(String id) {
    for (final h in _allHoldings) {
      if (h.id == id) return h;
    }
    return null;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  void loadOnAppear() {
    unawaited(loadPortfolio());
  }

  Future<void> loadAll() async {
    _isLoadingAll = _allHoldings.isEmpty;
    _safeNotify();
    try {
      _allHoldings = await _holdingRepo.getAll();
      _errorMessage = null;
    } catch (e) {
      _errorMessage = e.toString();
    } finally {
      _isLoadingAll = false;
      _safeNotify();
    }
  }

  /// Carga la lista global de holdings y pre-carga por cada uno sus lots,
  /// precio de mercado y dividendos en paralelo. Un error en un holding
  /// no tumba al resto (`eagerError: false`).
  Future<void> loadPortfolio() async {
    _isLoadingAll = _allHoldings.isEmpty;
    _safeNotify();
    try {
      final holdings = await _holdingRepo.getAll();
      _allHoldings = holdings;

      final futures = <Future<void>>[];
      for (final h in holdings) {
        futures.add(() async {
          try {
            _lotsByHolding[h.id] = await _lotRepo.getByHolding(h.id);
          } catch (_) {
            _lotsByHolding[h.id] = const [];
          }
          try {
            final row = await _marketPriceStore.getBySymbolExchange(
              h.symbol,
              h.exchange,
            );
            _priceBySymbolExchange['${h.symbol}:${h.exchange}'] =
                row == null ? null : MarketPriceModel.fromMap(row);
          } catch (_) {
            _priceBySymbolExchange['${h.symbol}:${h.exchange}'] = null;
          }
          try {
            final rows = await _transactionStore.queryDividendsByHolding(h.id);
            _dividendsByHolding[h.id] =
                rows.map(TransactionModel.fromMap).toList();
          } catch (_) {
            _dividendsByHolding[h.id] = const [];
          }
        }());
      }
      await Future.wait(futures, eagerError: false);
      try {
        _maxFetchedAt = await _marketPriceStore.getMaxFetchedAt();
      } catch (_) {
        _maxFetchedAt = null;
      }
      _errorMessage = null;
    } catch (e) {
      _errorMessage = e.toString();
    } finally {
      _isLoadingAll = false;
      _safeNotify();
    }
  }

  Future<void> loadHolding(String holdingId) async {
    _loadingHoldingId = holdingId;
    _safeNotify();
    try {
      _lotsByHolding[holdingId] = await _lotRepo.getByHolding(holdingId);
      _errorMessage = null;
    } catch (e) {
      _errorMessage = e.toString();
    } finally {
      _loadingHoldingId = null;
      _safeNotify();
    }
  }

  /// Variante de [loadHolding] que además refresca el precio de mercado y
  /// los dividendos para ese holding. Usada por HoldingDetailScreen.
  Future<void> loadHoldingFull(String holdingId) async {
    _loadingHoldingId = holdingId;
    _safeNotify();
    try {
      _lotsByHolding[holdingId] = await _lotRepo.getByHolding(holdingId);
      final holding = findHolding(holdingId);
      if (holding != null) {
        final row = await _marketPriceStore.getBySymbolExchange(
          holding.symbol,
          holding.exchange,
        );
        _priceBySymbolExchange['${holding.symbol}:${holding.exchange}'] =
            row == null ? null : MarketPriceModel.fromMap(row);
      }
      final divRows = await _transactionStore.queryDividendsByHolding(
        holdingId,
      );
      _dividendsByHolding[holdingId] =
          divRows.map(TransactionModel.fromMap).toList();
      _errorMessage = null;
    } catch (e) {
      _errorMessage = e.toString();
    } finally {
      _loadingHoldingId = null;
      _safeNotify();
    }
  }

  Future<void> refresh() async {
    _isSyncing = true;
    _safeNotify();
    try {
      await _orchestrator.runCycle();
      await loadPortfolio();
    } catch (e) {
      _errorMessage = e.toString();
    } finally {
      _isSyncing = false;
      _safeNotify();
    }
  }

  Future<void> saveHolding(InvestmentHoldingModel model) async {
    await _holdingRepo.upsert(model);
    await loadPortfolio();
    unawaited(_syncInBackground());
  }

  Future<void> archiveHolding(InvestmentHoldingModel holding) async {
    await _holdingRepo.archive(holding.id);
    _lotsByHolding.remove(holding.id);
    _dividendsByHolding.remove(holding.id);
    await loadPortfolio();
    unawaited(_orchestratorInBackground());
  }

  Future<void> saveLot(InvestmentLotModel model) async {
    await _lotRepo.upsert(model);
    await loadHoldingFull(model.holdingId);
    unawaited(_orchestratorInBackground());
  }

  Future<void> deleteLot(InvestmentLotModel model) async {
    await _lotRepo.delete(model.id);
    await loadHoldingFull(model.holdingId);
    unawaited(_orchestratorInBackground());
  }

  Future<String?> lastUsedAccountId() => _lotRepo.getLastUsedAccountId();

  Future<void> _syncInBackground() async {
    try {
      await _syncService.sync();
    } catch (_) {}
  }

  Future<void> _orchestratorInBackground() async {
    try {
      await _orchestrator.runCycle();
    } catch (e) {
      _errorMessage = e.toString();
      _safeNotify();
    }
  }
}
