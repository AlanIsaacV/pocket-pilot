// ============================================================
// CsvImportViewModel — estado del flujo de importación CSV
// ============================================================

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import 'package:pocket_pilot/src/features/accounts/data/account_local_store.dart';
import 'package:pocket_pilot/src/features/accounts/domain/account.dart';
import 'package:pocket_pilot/src/features/categories/data/category_local_store.dart';
import 'package:pocket_pilot/src/features/categories/domain/category.dart';
import 'package:pocket_pilot/src/features/csv_import/data/csv_import_repository.dart';
import 'package:pocket_pilot/src/features/csv_import/data/csv_import_service.dart';
import 'package:pocket_pilot/src/features/csv_import/domain/csv_extraction_result.dart';
import 'package:pocket_pilot/src/features/csv_import/domain/csv_duplicate_matcher.dart';
import 'package:pocket_pilot/src/features/csv_import/domain/csv_transaction_row.dart';
import 'package:pocket_pilot/src/features/csv_import/domain/mapping_dictionary.dart';
import 'package:pocket_pilot/src/features/tags/data/tag_local_store.dart';
import 'package:pocket_pilot/src/features/accounts/data/account_repository.dart';
import 'package:pocket_pilot/src/features/categories/data/category_repository.dart';
import 'package:pocket_pilot/src/features/tags/data/tag_repository.dart';
import 'package:pocket_pilot/src/features/tags/domain/tag.dart';

enum CsvImportStatus { idle, parsing, readyToMap, importing, done, error }

/// Returns only the CSV rows selected for insertion by their original index.
List<CsvTransactionRow> rowsIncludedForImport(
  List<CsvTransactionRow> rows,
  Set<int> includedRowIndices,
) => [
  for (var index = 0; index < rows.length; index++)
    if (includedRowIndices.contains(index)) rows[index],
];

/// Reconciles duplicate flags without discarding deliberate row exclusions.
Set<int> reconcileIncludedRowIndices({
  required Set<int> includedRowIndices,
  required Set<int> previousDuplicateRowIndices,
  required Set<int> matchedRowIndices,
  required int rowCount,
  required bool initializeIncludedRows,
}) {
  final included = Set<int>.from(includedRowIndices);
  if (initializeIncludedRows) {
    included.addAll(List.generate(rowCount, (index) => index));
  }
  return included
    ..addAll(previousDuplicateRowIndices.difference(matchedRowIndices))
    ..removeAll(matchedRowIndices.difference(previousDuplicateRowIndices));
}

class CsvImportViewModel extends ChangeNotifier {
  final CsvImportService _service;
  final CsvImportRepository _repository;
  final AccountLocalStore _accountStore;
  final CategoryLocalStore _categoryStore;
  final TagLocalStore _tagStore;
  final TagRepository _tagRepository;
  final AccountRepository _accountRepository;
  final CategoryRepository _categoryRepository;

  CsvImportViewModel({
    required CsvImportService service,
    required CsvImportRepository repository,
    required AccountLocalStore accountStore,
    required CategoryLocalStore categoryStore,
    required TagLocalStore tagStore,
    required TagRepository tagRepository,
    required AccountRepository accountRepository,
    required CategoryRepository categoryRepository,
  }) : _service = service,
       _repository = repository,
       _accountStore = accountStore,
       _categoryStore = categoryStore,
       _tagStore = tagStore,
       _tagRepository = tagRepository,
       _accountRepository = accountRepository,
       _categoryRepository = categoryRepository;

  // ----------------------------------------------------------
  // State
  // ----------------------------------------------------------

  CsvImportStatus _status = CsvImportStatus.idle;
  CsvImportStatus get status => _status;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  CsvExtractionResult? _extractionResult;
  CsvExtractionResult? get extractionResult => _extractionResult;

  final Map<String, String> accountIdMap = {};
  final Map<String, String> categoryIdMap = {};
  final Map<String, String> tagIdMap = {};

  List<AccountModel> _existingAccounts = [];
  List<AccountModel> get existingAccounts => _existingAccounts;

  List<CategoryModel> _existingCategories = [];
  List<CategoryModel> get existingCategories => _existingCategories;

