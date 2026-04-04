import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_pilot/src/features/transactions/domain/transaction.dart';

void main() {
  test('fromMap parses tags JSON array', () {
    final model = TransactionModel.fromMap({
      'id': 't1',
      'account_id': 'a1',
      'category_id': null,
      'linked_transaction_id': null,
      'template_id': null,
      'yield_id': null,
      'amount_cents': 100,
      'installments_count': 1,
      'currency_code': 'MXN',
      'description': '',
      'date': '2026-04-01',
      'type': 'expense',
      'status': 'cleared',
      'tags': '["rent","fixed"]',
      'created_at': '2026-04-01T00:00:00Z',
      'updated_at': '2026-04-01T00:00:00Z',
    });

    expect(model.tags, ['rent', 'fixed']);
  });

  test('toMap encodes tags and template_id for local storage', () {
    final model = TransactionModel(
      id: 't1',
      accountId: 'a1',
      categoryId: null,
      linkedTransactionId: null,
      templateId: 'tpl-1',
      yieldId: null,
      amount: 100,
      installmentsCount: 1,
      currencyCode: 'MXN',
      description: '',
      date: '2026-04-01',
      type: 'expense',
      status: 'cleared',
      tags: const ['rent', 'fixed'],
      createdAt: DateTime.parse('2026-04-01T00:00:00Z'),
      updatedAt: DateTime.parse('2026-04-01T00:00:00Z'),
    );

    final map = model.toMap();

    expect(map['template_id'], 'tpl-1');
    expect(map['tags'], '["rent","fixed"]');
  });

  test('toServerMap keeps tags as repeated string payload', () {
    final model = TransactionModel(
      id: 't1',
      accountId: 'a1',
      categoryId: null,
      linkedTransactionId: null,
      templateId: 'tpl-1',
      yieldId: null,
      amount: 100,
      installmentsCount: 1,
      currencyCode: 'MXN',
      description: '',
      date: '2026-04-01',
      type: 'expense',
      status: 'cleared',
      tags: const ['rent', 'fixed'],
      createdAt: DateTime.parse('2026-04-01T00:00:00Z'),
      updatedAt: DateTime.parse('2026-04-01T00:00:00Z'),
    );

    final payload = model.toServerMap();

    expect(payload['template_id'], 'tpl-1');
    expect(payload['tags'], ['rent', 'fixed']);
  });
}
