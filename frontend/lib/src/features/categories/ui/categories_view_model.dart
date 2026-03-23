// ============================================================
// ViewModel: Categorías
// ============================================================
//
// Mismo patrón que AccountsViewModel: local-first + throttle 5s + refresh().
// Ver accounts_view_model.dart para la explicación del flujo.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:pocket_pilot/src/core/sync/sync_service.dart';
import 'package:pocket_pilot/src/features/categories/data/category_repository.dart';
import 'package:pocket_pilot/src/features/categories/domain/category.dart';

class CategoriesViewModel extends ChangeNotifier {
  final CategoryRepository _repository;
  final SyncService _syncService;

  List<CategoryModel> categories = [];
  bool isLoading = false;
  bool isSyncing = false;
  String? errorMessage;

  DateTime? _lastSyncAt;

  CategoriesViewModel({
    required CategoryRepository repository,
    required SyncService syncService,
  })  : _repository = repository,
        _syncService = syncService;

  // ----------------------------------------------------------
  // Getters computados para la UI
  // ----------------------------------------------------------

  List<CategoryModel> get incomeCategories =>
      categories.where((c) => c.isIncome).toList();

  List<CategoryModel> get expenseCategories =>
      categories.where((c) => c.isExpense).toList();

  // ----------------------------------------------------------
  // API pública
  // ----------------------------------------------------------

  void loadOnAppear() {
    unawaited(_loadLocalThenMaybeSync());
  }

  Future<void> refresh() => _runSync();

  // ----------------------------------------------------------
  // Implementación interna
  // ----------------------------------------------------------

  Future<void> _loadLocalThenMaybeSync() async {
    categories = await _repository.getCategories();
    notifyListeners();
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
    isLoading = categories.isEmpty;
    isSyncing = true;
    notifyListeners();

    try {
      await _syncService.sync();
      categories = await _repository.getCategories();
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
