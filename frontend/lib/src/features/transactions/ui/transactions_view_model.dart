// ============================================================
// ViewModel: Transacciones
// ============================================================
//
// Mismo patrón que AccountsViewModel: local-first + throttle 5s + refresh().
// Ver accounts_view_model.dart para la explicación del flujo.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:pocket_pilot/src/core/constants/constants.dart';
import 'package:pocket_pilot/src/features/transactions/data/transaction_repository.dart';
import 'package:pocket_pilot/src/features/transactions/domain/transaction.dart';

class TransactionsViewModel extends ChangeNotifier {
  final TransactionRepository _repository;

  List<TransactionModel> transactions = [];
  bool isLoading = false;
  bool isSyncing = false;
  String? errorMessage;

  DateTime? _lastRemoteSyncAt;

  TransactionsViewModel({required TransactionRepository repository})
      : _repository = repository;

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
    transactions = await _repository.getTransactions(kHardcodedUserId);
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
    isLoading = transactions.isEmpty;
    isSyncing = true;
    notifyListeners();

    try {
      await _repository.syncRemote(kHardcodedUserId);
      transactions = await _repository.getTransactions(kHardcodedUserId);
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
