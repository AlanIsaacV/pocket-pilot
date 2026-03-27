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

class TransactionsViewModel extends ChangeNotifier {
  final TransactionRepository _repository;
  final SyncService _syncService;

  List<TransactionModel> transactions = [];
  bool isLoading = false;
  bool isSyncing = false;
  String? errorMessage;

  DateTime? _lastSyncAt;

  TransactionsViewModel({
    required TransactionRepository repository,
    required SyncService syncService,
  })  : _repository = repository,
        _syncService = syncService;

  // ----------------------------------------------------------
  // API pública
  // ----------------------------------------------------------

  void loadOnAppear() {
    unawaited(_loadLocalThenMaybeSync());
  }

  Future<void> refresh() => _runSync();

  Future<void> deleteTransaction(String id, {String? linkedTransactionId}) async {
    await _repository.deleteTransaction(id, linkedTransactionId: linkedTransactionId);
    await _loadLocalThenMaybeSync();
  }

  TransactionModel? findLinked(String linkedId) {
    try {
      return transactions.firstWhere((t) => t.id == linkedId);
    } catch (_) {
      return null;
    }
  }

  // ----------------------------------------------------------
  // Implementación interna
  // ----------------------------------------------------------

  Future<void> _loadLocalThenMaybeSync() async {
    transactions = await _repository.getTransactions();
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
    isLoading = transactions.isEmpty;
    isSyncing = true;
    notifyListeners();

    try {
      await _syncService.sync();
      transactions = await _repository.getTransactions();
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
