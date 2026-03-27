import 'dart:convert';

import 'package:pocket_pilot/src/core/sync/sync_outbox.dart';
import 'package:pocket_pilot/src/features/accounts/data/account_local_store.dart';
import 'package:pocket_pilot/src/features/accounts/domain/account.dart';

class AccountRepository {
  final AccountLocalStore _local;
  final SyncOutbox _outbox;

  AccountRepository({
    required AccountLocalStore local,
    required SyncOutbox outbox,
  }) : _local = local,
       _outbox = outbox;

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
      type: current.type,
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

  Future<void> deleteAccount(String id) async {
    final now = DateTime.now().toUtc();
    await _local.softDelete(id, now);
    await _outbox.enqueue(
      entityType: 'account',
      entityId: id,
      operation: 'delete',
      payload: jsonEncode({'deleted_at': now.toIso8601String()}),
    );
  }
}
