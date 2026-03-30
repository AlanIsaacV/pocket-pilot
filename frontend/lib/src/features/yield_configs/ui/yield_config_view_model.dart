// ============================================================
// ViewModel: Yield Configs
// ============================================================
//
// Local-first load + throttle 5s sync + CRUD via repository.
// Patrón: loadOnAppear(), refresh(), deleteConfig(id).

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:pocket_pilot/src/core/sync/sync_service.dart';
import 'package:pocket_pilot/src/features/yield_configs/data/yield_config_repository.dart';
import 'package:pocket_pilot/src/features/yield_configs/domain/yield_config.dart';

class YieldConfigViewModel extends ChangeNotifier {
  final YieldConfigRepository _repository;
  final SyncService _syncService;

  // ----------------------------------------------------------
  // Estado
  // ----------------------------------------------------------

  List<YieldConfigModel> configs = [];
  bool isLoading = false;
  bool isSyncing = false;
  String? errorMessage;

  DateTime? _lastSyncAt;

  YieldConfigViewModel({
    required YieldConfigRepository repository,
    required SyncService syncService,
  })  : _repository = repository,
        _syncService = syncService;

  // ----------------------------------------------------------
  // API pública — carga & sync
  // ----------------------------------------------------------

  void loadOnAppear() {
    unawaited(_loadLocalThenMaybeSync());
  }

  Future<void> refresh() => _runSync();

  Future<void> deleteConfig(String id) async {
    await _repository.deleteConfig(id);
    await _reloadLocal();
  }

  // ----------------------------------------------------------
  // Implementación interna
  // ----------------------------------------------------------

  Future<void> _reloadLocal() async {
    configs = await _repository.getConfigs();
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
    isLoading = configs.isEmpty;
    isSyncing = true;
    notifyListeners();

    try {
      await _syncService.sync();
      configs = await _repository.getConfigs();
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
