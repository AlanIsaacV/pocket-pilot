// ============================================================
// ViewModel: Deudas
// ============================================================
//
// Local-first load + throttle 5s sync + CRUD via DebtRepository.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:pocket_pilot/src/core/sync/sync_service.dart';
import 'package:pocket_pilot/src/features/debts/data/debt_repository.dart';
import 'package:pocket_pilot/src/features/debts/domain/contact_balance.dart';
import 'package:pocket_pilot/src/features/transactions/domain/transaction.dart';

class DebtViewModel extends ChangeNotifier {
  final DebtRepository _repository;
  final SyncService _syncService;

  List<ContactBalance> contacts = [];
  bool isLoading = false;
  bool isSyncing = false;
  String? errorMessage;

  DateTime? _lastSyncAt;

  DebtViewModel({
    required DebtRepository repository,
    required SyncService syncService,
  }) : _repository = repository,
       _syncService = syncService;

  /// Contactos con saldo activo (positivo o negativo).
  List<ContactBalance> get activeContacts =>
      contacts.where((c) => c.hasActiveDebt && !c.isDeleted).toList();

  /// Contactos activos sin deuda (saldo 0 en todas sus monedas).
  List<ContactBalance> get settledContacts =>
      contacts.where((c) => !c.hasActiveDebt && !c.isDeleted).toList();

  /// Contactos eliminados (deuda perdonada).
  List<ContactBalance> get forgivenContacts =>
      contacts.where((c) => c.isDeleted).toList();

  ContactBalance? getContactByAccountId(String accountId) {
    for (final contact in contacts) {
      if (contact.accountId == accountId) {
        return contact;
      }
    }
    return null;
  }

  void loadOnAppear() {
    unawaited(_loadLocalThenMaybeSync());
  }

  Future<void> refresh() => _runSync();

  Future<void> forgiveDebt(String accountId) async {
    await _repository.forgiveDebt(accountId);
    await _reloadLocal();
  }

  Future<List<TransactionModel>> getContactTransactions(String accountId) =>
      _repository.getContactTransactions(accountId);

  Future<void> _reloadLocal() async {
    contacts = await _repository.getContactsBalances();
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
    isLoading = contacts.isEmpty;
    isSyncing = true;
    notifyListeners();

    try {
      await _syncService.sync();
      contacts = await _repository.getContactsBalances();
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
