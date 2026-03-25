// ============================================================
// ViewModel: Categorías
// ============================================================
//
// CRUD completo + navegación jerárquica (drill-down) + multi-select.
// Patrón local-first + throttle 5s + refresh().

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:pocket_pilot/src/core/sync/sync_service.dart';
import 'package:pocket_pilot/src/features/categories/data/category_repository.dart';
import 'package:pocket_pilot/src/features/categories/domain/category.dart';
import 'package:uuid/uuid.dart';

class CategoriesViewModel extends ChangeNotifier {
  static const _uuid = Uuid();

  final CategoryRepository _repository;
  final SyncService _syncService;

  // ----------------------------------------------------------
  // Estado
  // ----------------------------------------------------------

  List<CategoryModel> categories = [];
  List<CategoryModel> deletedCategories = [];
  bool isLoading = false;
  bool isSyncing = false;
  String? errorMessage;

  DateTime? _lastSyncAt;

  /// Navegación jerárquica: null = raíz.
  String? currentParentId;

  /// Breadcrumb para la navegación drill-down.
  final List<({String id, String name})> breadcrumb = [];

  /// IDs seleccionados para multi-select (ocultar en batch).
  final Set<String> selectedIds = {};

  CategoriesViewModel({
    required CategoryRepository repository,
    required SyncService syncService,
  })  : _repository = repository,
        _syncService = syncService;

  // ----------------------------------------------------------
  // Getters computados
  // ----------------------------------------------------------

  bool get isMultiSelectMode => selectedIds.isNotEmpty;

  bool get isAtRoot => currentParentId == null;

  List<CategoryModel> get currentIncomeCategories => categories
      .where((c) => c.parentId == currentParentId && c.isIncome)
      .toList();

  List<CategoryModel> get currentExpenseCategories => categories
      .where((c) => c.parentId == currentParentId && c.isExpense)
      .toList();

  List<CategoryModel> get currentDeletedCategories => deletedCategories
      .where((c) => c.parentId == currentParentId)
      .toList();

  /// Número de hijos activos de una categoría.
  int childCount(String id) =>
      categories.where((c) => c.parentId == id).length;

  /// Modelo de la categoría padre actual (para pasar al formulario).
  CategoryModel? get currentParentModel {
    if (currentParentId == null) return null;
    try {
      return categories.firstWhere((c) => c.id == currentParentId);
    } catch (_) {
      return null;
    }
  }

  // ----------------------------------------------------------
  // Navegación drill-down
  // ----------------------------------------------------------

  void navigateToChildren(CategoryModel cat) {
    breadcrumb.add((id: cat.id, name: cat.name));
    currentParentId = cat.id;
    selectedIds.clear();
    notifyListeners();
  }

  void navigateBack() {
    if (breadcrumb.isEmpty) return;
    breadcrumb.removeLast();
    currentParentId = breadcrumb.isEmpty ? null : breadcrumb.last.id;
    selectedIds.clear();
    notifyListeners();
  }

  void navigateToRoot() {
    breadcrumb.clear();
    currentParentId = null;
    selectedIds.clear();
    notifyListeners();
  }

  // ----------------------------------------------------------
  // Multi-select
  // ----------------------------------------------------------

  void toggleSelection(String id) {
    if (selectedIds.contains(id)) {
      selectedIds.remove(id);
    } else {
      selectedIds.add(id);
    }
    notifyListeners();
  }

  void clearSelection() {
    selectedIds.clear();
    notifyListeners();
  }

  // ----------------------------------------------------------
  // CRUD
  // ----------------------------------------------------------

  Future<void> createCategory({
    required String name,
    required String type,
    String? icon,
    String? color,
    String? parentId,
  }) async {
    final id = _uuid.v4();
    await _repository.createCategory(
      id: id,
      name: name,
      type: type,
      icon: icon,
      color: color,
      parentId: parentId,
    );
    await _reloadLocal();
  }

  Future<void> updateCategory({
    required CategoryModel current,
    required String name,
    required String type,
    String? icon,
    String? color,
  }) async {
    await _repository.updateCategory(
      current: current,
      name: name,
      type: type,
      icon: icon,
      color: color,
    );
    await _reloadLocal();
  }

  Future<void> hideCategory(String id) async {
    await _repository.deleteCategory(id);
    await _reloadLocal();
  }

  Future<void> hideSelected() async {
    if (selectedIds.isEmpty) return;
    await _repository.deleteCategories(selectedIds.toList());
    selectedIds.clear();
    await _reloadLocal();
  }

  Future<void> restoreCategory(String id) async {
    await _repository.restoreCategory(id);
    await _reloadLocal();
  }

  // ----------------------------------------------------------
  // API pública — carga & sync
  // ----------------------------------------------------------

  void loadOnAppear() {
    unawaited(_loadLocalThenMaybeSync());
  }

  Future<void> refresh() => _runSync();

  // ----------------------------------------------------------
  // Implementación interna
  // ----------------------------------------------------------

  Future<void> _reloadLocal() async {
    categories = await _repository.getCategories();
    deletedCategories = await _repository.getDeletedCategories();
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
    isLoading = categories.isEmpty && deletedCategories.isEmpty;
    isSyncing = true;
    notifyListeners();

    try {
      await _syncService.sync();
      categories = await _repository.getCategories();
      deletedCategories = await _repository.getDeletedCategories();
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
