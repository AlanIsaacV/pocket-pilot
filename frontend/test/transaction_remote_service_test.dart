import 'package:flutter_test/flutter_test.dart';

import 'package:pocket_pilot/src/features/transactions/data/transaction_remote_service.dart';

void main() {
  test('upsert payload forwards transaction source to the proto', () {
    final transaction = TransactionRemoteService.transactionFromPayload({
      'id': 'transaction-1',
      'account_id': 'account-1',
      'type': 'expense',
      'amount_cents': 12500,
      'installments_count': 1,
      'currency_code': 'MXN',
      'status': 'cleared',
      'source': 'auto_notification',
      'tags': <String>[],
      'description': 'Compra',
      'date': '2026-07-18',
    });

    expect(transaction.hasSource(), isTrue);
    expect(transaction.source, 'auto_notification');
  });

  test('old payloads without source default to manual', () {
    final transaction = TransactionRemoteService.transactionFromPayload({
      'id': 'transaction-1',
      'account_id': 'account-1',
      'type': 'expense',
      'amount_cents': 12500,
      'installments_count': 1,
      'currency_code': 'MXN',
      'status': 'cleared',
      'tags': <String>[],
      'description': 'Compra',
      'date': '2026-07-18',
    });

    expect(transaction.source, 'manual');
  });
}