  List<TagModel> _existingTags = [];
  List<TagModel> get existingTags => _existingTags;

  final Set<int> _duplicateRowIndices = {};
  final Set<int> _includedRowIndices = {};
  bool _includedRowsInitialized = false;
  int _lastImportedRowCount = 0;
  int _lastSkippedDuplicateRowCount = 0;

  Set<int> get duplicateRowIndices => Set.unmodifiable(_duplicateRowIndices);
  bool isDuplicateRow(int rowIndex) => _duplicateRowIndices.contains(rowIndex);
  bool isRowIncluded(int rowIndex) => _includedRowIndices.contains(rowIndex);
  int get duplicateRowCount => _duplicateRowIndices.length;
  int get skippedDuplicateRowCount =>
      _duplicateRowIndices.difference(_includedRowIndices).length;
  int get includedRowCount => _includedRowIndices.length;
  int get lastImportedRowCount => _lastImportedRowCount;
  int get lastSkippedDuplicateRowCount => _lastSkippedDuplicateRowCount;

  // ----------------------------------------------------------
  // Summary getters
  // ----------------------------------------------------------

  int get totalRows => _extractionResult?.rows.length ?? 0;

  int get expenseCount =>
      _extractionResult?.rows.where((r) => r.type == 'EXPENSE').length ?? 0;

  int get incomeCount =>
      _extractionResult?.rows.where((r) => r.type == 'INCOME').length ?? 0;

  int get transferCount =>
      _extractionResult?.rows.where((r) => r.type == 'TRANSFER').length ?? 0;

  // ----------------------------------------------------------
  // Mapping status getters
  // ----------------------------------------------------------

  int get unmappedAccountCount {
    final names = _extractionResult?.uniqueAccountNames ?? {};
    return names.where((n) => !accountIdMap.containsKey(n)).length;
  }

  int get unmappedCategoryCount {
    final names = _extractionResult?.uniqueCategoryNames ?? {};
    return names.where((n) => !categoryIdMap.containsKey(n)).length;
  }

  int get unmappedTagCount {
    final names = _extractionResult?.uniqueTagNames ?? {};
    return names.where((n) => !tagIdMap.containsKey(n)).length;
  }

  bool get allMapped => unmappedAccountCount == 0;

  // ----------------------------------------------------------
  // Phase 1: Pick file and parse
  // ----------------------------------------------------------

  Future<void> pickAndParse() async {
    _status = CsvImportStatus.parsing;
    _errorMessage = null;
    notifyListeners();

    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
      );

      if (result == null || result.files.isEmpty) {
        _status = CsvImportStatus.idle;
        notifyListeners();
        return;
      }

      final file = File(result.files.single.path!);
      final content = await file.readAsString();

      final extraction = _service.parseAndExtract(content);

      if (extraction.rows.isEmpty) {
        _status = CsvImportStatus.error;
        _errorMessage = 'El archivo no contiene transacciones.';
        notifyListeners();
        return;
      }

