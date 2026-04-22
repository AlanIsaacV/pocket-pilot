import 'dart:convert';

import 'package:pocket_pilot/src/core/sync/sync_outbox.dart';
import 'package:pocket_pilot/src/features/accounts/data/account_local_store.dart';
import 'package:pocket_pilot/src/features/accounts/domain/account.dart';
import 'package:pocket_pilot/src/features/investments/data/investment_lot_local_store.dart';

class AccountRepository {
  final AccountLocalStore _local;
  final SyncOutbox _outbox;
  final InvestmentLotLocalStore? _investmentLotLocal;

  AccountRepository({
    required AccountLocalStore local,
    required SyncOutbox outbox,
    InvestmentLotLocalStore? investmentLotLocal,
  }) : _local = local,
       _outbox = outbox,
       _investmentLotLocal = investmentLotLocal;

  Future<List<AccountModel>> getAccounts() => _local.getAccounts();

  Future<void> createAccount({
    required String id,
    required String name,
    required String type,
    required String currencyCode,
    int? creditLimitCents,
    int? statementDay,
    int? paymentDueDay,
    int? interestRateApr,
    int? termMonths,
  }) async {
    final now = DateTime.now().toUtc();
    final model = AccountModel(
      id: id,
      name: name,
      type: type,
      currencyCode: currencyCode,
      creditLimitCents: creditLimitCents,
      statementDay: statementDay,
      paymentDueDay: paymentDueDay,
      interestRateApr: interestRateApr,
      termMonths: termMonths,
      createdAt: now,
      updatedAt: now,
    );

    await _local.upsert(model);
    await _outbox.enqueue(
      entityType: 'account',
      entityId: id,
      operation: 'upsert',
      payload: jsonEncode(model.toServerMap()),
    );
  }

  Future<void> updateAccount({
    required AccountModel current,
    required String type,
    required String name,
    required String currencyCode,
    int? creditLimitCents,
    int? statementDay,
    int? paymentDueDay,
    int? interestRateApr,
    int? termMonths,
  }) async {
    final now = DateTime.now().toUtc();
    final model = AccountModel(
      id: current.id,
      name: name,
      type: type,
      currencyCode: currencyCode,
      creditLimitCents: creditLimitCents,
      statementDay: statementDay,
      paymentDueDay: paymentDueDay,
      interestRateApr: interestRateApr,
      termMonths: termMonths,
      createdAt: current.createdAt,
      updatedAt: now,
    );

    await _local.upsert(model);
    await _outbox.enqueue(
      entityType: 'account',
      entityId: current.id,
      operation: 'upsert',
      payload: jsonEncode(model.toServerMap()),
    );
  }

  Future<List<AccountModel>> getArchivedAccounts() =>
      _local.getArchivedAccounts();

  /// Cuenta lots de inversión activos que settlear contra esta cuenta.
  /// Usado por la UI para mostrar el impacto del archive antes de confirmar.
  Future<int> countInvestmentLots(String accountId) async {
    final lotStore = _investmentLotLocal;
    if (lotStore == null) return 0;
    final rows = await lotStore.queryByAccount(accountId);
    return rows.length;
  }

  Future<void> archiveAccount(String id) async {
    final now = DateTime.now().toUtc();
    final current = await _local.getById(id);

    var deletedAt = now;
    if (current != null && !current.updatedAt.isBefore(now)) {
      deletedAt = current.updatedAt.add(const Duration(milliseconds: 1));
    }

    final lotStore = _investmentLotLocal;
    if (current != null && current.type == 'investment' && lotStore != null) {
      // Holdings are global and survive the archive. Only lots that settled
      // against this account are soft-deleted; the generator propagates to the
      // derived transactions on its next tick.
      final lotRows = await lotStore.queryByAccount(id);
      for (final row in lotRows) {
        final lotId = row['id'] as String;
        await lotStore.softDelete(lotId, deletedAt);
        await _outbox.enqueue(
          entityType: 'investment_lot',
          entityId: lotId,
          operation: 'delete',
          payload: jsonEncode({'deleted_at': deletedAt.toIso8601String()}),
        );
      }
    }

    await _local.softDelete(id, deletedAt);
    await _outbox.enqueue(
      entityType: 'account',
      entityId: id,
      operation: 'delete',
      payload: jsonEncode({'deleted_at': deletedAt.toIso8601String()}),
    );
  }

  Future<void> restoreAccount(String id) async {
    final now = DateTime.now().toUtc();
    await _local.restore(id, now);
    final model = await _local.getById(id);
    if (model == null) return;
    await _outbox.enqueue(
      entityType: 'account',
      entityId: id,
      operation: 'upsert',
      payload: jsonEncode(model.toServerMap()),
    );
  }
}
