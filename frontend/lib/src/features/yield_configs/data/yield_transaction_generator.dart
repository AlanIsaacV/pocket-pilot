import 'dart:convert';

import 'package:uuid/uuid.dart';

import 'package:pocket_pilot/src/core/ids/deterministic_namespace.dart';
import 'package:pocket_pilot/src/core/sync/scheduled_generation_orchestrator.dart';
import 'package:pocket_pilot/src/core/sync/sync_outbox.dart';
import 'package:pocket_pilot/src/features/accounts/data/account_local_store.dart';
import 'package:pocket_pilot/src/features/accounts/domain/account.dart';
import 'package:pocket_pilot/src/features/transactions/data/transaction_local_store.dart';
import 'package:pocket_pilot/src/features/yield_configs/data/yield_config_repository.dart';
import 'package:pocket_pilot/src/features/yield_configs/domain/yield_config.dart';
import 'package:pocket_pilot/src/features/yield_configs/domain/yield_interest_math.dart';
import 'package:pocket_pilot/src/features/yield_configs/domain/yield_schedule_date_math.dart';

class YieldGenerationReport {
  final int generatedTransactions;
  final int skippedConfigs;
  final int completedConfigs;
  final int renewedConfigs;

  const YieldGenerationReport({
    required this.generatedTransactions,
    required this.skippedConfigs,
    required this.completedConfigs,
    required this.renewedConfigs,
  });
}

abstract class YieldScheduleStore {
  Future<List<YieldConfigModel>> getSchedulableConfigs({
    required String horizonDate,
  });

  Future<void> upsertConfig(YieldConfigModel model);
}

abstract class YieldTransactionStore {
  Future<bool> insertIgnore(Map<String, dynamic> row);
}

abstract class YieldOutboxWriter {
  Future<void> enqueueTransactionUpsert(
    String transactionId,
    String payloadJson,
  );
}

abstract class YieldAccountLookup {
  Future<AccountModel?> getActiveById(String id);
}

class YieldScheduleStoreAdapter implements YieldScheduleStore {
  final YieldConfigRepository _repository;

  YieldScheduleStoreAdapter({required YieldConfigRepository repository})
    : _repository = repository;

  @override
  Future<List<YieldConfigModel>> getSchedulableConfigs({
    required String horizonDate,
  }) {
    return _repository.getSchedulableConfigs(horizonDate: horizonDate);
  }

  @override
  Future<void> upsertConfig(YieldConfigModel model) {
    return _repository.upsertConfig(model);
  }
}

class YieldTransactionStoreAdapter implements YieldTransactionStore {
  final TransactionLocalStore _local;

  YieldTransactionStoreAdapter({required TransactionLocalStore local})
    : _local = local;

  @override
  Future<bool> insertIgnore(Map<String, dynamic> row) {
    return _local.insertRowIgnoreConflict(row);
  }
}

class YieldOutboxWriterAdapter implements YieldOutboxWriter {
  final SyncOutbox _outbox;

  YieldOutboxWriterAdapter({required SyncOutbox outbox}) : _outbox = outbox;

  @override
  Future<void> enqueueTransactionUpsert(
    String transactionId,
    String payloadJson,
  ) {
    return _outbox.enqueue(
      entityType: 'transaction',
      entityId: transactionId,
      operation: 'upsert',
      payload: payloadJson,
    );
  }
}

class YieldAccountLookupAdapter implements YieldAccountLookup {
  final AccountLocalStore _local;

  YieldAccountLookupAdapter({required AccountLocalStore local})
    : _local = local;

  @override
  Future<AccountModel?> getActiveById(String id) {
    return _local.getById(id);
  }
}

class YieldTransactionGenerator implements ScheduledGeneratorRunner {
  final YieldScheduleStore _configs;
  final YieldTransactionStore _transactions;
  final YieldOutboxWriter _outbox;
  final YieldAccountLookup _accounts;
  final Duration _horizon;
  final Uuid _uuid;

  YieldTransactionGenerator({
    required YieldScheduleStore configs,
    required YieldTransactionStore transactions,
    required YieldOutboxWriter outbox,
    required YieldAccountLookup accounts,
    Duration horizon = const Duration(days: 30),
    Uuid? uuid,
  }) : _configs = configs,
       _transactions = transactions,
       _outbox = outbox,
       _accounts = accounts,
       _horizon = horizon,
       _uuid = uuid ?? const Uuid();

  @override
  Future<YieldGenerationReport> run({required DateTime nowUtc}) async {
    final now = nowUtc.toUtc();
    final today = _dateOnly(now);
    final horizonDate = _dateOnly(now.add(_horizon));

    final schedulable = await _configs.getSchedulableConfigs(
      horizonDate: horizonDate,
    );

    var generated = 0;
    var skipped = 0;
    var completed = 0;
    var renewed = 0;

    for (final cfg in schedulable) {
      final result = await _processConfig(
        cfg: cfg,
        today: today,
        horizonDate: horizonDate,
      );
      generated += result.generated;
      skipped += result.skipped;
      completed += result.completed;
      renewed += result.renewed;
    }

    return YieldGenerationReport(
      generatedTransactions: generated,
      skippedConfigs: skipped,
      completedConfigs: completed,
      renewedConfigs: renewed,
    );
  }

