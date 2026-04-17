// ============================================================
// ViewModel: Transacciones
// ============================================================
//
// Mismo patrón que AccountsViewModel: local-first + throttle 5s + refresh().
// Ver accounts_view_model.dart para la explicación del flujo.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:pocket_pilot/src/core/sync/sync_service.dart';
import 'package:pocket_pilot/src/features/transactions/data/transaction_repository.dart';
import 'package:pocket_pilot/src/features/transactions/domain/transaction.dart';
import 'package:pocket_pilot/src/features/transactions/ui/transaction_filter_view_model.dart';

class TransactionsViewModel extends ChangeNotifier {
  final TransactionRepository _repository;
  final SyncService _syncService;
  final TransactionFilterViewModel _filterViewModel;

  List<TransactionModel> transactions = [];
  bool isLoading = false;
  bool isSyncing = false;
  String? errorMessage;

  DateTime? _lastSyncAt;
  bool _disposed = false;

  TransactionsViewModel({
    required TransactionRepository repository,
    required SyncService syncService,
    required TransactionFilterViewModel filterViewModel,
  }) : _repository = repository,
       _syncService = syncService,
       _filterViewModel = filterViewModel {
    _filterViewModel.addListener(_onFilterChanged);
  }

  void _onFilterChanged() {
    _loadLocal();
  }

  @override
  void dispose() {
    _disposed = true;
    _filterViewModel.removeListener(_onFilterChanged);
    super.dispose();
  }

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  // ----------------------------------------------------------
  // API pública
  // ----------------------------------------------------------

  void loadOnAppear() {
    unawaited(_loadLocalThenMaybeSync());
  }

  Future<void> refresh() => _runSync();

  Future<void> deleteTransaction(
    String id, {
    String? linkedTransactionId,
  }) async {
    await _repository.deleteTransaction(
      id,
      linkedTransactionId: linkedTransactionId,
    );
    await _loadLocalThenMaybeSync();
  }

  /// Confirma una transacción pending. Si tiene linked (transferencia),
  /// confirma ambas piernas para mantener consistencia.
  Future<void> confirmTransaction(
    String id, {
    String? linkedTransactionId,
  }) async {
    await _repository.confirmTransaction(id);
    if (linkedTransactionId != null) {
      await _repository.confirmTransaction(linkedTransactionId);
    }
    await _loadLocal();
  }

  Future<bool> isInitialBalanceTransaction({
    required TransactionModel transaction,
    required String accountType,
  }) async {
    if (transaction.isTransfer) return false;
    if (transaction.categoryId != null) return false;
    if (transaction.linkedTransactionId != null) return false;
    if (transaction.nature == 'adjustment') return false;

    final expectedType = _initialBalanceTypeForAccount(accountType);
    if (transaction.type != expectedType) return false;

    final initial = await _repository.getInitialBalanceTransaction(
      accountId: transaction.accountId,
      type: expectedType,
    );
    return initial?.id == transaction.id;
  }

  TransactionModel? findLinked(String linkedId) {
    try {
      return transactions.firstWhere((t) => t.id == linkedId);
    } catch (_) {
      return null;
    }
  }

  /// Busca la transacción por id directamente en DB (sin filtros del listado).
  Future<TransactionModel?> getTransactionById(String id) =>
      _repository.getTransactionById(id);

  // ----------------------------------------------------------
  // Implementación interna
  // ----------------------------------------------------------

  Future<void> _loadLocal() async {
    transactions = await _repository.getTransactions(
      filter: _filterViewModel.resolvedFilter,
    );
    _safeNotify();
  }

  Future<void> _loadLocalThenMaybeSync() async {
    await _loadLocal();
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
    isLoading = transactions.isEmpty;
    isSyncing = true;
    _safeNotify();

    try {
      await _syncService.sync();
      transactions = await _repository.getTransactions(
        filter: _filterViewModel.resolvedFilter,
      );
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

  String _initialBalanceTypeForAccount(String accountType) {
    switch (accountType) {
      case 'credit_card':
      case 'loan':
        return 'expense';
      default:
        return 'income';
    }
  }
}
