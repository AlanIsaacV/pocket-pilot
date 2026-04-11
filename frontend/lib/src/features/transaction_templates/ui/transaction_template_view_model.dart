// ============================================================
// ViewModel: Transaction Templates
// ============================================================
//
// Local-first load + throttle 5s sync + CRUD via repository.
// Patrón: loadOnAppear(), refresh(), deleteTemplate(id).

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:pocket_pilot/src/core/sync/sync_service.dart';
import 'package:pocket_pilot/src/features/transaction_templates/data/transaction_template_repository.dart';
import 'package:pocket_pilot/src/features/transaction_templates/domain/transaction_template.dart';

class TransactionTemplateViewModel extends ChangeNotifier {
  final TransactionTemplateRepository _repository;
  final SyncService _syncService;

  // ----------------------------------------------------------
  // Estado
  // ----------------------------------------------------------

  List<TransactionTemplateModel> templates = [];
  bool isLoading = false;
  bool isSyncing = false;
  String? errorMessage;

  DateTime? _lastSyncAt;
  bool _disposed = false;

  TransactionTemplateViewModel({
    required TransactionTemplateRepository repository,
    required SyncService syncService,
  })  : _repository = repository,
        _syncService = syncService;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  // ----------------------------------------------------------
  // API pública — carga & sync
  // ----------------------------------------------------------

  void loadOnAppear() {
    unawaited(_loadLocalThenMaybeSync());
  }

  Future<void> refresh() => _runSync();

  Future<void> deleteTemplate(String id) async {
    await _repository.deleteTemplate(id);
    await _reloadLocal();
  }

  // ----------------------------------------------------------
  // Implementación interna
  // ----------------------------------------------------------

  Future<void> _reloadLocal() async {
    templates = await _repository.getTemplates();
    _safeNotify();
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
    isLoading = templates.isEmpty;
    isSyncing = true;
    _safeNotify();

    try {
      await _syncService.sync();
      templates = await _repository.getTemplates();
      _lastSyncAt = DateTime.now();
      errorMessage = null;
    } catch (e) {
      errorMessage = e.toString();
    } finally {
      isLoading = false;
      isSyncing = false;
      _safeNotify();
    }
  }
}