  Future<({int generated, int skipped, int completed, int renewed})>
  _processConfig({
    required YieldConfigModel cfg,
    required String today,
    required String horizonDate,
  }) async {
    final startCursor = cfg.nextDate;
    var cursor = startCursor;
    var maturityDate = cfg.maturityDate;
    var status = cfg.status;
    var generated = 0;
    var renewed = 0;
    var completed = 0;
    var changed = false;

    if (_isMalformedSchedule(cfg)) {
      return (generated: 0, skipped: 1, completed: 0, renewed: 0);
    }

    final account = await _accounts.getActiveById(cfg.accountId);
    if (account == null) {
      return (generated: 0, skipped: 1, completed: 0, renewed: 0);
    }

    while (_onOrBefore(cursor, horizonDate)) {
      if (maturityDate != null && cursor.compareTo(maturityDate) > 0) {
        if (cfg.autoRenew && cfg.termDays != null && cfg.termDays! > 0) {
          final nextMaturity = _plusDays(maturityDate, cfg.termDays!);
          maturityDate = nextMaturity;
          changed = true;
          renewed += 1;
          continue;
        }

        status = 'completed';
        completed = 1;
        cursor = maturityDate;
        changed = true;
        break;
      }

      final daysElapsed = daysElapsedForPayout(
        cfg.payoutFrequency,
        cursor,
        termDays: cfg.termDays,
      );

      final interestCents = computeInterestCents(
        amountCents: cfg.amountCents,
        apyRate: cfg.apyRate,
        daysElapsed: daysElapsed,
      );

      if (interestCents > 0) {
        final transactionId = _uuid.v5(
          kDeterministicYieldNamespace,
          '${cfg.id}-$cursor',
        );

        final nowIso = DateTime.now().toUtc().toIso8601String();
        final row = <String, dynamic>{
          'id': transactionId,
          'account_id': cfg.accountId,
          'category_id': null,
          'linked_transaction_id': null,
          'template_id': null,
          'yield_id': cfg.id,
          'type': 'income',
          'amount_cents': interestCents,
          'currency_code': account.currencyCode,
          'status': cursor.compareTo(today) <= 0 ? 'cleared' : 'pending',
          'tags': jsonEncode(const <String>[]),
          'description': cfg.name,
          'nature': 'passive',
          'date': cursor,
          'created_at': nowIso,
          'updated_at': nowIso,
          'deleted_at': null,
        };

        final inserted = await _transactions.insertIgnore(row);
        if (inserted) {
          generated += 1;
          await _outbox.enqueueTransactionUpsert(
            transactionId,
            jsonEncode(row),
          );
        }
      }

      final nextCursor = nextScheduleDate(
        cfg.payoutFrequency,
        cursor,
        termDays: cfg.termDays,
      );

      if (cfg.payoutFrequency == 'at_maturity') {
        if (cfg.autoRenew) {
          maturityDate = nextCursor;
          cursor = nextCursor;
          changed = true;
          renewed += 1;
          continue;
        }

        status = 'completed';
        completed = 1;
        cursor = maturityDate!;
        changed = true;
        break;
      }

      cursor = nextCursor;
      changed = true;
    }

    if (changed || status != cfg.status || maturityDate != cfg.maturityDate) {
      final updated = cfg
          .copyWith(
            nextDate: cursor,
            maturityDate: maturityDate,
            status: status,
            updatedAt: DateTime.now().toUtc(),
          )
          .normalized();
      await _configs.upsertConfig(updated);
    }

    return (
      generated: generated,
      skipped: 0,
      completed: completed,
      renewed: renewed,
    );
  }

  bool _isMalformedSchedule(YieldConfigModel cfg) {
    if (!_isIsoDate(cfg.nextDate)) {
      return true;
    }

    final freq = cfg.payoutFrequency;
    if (freq != 'daily' &&
        freq != 'weekly' &&
        freq != 'monthly' &&
        freq != 'at_maturity') {
      return true;
    }

    if (freq == 'at_maturity') {
      if (cfg.termDays == null || cfg.termDays! <= 0) {
        return true;
      }
      if (cfg.maturityDate == null || !_isIsoDate(cfg.maturityDate!)) {
        return true;
      }
      if (cfg.nextDate != cfg.maturityDate) {
        return true;
      }
    }

    if (cfg.maturityDate != null && !_isIsoDate(cfg.maturityDate!)) {
      return true;
    }

    return false;
  }

  static bool _onOrBefore(String a, String b) => a.compareTo(b) <= 0;

  static bool _isIsoDate(String value) {
    if (value.length != 10) return false;
    try {
      DateTime.parse(value);
      return true;
    } catch (_) {
      return false;
    }
  }

  static String _plusDays(String date, int days) {
    final d = DateTime.parse(date).add(Duration(days: days));
    return _dateOnly(d);
  }

  static String _dateOnly(DateTime value) {
    final y = value.year.toString().padLeft(4, '0');
    final m = value.month.toString().padLeft(2, '0');
    final d = value.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }
}
