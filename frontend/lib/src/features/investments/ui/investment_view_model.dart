import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:pocket_pilot/src/core/sync/scheduled_generation_orchestrator.dart';
import 'package:pocket_pilot/src/core/sync/sync_service.dart';
import 'package:pocket_pilot/src/features/investments/data/investment_holding_repository.dart';
import 'package:pocket_pilot/src/features/investments/data/investment_lot_repository.dart';
import 'package:pocket_pilot/src/features/investments/domain/investment_holding.dart';
import 'package:pocket_pilot/src/features/investments/domain/investment_lot.dart';

class InvestmentViewModel extends ChangeNotifier {
  final InvestmentHoldingRepository _holdingRepo;
  final InvestmentLotRepository _lotRepo;
  final SyncService _syncService;
  final ScheduledGenerationOrchestrator _orchestrator;

  List<InvestmentHoldingModel> _allHoldings = const [];
  final Map<String, List<InvestmentLotModel>> _lotsByHolding = {};

  bool _isLoadingAll = false;
  String? _loadingHoldingId;
  bool _isSyncing = false;
  String? _errorMessage;
  bool _disposed = false;

  InvestmentViewModel({
    required InvestmentHoldingRepository holdingRepo,
    required InvestmentLotRepository lotRepo,
    required SyncService syncService,
    required ScheduledGenerationOrchestrator orchestrator,
  }) : _holdingRepo = holdingRepo,
       _lotRepo = lotRepo,
       _syncService = syncService,
       _orchestrator = orchestrator;

  List<InvestmentHoldingModel> get allHoldings => _allHoldings;

  List<InvestmentLotModel> lotsFor(String holdingId) =>
      _lotsByHolding[holdingId] ?? const [];

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
    unawaited(loadAll());
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

  Future<void> refresh() async {
    _isSyncing = true;
    _safeNotify();
    try {
      await _orchestrator.runCycle();
      await loadAll();
    } catch (e) {
      _errorMessage = e.toString();
    } finally {
      _isSyncing = false;
      _safeNotify();
    }
  }

  Future<void> saveHolding(InvestmentHoldingModel model) async {
    await _holdingRepo.upsert(model);
    await loadAll();
    unawaited(_syncInBackground());
  }

  Future<void> archiveHolding(InvestmentHoldingModel holding) async {
    await _holdingRepo.archive(holding.id);
    _lotsByHolding.remove(holding.id);
    await loadAll();
    unawaited(_orchestratorInBackground());
  }

  Future<void> saveLot(InvestmentLotModel model) async {
    await _lotRepo.upsert(model);
    await loadHolding(model.holdingId);
    unawaited(_orchestratorInBackground());
  }

  Future<void> deleteLot(InvestmentLotModel model) async {
    await _lotRepo.delete(model.id);
    await loadHolding(model.holdingId);
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