      _extractionResult = extraction;
      _duplicateRowIndices.clear();
      _includedRowIndices.clear();
      _includedRowsInitialized = false;
      _status = CsvImportStatus.readyToMap;
      notifyListeners();
    } on FormatException catch (e) {
      _status = CsvImportStatus.error;
      _errorMessage = e.message;
      notifyListeners();
    } catch (e) {
      _status = CsvImportStatus.error;
      _errorMessage = 'Error al leer el archivo: $e';
      notifyListeners();
    }
  }

  // ----------------------------------------------------------
  // Phase 2: Load entities and auto-match
  // ----------------------------------------------------------

  Future<void> loadExistingEntities() async {
    _existingAccounts = await _accountStore.getAccounts();
    _existingCategories = await _categoryStore.getCategories();
    _existingTags = await _tagStore.getTags();

    _autoMatch();
    await _refreshDuplicateMatches();
    notifyListeners();
  }

  void _autoMatch() {
    final result = _extractionResult;
    if (result == null) return;

    for (final name in result.uniqueAccountNames) {
      if (accountIdMap.containsKey(name)) continue;
      final match = _findByName(_existingAccounts, name, (a) => a.name);
      if (match != null) accountIdMap[name] = match.id;
    }

    for (final name in result.uniqueCategoryNames) {
      if (categoryIdMap.containsKey(name)) continue;
      final match = _findByName(_existingCategories, name, (c) => c.name);
      if (match != null) categoryIdMap[name] = match.id;
    }

    for (final name in result.uniqueTagNames) {
      if (tagIdMap.containsKey(name)) continue;
      final match = _findByName(_existingTags, name, (t) => t.name);
      if (match != null) tagIdMap[name] = match.id;
    }
  }

  T? _findByName<T>(List<T> items, String name, String Function(T) getName) {
    final lower = name.toLowerCase();
    for (final item in items) {
      if (getName(item).toLowerCase() == lower) return item;
    }
    return null;
  }

  // ----------------------------------------------------------
  // Mapping updates
  // ----------------------------------------------------------

  Future<void> updateAccountMapping(String csvName, String accountId) async {
    accountIdMap[csvName] = accountId;
    await _refreshDuplicateMatches();
    notifyListeners();
  }

  /// Phase 5.3 UI will expose this for the per-row include toggle.
  void setRowIncluded(int rowIndex, bool included) {
    if (included) {
      _includedRowIndices.add(rowIndex);
    } else {
      _includedRowIndices.remove(rowIndex);
    }
    notifyListeners();
  }

  void includeAllDuplicateRows() {
    _includedRowIndices.addAll(_duplicateRowIndices);
    notifyListeners();
  }

  void updateCategoryMapping(String csvName, String categoryId) {
    categoryIdMap[csvName] = categoryId;
    notifyListeners();
  }

  void updateTagMapping(String csvName, String tagId) {
    tagIdMap[csvName] = tagId;
    notifyListeners();
  }

  Future<void> refreshAccounts() async {
    _existingAccounts = await _accountStore.getAccounts();
    _autoMatch();
    await _refreshDuplicateMatches();
    notifyListeners();
  }

  Future<void> _refreshDuplicateMatches() async {
    final rows = _extractionResult?.rows;
    if (rows == null) return;

    final candidates = <CsvDuplicateCandidate>[];
    for (var index = 0; index < rows.length; index++) {
      final accountId = accountIdMap[rows[index].accountName];
      if (accountId != null) {
        candidates.add(
          CsvDuplicateCandidate(
            rowIndex: index,
            row: rows[index],
            accountId: accountId,
          ),
        );
      }
    }

    final transactions = await _repository.getTransactionsForAccounts(
      candidates.map((candidate) => candidate.accountId).toSet(),
    );
    final matches = findCsvDuplicateMatches(
      csvRows: candidates,
      existingTransactions: transactions,
    );

    final previousDuplicates = Set<int>.from(_duplicateRowIndices);
    final matchedRowIndices = matches.map((match) => match.rowIndex).toSet();
    // New duplicate flags default to skip; an explicit include choice for an
    // already flagged row survives later refreshes.
    final reconciledIncludedRows = reconcileIncludedRowIndices(
      includedRowIndices: _includedRowIndices,
      previousDuplicateRowIndices: previousDuplicates,
      matchedRowIndices: matchedRowIndices,
      rowCount: rows.length,
      initializeIncludedRows: !_includedRowsInitialized,
    );
    _includedRowIndices
      ..clear()
      ..addAll(reconciledIncludedRows);
    _includedRowsInitialized = true;
    _duplicateRowIndices
      ..clear()
      ..addAll(matchedRowIndices);
  }

  Future<void> refreshCategories() async {
    _existingCategories = await _categoryStore.getCategories();
    _autoMatch();
    notifyListeners();
  }

  // ----------------------------------------------------------
  // Quick-create shortcuts
  // ----------------------------------------------------------

  String _inferCurrencyForAccount(String csvName) {
    final rows = _extractionResult?.rows ?? [];
    final matching = rows.where(
      (r) => r.accountName == csvName || r.destinationAccountName == csvName,
    );
    if (matching.isEmpty) return 'MXN';
    final counts = <String, int>{};
    for (final r in matching) {
      counts[r.currencyCode] = (counts[r.currencyCode] ?? 0) + 1;
    }
    return counts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
  }

  Future<void> quickCreateAccountAndMap(String csvName) async {
    final currencyCode = _inferCurrencyForAccount(csvName);
    final id = const Uuid().v4();
    await _accountRepository.createAccount(
      id: id,
      name: csvName,
      type: 'bank',
      currencyCode: currencyCode,
    );
    accountIdMap[csvName] = id;
    await refreshAccounts();
  }

  String _inferCategoryType(String csvName) {
    final rows = _extractionResult?.rows ?? [];
    final matching = rows.where((r) => r.categoryName == csvName);
    if (matching.isEmpty) return 'expense';
    final hasIncome = matching.any((r) => r.type.toUpperCase() == 'INCOME');
    final hasExpense = matching.any((r) => r.type.toUpperCase() == 'EXPENSE');
    if (hasIncome && !hasExpense) return 'income';
    return 'expense';
  }

  Future<void> quickCreateCategoryAndMap(String csvName) async {
    final type = _inferCategoryType(csvName);
    final id = const Uuid().v4();
    await _categoryRepository.createCategory(
      id: id,
      name: csvName,
      type: type,
      color: '#9E9E9E',
      icon: 'label',
      defaultNature: '',
    );
    categoryIdMap[csvName] = id;
    await refreshCategories();
  }

  // ----------------------------------------------------------
  // Category tree
  // ----------------------------------------------------------

  List<CategoryNode> get categoryTree =>
      _buildCategoryTree(_existingCategories);

  List<CategoryNode> _buildCategoryTree(List<CategoryModel> categories) {
    final byParent = <String?, List<CategoryModel>>{};
    for (final cat in categories) {
      byParent.putIfAbsent(cat.parentId, () => []).add(cat);
    }

    List<CategoryNode> buildChildren(String? parentId, int depth) {
      return (byParent[parentId] ?? [])
          .map(
            (cat) => CategoryNode(
              category: cat,
              children: buildChildren(cat.id, depth + 1),
              depth: depth,
            ),
          )
          .toList();
    }

    return buildChildren(null, 0);
  }

  // ----------------------------------------------------------
  // Phase 3: Import
  // ----------------------------------------------------------

  Future<void> importBatch() async {
    _status = CsvImportStatus.importing;
    _errorMessage = null;
    notifyListeners();

    try {
      await _refreshDuplicateMatches();
      // Auto-create entities that didn't get manually mapped.
      final result = _extractionResult;
      if (result != null) {
        for (final tagName in result.uniqueTagNames) {
          if (!tagIdMap.containsKey(tagName)) {
            final id = const Uuid().v4();
            await _tagRepository.createTag(id: id, name: tagName);
            tagIdMap[tagName] = id;
          }
        }
        for (final catName in result.uniqueCategoryNames) {
          if (!categoryIdMap.containsKey(catName)) {
            final type = _inferCategoryType(catName);
            final id = const Uuid().v4();
            await _categoryRepository.createCategory(
              id: id,
              name: catName,
              type: type,
              color: '#9E9E9E',
              icon: 'label',
              defaultNature: '',
            );
            categoryIdMap[catName] = id;
          }
        }
      }

      final mapping = MappingDictionary(
        accountIdMap: Map.unmodifiable(accountIdMap),
        categoryIdMap: Map.unmodifiable(categoryIdMap),
        tagIdMap: Map.unmodifiable(tagIdMap),
      );

      final includedRows = rowsIncludedForImport(
        _extractionResult!.rows,
        _includedRowIndices,
      );
      _lastImportedRowCount = includedRows.length;
      _lastSkippedDuplicateRowCount = skippedDuplicateRowCount;
      final batch = _service.buildInsertBatch(includedRows, mapping);

      await _repository.importTransactions(batch);

      _status = CsvImportStatus.done;
      notifyListeners();
    } catch (e) {
      _status = CsvImportStatus.error;
      _errorMessage = 'Error al importar: $e';
      notifyListeners();
    }
  }
}

class CategoryNode {
  final CategoryModel category;
  final List<CategoryNode> children;
  final int depth;

  const CategoryNode({
    required this.category,
    required this.children,
    required this.depth,
  });

  bool get hasChildren => children.isNotEmpty;
}
