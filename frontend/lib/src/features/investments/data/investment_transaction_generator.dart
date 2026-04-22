import 'dart:convert';

import 'package:uuid/uuid.dart';

import 'package:pocket_pilot/src/core/ids/deterministic_namespace.dart';
import 'package:pocket_pilot/src/core/sync/scheduled_generation_orchestrator.dart';
import 'package:pocket_pilot/src/core/sync/sync_outbox.dart';
import 'package:pocket_pilot/src/features/accounts/data/account_local_store.dart';
import 'package:pocket_pilot/src/features/accounts/domain/account.dart';
import 'package:pocket_pilot/src/features/investments/data/investment_holding_local_store.dart';
import 'package:pocket_pilot/src/features/investments/data/investment_lot_local_store.dart';
import 'package:pocket_pilot/src/features/investments/domain/investment_holding.dart';
import 'package:pocket_pilot/src/features/investments/domain/investment_lot.dart';
import 'package:pocket_pilot/src/features/transactions/data/transaction_local_store.dart';

class InvestmentGenerationReport {
  final int upsertedTransactions;
  final int softDeletedTransactions;
  final int skippedLots;

  const InvestmentGenerationReport({
    required this.upsertedTransactions,
    required this.softDeletedTransactions,
    required this.skippedLots,
  });
}

abstract class InvestmentLotStore {
  Future<List<InvestmentLotModel>> listAllIncludingDeleted();
}

abstract class InvestmentHoldingLookup {
  Future<InvestmentHoldingModel?> getByIdIncludingArchived(String id);
}

abstract class InvestmentAccountLookup {
  Future<AccountModel?> getByIdIncludingArchived(String id);
}

abstract class InvestmentTransactionStore {
  Future<Map<String, dynamic>?> findRowById(String id);
  Future<void> upsertRow(Map<String, dynamic> row);
  Future<void> softDelete(String id, DateTime deletedAt);
}

abstract class InvestmentOutboxWriter {
  Future<void> enqueueTransactionUpsert(String id, String payloadJson);
  Future<void> enqueueTransactionDelete(String id, DateTime deletedAt);
}

class InvestmentLotStoreAdapter implements InvestmentLotStore {
  final InvestmentLotLocalStore _local;

  InvestmentLotStoreAdapter({required InvestmentLotLocalStore local})
    : _local = local;

  @override
  Future<List<InvestmentLotModel>> listAllIncludingDeleted() async {
    final rows = await _local.queryAllIncludingDeleted();
    return rows.map(InvestmentLotModel.fromMap).toList();
  }
}

class InvestmentHoldingLookupAdapter implements InvestmentHoldingLookup {
  final InvestmentHoldingLocalStore _local;

  InvestmentHoldingLookupAdapter({required InvestmentHoldingLocalStore local})
    : _local = local;

  @override
  Future<InvestmentHoldingModel?> getByIdIncludingArchived(String id) async {
    final row = await _local.getByIdIncludingArchived(id);
    if (row == null) return null;
    return InvestmentHoldingModel.fromMap(row);
  }
}

class InvestmentAccountLookupAdapter implements InvestmentAccountLookup {
  final AccountLocalStore _local;

  InvestmentAccountLookupAdapter({required AccountLocalStore local})
    : _local = local;

  @override
  Future<AccountModel?> getByIdIncludingArchived(String id) {
    return _local.getByIdIncludingArchived(id);
  }
}

class InvestmentTransactionStoreAdapter implements InvestmentTransactionStore {
  final TransactionLocalStore _local;

  InvestmentTransactionStoreAdapter({required TransactionLocalStore local})
    : _local = local;

  @override
  Future<Map<String, dynamic>?> findRowById(String id) => _local.findRowById(id);

  @override
  Future<void> upsertRow(Map<String, dynamic> row) => _local.upsertRow(row);

  @override
  Future<void> softDelete(String id, DateTime deletedAt) =>
      _local.softDelete(id, deletedAt);
}

class InvestmentOutboxWriterAdapter implements InvestmentOutboxWriter {
  final SyncOutbox _outbox;

  InvestmentOutboxWriterAdapter({required SyncOutbox outbox}) : _outbox = outbox;

  @override
  Future<void> enqueueTransactionUpsert(String id, String payloadJson) {
    return _outbox.enqueue(
      entityType: 'transaction',
      entityId: id,
      operation: 'upsert',
      payload: payloadJson,
    );
  }

  @override
  Future<void> enqueueTransactionDelete(String id, DateTime deletedAt) {
    return _outbox.enqueue(
      entityType: 'transaction',
      entityId: id,
      operation: 'delete',
      payload: jsonEncode({'deleted_at': deletedAt.toIso8601String()}),
    );
  }
}

class InvestmentTransactionGenerator implements ScheduledGeneratorRunner {
  final InvestmentLotStore _lots;
  final InvestmentHoldingLookup _holdings;
  final InvestmentAccountLookup _accounts;
  final InvestmentTransactionStore _transactions;
  final InvestmentOutboxWriter _outbox;
  final Uuid _uuid;

  InvestmentTransactionGenerator({
    required InvestmentLotStore lots,
    required InvestmentHoldingLookup holdings,
    required InvestmentAccountLookup accounts,
    required InvestmentTransactionStore transactions,
    required InvestmentOutboxWriter outbox,
    Uuid? uuid,
  }) : _lots = lots,
       _holdings = holdings,
       _accounts = accounts,
       _transactions = transactions,
       _outbox = outbox,
       _uuid = uuid ?? const Uuid();

