// ============================================================
// ViewModel: Cuentas
// ============================================================
//
// Flujo al entrar a la pantalla (loadOnAppear):
//   1. Lee SQLite local → UI se actualiza inmediatamente (sin red).
//   2. Si pasaron ≥5s desde el último sync exitoso, lanza un ciclo de sync
//      completo via SyncService → UI se actualiza al terminar.
//
// Estados que expone:
//   isLoading    → true solo si no hay datos locales Y estamos sincronizando.
//   isSyncing    → true mientras corre el sync remoto (datos locales visibles).
//   errorMessage → mensaje si el sync falla; null si todo va bien.
//                  No borra los datos locales.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:pocket_pilot/src/core/sync/sync_service.dart';
import 'package:pocket_pilot/src/features/accounts/data/account_repository.dart';
import 'package:pocket_pilot/src/features/accounts/domain/account.dart';
import 'package:uuid/uuid.dart';

class AccountsViewModel extends ChangeNotifier {
  static const _uuid = Uuid();

  final AccountRepository _repository;
  final SyncService _syncService;

  List<AccountModel> accounts = [];
  bool isLoading = false;
  bool isSyncing = false;
  String? errorMessage;

  DateTime? _lastSyncAt;

  AccountsViewModel({
    required AccountRepository repository,
    required SyncService syncService,
  }) : _repository = repository,
       _syncService = syncService;

  // ----------------------------------------------------------
  // API pública
  // ----------------------------------------------------------

  void loadOnAppear() {
    unawaited(_loadLocalThenMaybeSync());
  }

  Future<void> refresh() => _runSync();

  Future<void> createAccount({
    required String name,
    required String type,
    int? creditLimitCents,
    int? statementDay,
    int? paymentDueDay,
    int? interestRateApr,
    int? termMonths,
  }) async {
    final id = _uuid.v4();

    await _repository.createAccount(
      id: id,
      name: name,
      type: type,
      creditLimitCents: creditLimitCents,
      statementDay: statementDay,
      paymentDueDay: paymentDueDay,
      interestRateApr: interestRateApr,
      termMonths: termMonths,
    );

    accounts = await _repository.getAccounts();
    notifyListeners();
  }

  Future<void> updateAccount({
    required AccountModel current,
    required String name,
    int? creditLimitCents,
    int? statementDay,
    int? paymentDueDay,
    int? interestRateApr,
    int? termMonths,
  }) async {
    await _repository.updateAccount(
      current: current,
      name: name,
      creditLimitCents: creditLimitCents,
      statementDay: statementDay,
      paymentDueDay: paymentDueDay,
      interestRateApr: interestRateApr,
      termMonths: termMonths,
    );
    accounts = await _repository.getAccounts();
    notifyListeners();
  }

  Future<void> deleteAccount(String id) async {
    await _repository.deleteAccount(id);
    accounts = await _repository.getAccounts();
    notifyListeners();
  }

  // ----------------------------------------------------------
  // Implementación interna
  // ----------------------------------------------------------

  Future<void> _loadLocalThenMaybeSync() async {
    accounts = await _repository.getAccounts();
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
    isLoading = accounts.isEmpty;
    isSyncing = true;
    notifyListeners();

    try {
      await _syncService.sync();
      accounts = await _repository.getAccounts();
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
