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
import 'package:pocket_pilot/src/features/transactions/data/transaction_repository.dart';
import 'package:uuid/uuid.dart';

class AccountsViewModel extends ChangeNotifier {
  static const _uuid = Uuid();
  static const _initialBalanceDescription = 'Monto inicial';

  final AccountRepository _repository;
  final TransactionRepository _transactionRepository;
  final SyncService _syncService;

  List<AccountModel> accounts = [];
  bool isLoading = false;
  bool isSyncing = false;
  String? errorMessage;

  DateTime? _lastSyncAt;
  bool _disposed = false;

  AccountsViewModel({
    required AccountRepository repository,
    required TransactionRepository transactionRepository,
    required SyncService syncService,
  }) : _repository = repository,
       _transactionRepository = transactionRepository,
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
    required String currencyCode,
    int? creditLimitCents,
    int? statementDay,
    int? paymentDueDay,
    int? interestRateApr,
    int? termMonths,
    int? initialAmountCents,
  }) async {
    final id = _uuid.v4();

    await _repository.createAccount(
      id: id,
      name: name,
      type: type,
      currencyCode: currencyCode,
      creditLimitCents: creditLimitCents,
      statementDay: statementDay,
      paymentDueDay: paymentDueDay,
      interestRateApr: interestRateApr,
      termMonths: termMonths,
    );

    if (initialAmountCents != null) {
      await _transactionRepository.createTransaction(
        id: _uuid.v4(),
        accountId: id,
        categoryId: null,
        amountMinor: initialAmountCents,
        currencyCode: currencyCode,
        description: _initialBalanceDescription,
        date: _toDateString(DateTime.now()),
        type: _initialBalanceTransactionType(type),
        status: 'cleared',
        tags: const [],
      );
    }

    accounts = await _repository.getAccounts();
    _safeNotify();
  }

  Future<void> updateAccount({
    required AccountModel current,
    required String name,
    required String currencyCode,
    int? creditLimitCents,
    int? statementDay,
    int? paymentDueDay,
    int? interestRateApr,
    int? termMonths,
    int? initialAmountCents,
  }) async {
    await _repository.updateAccount(
      current: current,
      name: name,
      currencyCode: currencyCode,
      creditLimitCents: creditLimitCents,
      statementDay: statementDay,
      paymentDueDay: paymentDueDay,
      interestRateApr: interestRateApr,
      termMonths: termMonths,
    );

    final initialBalanceType = _initialBalanceTransactionType(current.type);
    final existingInitial = await _transactionRepository
        .getInitialBalanceTransaction(
          accountId: current.id,
          type: initialBalanceType,
        );

    if (existingInitial != null && initialAmountCents == null) {
      await _transactionRepository.deleteTransaction(existingInitial.id);
    } else if (existingInitial != null && initialAmountCents != null) {
      await _transactionRepository.updateTransaction(
        id: existingInitial.id,
        accountId: current.id,
        categoryId: null,
        amountMinor: initialAmountCents,
        currencyCode: currencyCode,
        description: _initialBalanceDescription,
        date: existingInitial.date,
        type: existingInitial.type,
        status: existingInitial.status,
        tags: const [],
        createdAt: existingInitial.createdAt,
      );
    } else if (existingInitial == null && initialAmountCents != null) {
      await _transactionRepository.createTransaction(
        id: _uuid.v4(),
        accountId: current.id,
        categoryId: null,
        amountMinor: initialAmountCents,
        currencyCode: currencyCode,
        description: _initialBalanceDescription,
        date: _toDateString(DateTime.now()),
        type: initialBalanceType,
        status: 'cleared',
        tags: const [],
      );
    }

    accounts = await _repository.getAccounts();
    _safeNotify();
  }

  Future<int?> getInitialBalanceCents(AccountModel account) async {
    final transaction = await _transactionRepository
        .getInitialBalanceTransaction(
          accountId: account.id,
          type: _initialBalanceTransactionType(account.type),
        );
    return transaction?.amount;
  }

  Future<void> deleteAccount(String id) async {
    await _repository.deleteAccount(id);
    accounts = await _repository.getAccounts();
    _safeNotify();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  // ----------------------------------------------------------
  // Implementación interna
  // ----------------------------------------------------------

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> _loadLocalThenMaybeSync() async {
    accounts = await _repository.getAccounts();
    _safeNotify();
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
    _safeNotify();

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
      _safeNotify();
    }
  }

  String _initialBalanceTransactionType(String accountType) {
    switch (accountType) {
      case 'credit_card':
      case 'loan':
        return 'expense';
      default:
        return 'income';
    }
  }

  String _toDateString(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }
}
