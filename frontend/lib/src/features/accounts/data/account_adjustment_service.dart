// ============================================================
// AccountAdjustmentService — ajuste rápido de saldo (reconciliación)
// ============================================================
//
// Calcula la diferencia entre el saldo real del usuario y el saldo
// calculado en la app, y crea una transacción compensatoria
// (income o expense) sin categoría para no afectar analíticas.

import 'package:uuid/uuid.dart';

import 'package:pocket_pilot/src/features/transactions/data/transaction_local_store.dart';
import 'package:pocket_pilot/src/features/transactions/data/transaction_repository.dart';

class AccountAdjustmentService {
  static const _uuid = Uuid();

  final TransactionLocalStore _local;
  final TransactionRepository _repository;

  AccountAdjustmentService({
    required TransactionLocalStore local,
    required TransactionRepository repository,
  }) : _local = local,
       _repository = repository;

  /// Ajusta el saldo de [accountId] para que coincida con [realBalance].
  ///
  /// Retorna `true` si se creó una transacción de ajuste,
  /// `false` si el saldo ya coincidía.
  Future<bool> adjustAccountBalance({
    required String accountId,
    required double realBalance,
    required String currencyCode,
  }) async {
    final currentBalanceCents = await _local.queryBalanceCents(accountId);
    final realBalanceCents = (realBalance * 100).round();
    final difference = realBalanceCents - currentBalanceCents;

    if (difference == 0) return false;

    final now = DateTime.now().toUtc();

    await _repository.createTransaction(
      id: _uuid.v4(),
      accountId: accountId,
      categoryId: null,
      amountMinor: difference.abs(),
      currencyCode: currencyCode,
      description: 'Ajuste manual de saldo',
      date: now.toIso8601String().substring(0, 10),
      type: difference > 0 ? 'income' : 'expense',
      status: 'cleared',
      tags: [],
    );

    return true;
  }
}
