// ============================================================
// ViewModel: Categorías
// ============================================================
//
// Mismo patrón que AccountsViewModel: local-first + throttle 5s + refresh().
// Ver accounts_view_model.dart para la explicación del flujo.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:pocket_pilot/src/core/constants/constants.dart';
import 'package:pocket_pilot/src/features/categories/data/category_repository.dart';
import 'package:pocket_pilot/src/features/categories/domain/category.dart';

class CategoriesViewModel extends ChangeNotifier {
  final CategoryRepository _repository;

  List<CategoryModel> categories = [];
  bool isLoading = false;
  bool isSyncing = false;
  String? errorMessage;

  DateTime? _lastRemoteSyncAt;

  CategoriesViewModel({required CategoryRepository repository})
      : _repository = repository;

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

  Future<void> refresh() => _syncRemote();

  // ----------------------------------------------------------
  // Implementación interna
  // ----------------------------------------------------------

  Future<void> _loadLocalThenMaybeSync() async {
    categories = await _repository.getCategories(kHardcodedUserId);
    notifyListeners();
    await _maybeSyncRemote();
  }

  Future<void> _maybeSyncRemote() async {
    final last = _lastRemoteSyncAt;
    if (last != null &&
        DateTime.now().difference(last) < const Duration(seconds: 5)) {
      return;
    }
    await _syncRemote();
  }

  Future<void> _syncRemote() async {
    isLoading = categories.isEmpty;
    isSyncing = true;
    notifyListeners();

    try {
      await _repository.syncRemote(kHardcodedUserId);
      categories = await _repository.getCategories(kHardcodedUserId);
      _lastRemoteSyncAt = DateTime.now();
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
