// ============================================================
// ViewModel: Goals
// ============================================================
//
// Local-first load + throttle 5s sync + CRUD via repository.
// Patrón: loadOnAppear(), refresh(), upsertGoal(goal), deleteGoal(id).

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:pocket_pilot/src/core/sync/sync_service.dart';
import 'package:pocket_pilot/src/features/goals/data/goal_repository.dart';
import 'package:pocket_pilot/src/features/goals/domain/goal.dart';

class GoalViewModel extends ChangeNotifier {
  final GoalRepository _repository;
  final SyncService _syncService;

  // ----------------------------------------------------------
  // Estado
  // ----------------------------------------------------------

  List<GoalModel> goals = [];
  Map<String, int> liquidByCurrency = {};
  bool isLoading = false;
  bool isSyncing = false;
  String? errorMessage;

  Map<String, int> _liquidityByGoalId = const {};
  DateTime? _lastSyncAt;

  GoalViewModel({
    required GoalRepository repository,
    required SyncService syncService,
  }) : _repository = repository,
       _syncService = syncService;

  // ----------------------------------------------------------
  // Getters computados
  // ----------------------------------------------------------

  int get totalMonthlyRequiredCents => GoalMath.totalMonthlyRequiredCents(
    goals,
    liquidByCurrency: liquidByCurrency,
  );

  int liquidityForGoal(String goalId) => _liquidityByGoalId[goalId] ?? 0;

  List<GoalModel> get overdueGoals {
    return goals.where((goal) {
      return goal.isOverdueAt(
        DateTime.now(),
        liquidityAssignedCents: liquidityForGoal(goal.id),
      );
    }).toList();
  }

  // ----------------------------------------------------------
  // API pública — carga & sync
  // ----------------------------------------------------------

  void loadOnAppear() {
    unawaited(_loadLocalThenMaybeSync());
  }

  Future<void> refresh() => _runSync();

  Future<void> upsertGoal(GoalModel goal) async {
    await _repository.upsertGoal(goal);
    await _reloadLocal();
  }

  Future<void> deleteGoal(String id) async {
    await _repository.deleteGoal(id);
    await _reloadLocal();
  }

  // ----------------------------------------------------------
  // Implementación interna
  // ----------------------------------------------------------

  Future<void> _reloadLocal() async {
    final results = await Future.wait([
      _repository.getGoals(),
      _repository.getLiquidByCurrency(),
    ]);
    goals = results[0] as List<GoalModel>;
    liquidByCurrency = results[1] as Map<String, int>;
    _liquidityByGoalId = GoalMath.allocateLiquidity(goals, liquidByCurrency);
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
    isLoading = goals.isEmpty;
    isSyncing = true;
    notifyListeners();

    try {
      await _syncService.sync();
      await _reloadLocal();
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
