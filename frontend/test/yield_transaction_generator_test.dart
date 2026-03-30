import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:pocket_pilot/src/features/accounts/domain/account.dart';
import 'package:pocket_pilot/src/features/yield_configs/data/yield_transaction_generator.dart';
import 'package:pocket_pilot/src/features/yield_configs/domain/yield_config.dart';

void main() {
  group('YieldTransactionGenerator', () {
    test(
      'generates deterministic income transaction with yield_id linkage',
      () async {
        final configs = _FakeYieldScheduleStore([
          _cfg(
            id: 'yield-1',
            accountId: 'acc-1',
            amountCents: 100000,
            apyRate: 10,
            payoutFrequency: 'daily',
            nextDate: '2026-04-10',
            status: 'active',
          ),
        ]);

        final transactions = _FakeTransactionStore();
        final outbox = _FakeOutbox();
        final accounts = _FakeAccountLookup({'acc-1': 'USD'});

        final generator = YieldTransactionGenerator(
          configs: configs,
          transactions: transactions,
          outbox: outbox,
          accounts: accounts,
          horizon: Duration.zero,
        );

        final first = await generator.run(nowUtc: DateTime.utc(2026, 4, 10));
        final second = await generator.run(nowUtc: DateTime.utc(2026, 4, 10));

        expect(first.generatedTransactions, 1);
        expect(second.generatedTransactions, 0);
        expect(transactions.rows.length, 1);
        expect(outbox.events.length, 1);
        expect(transactions.rows.values.first['yield_id'], 'yield-1');
      },
    );

    test(
      'marks completed when maturity reached and auto_renew false',
      () async {
        final maturity = '2026-04-10';
        final configs = _FakeYieldScheduleStore([
          _cfg(
            id: 'yield-2',
            accountId: 'acc-1',
            amountCents: 100000,
            apyRate: 10,
            payoutFrequency: 'at_maturity',
            nextDate: maturity,
            maturityDate: maturity,
            termDays: 30,
            autoRenew: false,
            status: 'active',
          ),
        ]);

        final generator = YieldTransactionGenerator(
          configs: configs,
          transactions: _FakeTransactionStore(),
          outbox: _FakeOutbox(),
          accounts: _FakeAccountLookup({'acc-1': 'USD'}),
          horizon: const Duration(days: 1),
        );

        final report = await generator.run(nowUtc: DateTime.utc(2026, 4, 10));
        final updated = configs.byId('yield-2')!;

        expect(report.completedConfigs, 1);
        expect(updated.status, 'completed');
        expect(updated.nextDate, maturity);
        expect(updated.maturityDate, maturity);
      },
    );

    test('auto_renew at_maturity advances maturity by term_days', () async {
      final configs = _FakeYieldScheduleStore([
        _cfg(
          id: 'yield-3',
          accountId: 'acc-1',
          amountCents: 100000,
          apyRate: 10,
          payoutFrequency: 'at_maturity',
          nextDate: '2026-04-10',
          maturityDate: '2026-04-10',
          termDays: 90,
          autoRenew: true,
          status: 'active',
        ),
      ]);

      final generator = YieldTransactionGenerator(
        configs: configs,
        transactions: _FakeTransactionStore(),
        outbox: _FakeOutbox(),
        accounts: _FakeAccountLookup({'acc-1': 'USD'}),
        horizon: Duration.zero,
      );

      final report = await generator.run(nowUtc: DateTime.utc(2026, 4, 10));
      final updated = configs.byId('yield-3')!;

      expect(report.renewedConfigs, greaterThanOrEqualTo(1));
      expect(updated.nextDate, '2026-07-09');
      expect(updated.maturityDate, '2026-07-09');
      expect(updated.status, 'active');
    });

    test(
      'interest zero advances cursor but does not create transaction',
      () async {
        final configs = _FakeYieldScheduleStore([
          _cfg(
            id: 'yield-4',
            accountId: 'acc-1',
            amountCents: 1,
            apyRate: 1,
            payoutFrequency: 'daily',
            nextDate: '2026-04-10',
            status: 'active',
          ),
        ]);

        final transactions = _FakeTransactionStore();
        final generator = YieldTransactionGenerator(
          configs: configs,
          transactions: transactions,
          outbox: _FakeOutbox(),
          accounts: _FakeAccountLookup({'acc-1': 'USD'}),
          horizon: Duration.zero,
        );

        final report = await generator.run(nowUtc: DateTime.utc(2026, 4, 10));
        final updated = configs.byId('yield-4')!;

        expect(report.generatedTransactions, 0);
        expect(transactions.rows, isEmpty);
        expect(updated.nextDate, '2026-04-11');
      },
    );
  });
}

YieldConfigModel _cfg({
  required String id,
  required String accountId,
  required int amountCents,
  required double apyRate,
  required String payoutFrequency,
  required String nextDate,
  String? maturityDate,
  int? termDays,
  bool autoRenew = false,
  required String status,
}) {
  final now = DateTime.utc(2026, 4, 1);
  return YieldConfigModel(
    id: id,
    accountId: accountId,
    name: id,
    amountCents: amountCents,
    apyRate: apyRate,
    payoutFrequency: payoutFrequency,
    nextDate: nextDate,
    maturityDate: maturityDate,
    termDays: termDays,
    autoRenew: autoRenew,
    status: status,
    createdAt: now,
    updatedAt: now,
  );
}

class _FakeYieldScheduleStore implements YieldScheduleStore {
  final Map<String, YieldConfigModel> _rows;

  _FakeYieldScheduleStore(List<YieldConfigModel> rows)
    : _rows = {for (final row in rows) row.id: row};

  YieldConfigModel? byId(String id) => _rows[id];

  @override
  Future<List<YieldConfigModel>> getSchedulableConfigs({
    required String horizonDate,
  }) async {
    return _rows.values.where((row) {
      return row.deletedAt == null &&
          row.status == 'active' &&
          row.nextDate.compareTo(horizonDate) <= 0;
    }).toList();
  }

  @override
  Future<void> upsertConfig(YieldConfigModel model) async {
    _rows[model.id] = model;
  }
}

class _FakeTransactionStore implements YieldTransactionStore {
  final Map<String, Map<String, dynamic>> rows = {};

  @override
  Future<bool> insertIgnore(Map<String, dynamic> row) async {
    final id = row['id'] as String;
    if (rows.containsKey(id)) return false;
    rows[id] = Map<String, dynamic>.from(row);
    return true;
  }
}

class _FakeOutbox implements YieldOutboxWriter {
  final List<({String id, Map<String, dynamic> payload})> events = [];

  @override
  Future<void> enqueueTransactionUpsert(
    String transactionId,
    String payloadJson,
  ) async {
    events.add((
      id: transactionId,
      payload: jsonDecode(payloadJson) as Map<String, dynamic>,
    ));
  }
}

class _FakeAccountLookup implements YieldAccountLookup {
  final Map<String, String> _accountCurrency;

  _FakeAccountLookup(this._accountCurrency);

  @override
  Future<AccountModel?> getActiveById(String id) async {
    final currency = _accountCurrency[id];
    if (currency == null) return null;
    final now = DateTime.utc(2026, 4, 1);
    return AccountModel(
      id: id,
      name: id,
      type: 'cash',
      currencyCode: currency,
      createdAt: now,
      updatedAt: now,
    );
  }
}
