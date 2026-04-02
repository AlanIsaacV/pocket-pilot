// ============================================================
// ViewModel: Budgets
// ============================================================
//
// Local-first load + throttle 5s sync + CRUD via repository.
// Expone BudgetStatus (con gasto calculado dinámicamente).

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:pocket_pilot/src/core/sync/sync_service.dart';
import 'package:pocket_pilot/src/features/budgets/data/budget_repository.dart';
import 'package:pocket_pilot/src/features/budgets/domain/budget.dart';
import 'package:pocket_pilot/src/features/budgets/domain/budget_status.dart';

class BudgetViewModel extends ChangeNotifier {
  final BudgetRepository _repository;
  final SyncService _syncService;

  List<BudgetStatus> budgetStatuses = [];
  bool isLoading = false;
  bool isSyncing = false;
  String? errorMessage;

  DateTime? _lastSyncAt;

  BudgetViewModel({
    required BudgetRepository repository,
    required SyncService syncService,
  }) : _repository = repository,
       _syncService = syncService;

  void loadOnAppear() {
    unawaited(_loadLocalThenMaybeSync());
  }

  Future<void> refresh() => _runSync();

  Future<void> upsertBudget(BudgetModel budget) async {
    await _repository.upsertBudget(budget);
    await _reloadLocal();
  }

  Future<void> deleteBudget(String id) async {
    await _repository.deleteBudget(id);
    await _reloadLocal();
  }

  Future<void> _reloadLocal() async {
    budgetStatuses = await _repository.getBudgetStatuses();
    notifyListeners();
  }

  Future<void> _loadLocalThenMaybeSync() async {
    await _reloadLocal();
    await _maybeSyncRemote();
  }

  Future<void> _maybeSyncRemote() async {
    final last = _lastSyncAt;
    if (last != null &&
        DateTime.now().difference(last) < const Duration(seconds: 5)) {
      return;
    }
    await _runSync();
  }

  Future<void> _runSync() async {
    isLoading = budgetStatuses.isEmpty;
    isSyncing = true;
    notifyListeners();

    try {
      await _syncService.sync();
      budgetStatuses = await _repository.getBudgetStatuses();
      _lastSyncAt = DateTime.now();
      errorMessage = null;
    } catch (e) {
      errorMessage = e.toString();
    } finally {
      isLoading = false;
      isSyncing = false;
      notifyListeners();
    }
  }
}