  @override
  Future<InvestmentGenerationReport> run({required DateTime nowUtc}) async {
    final lots = await _lots.listAllIncludingDeleted();

    // Caches por holding/account para evitar N lookups cuando hay varios lots del mismo holding.
    final holdingCache = <String, InvestmentHoldingModel?>{};
    final accountCache = <String, AccountModel?>{};

    var upserted = 0;
    var softDeleted = 0;
    var skipped = 0;

    for (final lot in lots) {
      final txnId = _uuid.v5(
        kDeterministicInvestmentNamespace,
        'lot:${lot.id}',
      );

      final InvestmentHoldingModel? resolvedHolding;
      if (holdingCache.containsKey(lot.holdingId)) {
        resolvedHolding = holdingCache[lot.holdingId];
      } else {
        resolvedHolding =
            await _holdings.getByIdIncludingArchived(lot.holdingId);
        holdingCache[lot.holdingId] = resolvedHolding;
      }

      if (resolvedHolding == null) {
        skipped += 1;
        continue;
      }

      // Holdings are global — the lot's account_id is the single source of
      // truth for where cash settles.
      if (lot.accountId.isEmpty) {
        skipped += 1;
        continue;
      }

      final AccountModel? resolvedAccount;
      if (accountCache.containsKey(lot.accountId)) {
        resolvedAccount = accountCache[lot.accountId];
      } else {
        resolvedAccount = await _accounts.getByIdIncludingArchived(lot.accountId);
        accountCache[lot.accountId] = resolvedAccount;
      }

      if (resolvedAccount == null) {
        skipped += 1;
        continue;
      }

      final isDeleted = lot.deletedAt != null;

      if (isDeleted) {
        final existing = await _transactions.findRowById(txnId);
        if (existing == null || existing['deleted_at'] != null) {
          continue;
        }
        final deletedAt = lot.deletedAt!.toUtc();
        await _transactions.softDelete(txnId, deletedAt);
        await _outbox.enqueueTransactionDelete(txnId, deletedAt);
        softDeleted += 1;
        continue;
      }

      final row = _buildRow(
        txnId: txnId,
        lot: lot,
        holding: resolvedHolding,
        account: resolvedAccount,
        nowUtc: nowUtc,
      );

      if (row == null) {
        // FX rate missing cuando currencies difieren: saltamos silenciosamente.
        // El form hard-blockea esto, pero si llega un lot inválido desde server
        // no derivamos transacción hasta que el usuario lo corrija.
        skipped += 1;
        continue;
      }

      final existing = await _transactions.findRowById(txnId);
      if (_rowMatches(existing, row)) {
        continue;
      }

      // Preservar created_at si ya existía la transacción.
      if (existing != null && existing['created_at'] is String) {
        row['created_at'] = existing['created_at'];
      }

      await _transactions.upsertRow(row);
      await _outbox.enqueueTransactionUpsert(txnId, jsonEncode(row));
      upserted += 1;
    }

    return InvestmentGenerationReport(
      upsertedTransactions: upserted,
      softDeletedTransactions: softDeleted,
      skippedLots: skipped,
    );
  }

  Map<String, dynamic>? _buildRow({
    required String txnId,
    required InvestmentLotModel lot,
    required InvestmentHoldingModel holding,
    required AccountModel account,
    required DateTime nowUtc,
  }) {
    final sameCurrency = holding.currencyCode == account.currencyCode;
    final fxRate = lot.fxRate ?? (sameCurrency ? 1.0 : null);
    if (fxRate == null) return null;

    final gross = lot.quantity * lot.price;
    final feeInHoldingCurrency = lot.feeCents / 100.0;
    final lineTotalHolding =
        lot.isBuy ? gross + feeInHoldingCurrency : gross - feeInHoldingCurrency;
    final amountCents = (lineTotalHolding * fxRate * 100).round();

    final description = lot.isBuy
        ? 'Compra ${holding.symbol}'
        : 'Venta ${holding.symbol}';
    final type = lot.isBuy ? 'expense' : 'income';
    const nature = 'investment';

    final nowIso = nowUtc.toIso8601String();

    return <String, dynamic>{
      'id': txnId,
      'account_id': account.id,
      'category_id': null,
      'linked_transaction_id': null,
      'template_id': null,
      'yield_id': null,
      'holding_id': holding.id,
      'lot_id': lot.id,
      'type': type,
      'amount_cents': amountCents,
      'currency_code': account.currencyCode,
      'status': 'cleared',
      'tags': jsonEncode(const <String>[]),
      'description': description,
      'nature': nature,
      'date': lot.occurredAt,
      'created_at': nowIso,
      'updated_at': nowIso,
      'deleted_at': null,
    };
  }

  bool _rowMatches(Map<String, dynamic>? existing, Map<String, dynamic> row) {
    if (existing == null) return false;
    const keys = <String>[
      'account_id',
      'holding_id',
      'lot_id',
      'type',
      'amount_cents',
      'currency_code',
      'status',
      'description',
      'nature',
      'date',
    ];
    for (final k in keys) {
      if (existing[k] != row[k]) return false;
    }
    // Si la transacción estaba soft-deleted, debemos regenerarla.
    if (existing['deleted_at'] != null) return false;
    return true;
  }
}
