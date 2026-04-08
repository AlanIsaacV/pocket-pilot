import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:pocket_pilot/src/features/accounts/domain/account.dart';
import 'package:pocket_pilot/src/features/transaction_templates/data/scheduled_transaction_generator.dart';
import 'package:pocket_pilot/src/features/transaction_templates/domain/transaction_template.dart';

void main() {
  group('ScheduledTransactionGenerator', () {
    test(
      'uses deterministic UUID and does not duplicate on second run',
      () async {
        final templates = _FakeTemplateStore([
          _template(
            id: 'tpl-daily',
            accountId: 'acc-1',
            categoryId: 'cat-1',
            type: 'expense',
            amountCents: 1234,
            currencyCode: 'USD',
            frequency: 'DAILY',
            nextDate: '2026-04-10',
          ),
        ]);
        final tx = _FakeTransactionStore();
        final outbox = _FakeOutbox();
        final accounts = _FakeAccounts({'acc-1': 'USD'});
        final categories = _FakeCategories({'cat-1'});

        final generator = ScheduledTransactionGenerator(
          templates: templates,
          transactions: tx,
          outbox: outbox,
          accounts: accounts,
          categories: categories,
          horizon: Duration.zero,
        );

        final first = await generator.run(nowUtc: DateTime.utc(2026, 4, 10));
        final second = await generator.run(nowUtc: DateTime.utc(2026, 4, 10));

        expect(first.generatedTransactions, 1);
        expect(second.generatedTransactions, 0);
        expect(tx.rows.length, 1);
        expect(outbox.events.length, 1);

        final updated = templates.byId('tpl-daily')!;
        expect(updated.nextDate, '2026-04-11');
      },
    );

    test(
      'skips when category missing and leaves next_date unchanged',
      () async {
        final templates = _FakeTemplateStore([
          _template(
            id: 'tpl-missing-cat',
            accountId: 'acc-1',
            categoryId: 'cat-missing',
            type: 'expense',
            amountCents: 9900,
            currencyCode: 'USD',
            frequency: 'DAILY',
            nextDate: '2026-04-10',
          ),
        ]);
        final tx = _FakeTransactionStore();
        final outbox = _FakeOutbox();
        final accounts = _FakeAccounts({'acc-1': 'USD'});
        final categories = _FakeCategories({'cat-1'});

        final generator = ScheduledTransactionGenerator(
          templates: templates,
          transactions: tx,
          outbox: outbox,
          accounts: accounts,
          categories: categories,
          horizon: Duration.zero,
        );

        final report = await generator.run(nowUtc: DateTime.utc(2026, 4, 10));

        expect(report.generatedTransactions, 0);
        expect(report.skippedOccurrences, 1);
        expect(tx.rows, isEmpty);
        expect(outbox.events, isEmpty);
        expect(templates.byId('tpl-missing-cat')!.nextDate, '2026-04-10');
      },
    );

    test('transfer template creates out/in pair with linked ids', () async {
      final templates = _FakeTemplateStore([
        _template(
          id: 'tpl-transfer',
          accountId: 'acc-a',
          toAccountId: 'acc-b',
          type: 'transfer_out',
          amountCents: 5000,
          currencyCode: 'USD',
          frequency: 'DAILY',
          nextDate: '2026-04-10',
        ),
      ]);
      final tx = _FakeTransactionStore();
      final outbox = _FakeOutbox();
      final accounts = _FakeAccounts({'acc-a': 'USD', 'acc-b': 'USD'});
      final categories = _FakeCategories(const {});

      final generator = ScheduledTransactionGenerator(
        templates: templates,
        transactions: tx,
        outbox: outbox,
        accounts: accounts,
        categories: categories,
        horizon: Duration.zero,
      );

      final report = await generator.run(nowUtc: DateTime.utc(2026, 4, 10));

      expect(report.generatedTransactions, 2);
      expect(tx.rows.length, 2);

      final outRow = tx.rows.values.firstWhere(
        (row) => row['type'] == 'transfer_out',
      );
      final inRow = tx.rows.values.firstWhere(
        (row) => row['type'] == 'transfer_in',
      );

      expect(outRow['linked_transaction_id'], inRow['id']);
      expect(inRow['linked_transaction_id'], outRow['id']);
      expect(outRow['template_id'], 'tpl-transfer');
      expect(inRow['template_id'], 'tpl-transfer');
      expect(outbox.events.length, 2);
    });
  });
}

TransactionTemplateModel _template({
  required String id,
  required String accountId,
  String? toAccountId,
  String? categoryId,
  required String type,
  required int amountCents,
  required String currencyCode,
  required String frequency,
  required String nextDate,
}) {
  final now = DateTime.utc(2026, 4, 1);
  return TransactionTemplateModel(
    id: id,
    name: id,
    accountId: accountId,
    toAccountId: toAccountId,
    categoryId: categoryId,
    type: type,
    amountCents: amountCents,
    currencyCode: currencyCode,
    tags: const ['auto'],
    description: 'generated',
    frequency: frequency,
    nextDate: nextDate,
    endDate: null,
    createdAt: now,
    updatedAt: now,
    deletedAt: null,
  );
}

class _FakeTemplateStore implements TemplateScheduleStore {
  final Map<String, TransactionTemplateModel> _templates;

  _FakeTemplateStore(List<TransactionTemplateModel> templates)
    : _templates = {for (final t in templates) t.id: t};

  TransactionTemplateModel? byId(String id) => _templates[id];

  @override
  Future<List<TransactionTemplateModel>> getSchedulableTemplates({
    required String horizonDate,
  }) async {
    final list = _templates.values.where((t) {
      final next = t.nextDate;
      return t.deletedAt == null &&
          t.frequency != null &&
          next != null &&
          next.compareTo(horizonDate) <= 0;
    }).toList()..sort((a, b) => a.nextDate!.compareTo(b.nextDate!));
    return list;
  }

  @override
  Future<void> upsertTemplate(TransactionTemplateModel model) async {
    _templates[model.id] = model;
  }
}

class _FakeTransactionStore implements TransactionOccurrenceStore {
  final Map<String, Map<String, dynamic>> rows = {};

  @override
  Future<Map<String, dynamic>?> findById(String id) async => rows[id];

  @override
  Future<bool> insertIgnore(Map<String, dynamic> row) async {
    final id = row['id'] as String;
    if (rows.containsKey(id)) return false;
    rows[id] = Map<String, dynamic>.from(row);
    return true;
  }
}

class _FakeOutbox implements OutboxWriter {
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

class _FakeAccounts implements AccountLookup {
  final Map<String, String> _accountCurrency;

  _FakeAccounts(this._accountCurrency);

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
      deletedAt: null,
    );
  }
}

class _FakeCategories implements CategoryLookup {
  final Set<String> _activeIds;
  final Map<String, String> _natures;

  _FakeCategories(this._activeIds, [this._natures = const {}]);

  @override
  Future<bool> isActiveById(String id) async => _activeIds.contains(id);

  @override
  Future<String> getDefaultNatureById(String id) async =>
      _natures[id] ?? '';
}
