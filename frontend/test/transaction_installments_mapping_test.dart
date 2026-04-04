import 'package:fixnum/fixnum.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protobuf/well_known_types/google/protobuf/timestamp.pb.dart';

import 'package:pocket_pilot/src/features/transactions/domain/transaction.dart';
import 'package:pocket_pilot/src/generated/pocket_pilot/v1/transaction_service.pbgrpc.dart';

void main() {
  test('fromMap reads installments_count', () {
    final model = TransactionModel.fromMap({
      'id': 'tx-1',
      'account_id': 'acc-1',
      'category_id': 'cat-1',
      'linked_transaction_id': null,
      'template_id': null,
      'yield_id': null,
      'amount_cents': 1000,
      'installments_count': 6,
      'currency_code': 'MXN',
      'status': 'cleared',
      'tags': '[]',
      'description': 'MSI',
      'date': '2026-04-03',
      'type': 'expense',
      'created_at': '2026-04-03T00:00:00Z',
      'updated_at': '2026-04-03T00:00:00Z',
    });

    expect(model.installmentsCount, 6);
  });

  test('toMap and toServerMap include installments_count', () {
    final model = TransactionModel(
      id: 'tx-2',
      accountId: 'acc-1',
      categoryId: 'cat-1',
      amount: 1500,
      installmentsCount: 3,
      currencyCode: 'MXN',
      description: 'Laptop',
      date: '2026-04-03',
      type: 'expense',
      status: 'cleared',
      tags: const [],
      createdAt: DateTime.parse('2026-04-03T00:00:00Z'),
      updatedAt: DateTime.parse('2026-04-03T00:00:00Z'),
    );

    expect(model.toMap()['installments_count'], 3);
    expect(model.toServerMap()['installments_count'], 3);
  });

  test('fromProto maps installments_count', () {
    final now = DateTime.utc(2026, 4, 3);
    final proto = Transaction(
      id: 'tx-3',
      accountId: 'acc-1',
      type: TransactionType.TRANSACTION_TYPE_EXPENSE,
      amountCents: Int64(1200),
      installmentsCount: 12,
      currencyCode: 'MXN',
      status: 'cleared',
      description: 'MSI proto',
      date: Timestamp.fromDateTime(now),
      createdAt: Timestamp.fromDateTime(now),
      updatedAt: Timestamp.fromDateTime(now),
    );

    final model = TransactionModel.fromProto(proto);
    expect(model.installmentsCount, 12);
  });

  test('rejects installments_count < 1', () {
    expect(
      () => TransactionModel(
        id: 'tx-4',
        accountId: 'acc-1',
        categoryId: null,
        amount: 1200,
        installmentsCount: 0,
        currencyCode: 'MXN',
        description: 'invalid',
        date: '2026-04-03',
        type: 'expense',
        status: 'cleared',
        tags: const [],
        createdAt: DateTime.parse('2026-04-03T00:00:00Z'),
        updatedAt: DateTime.parse('2026-04-03T00:00:00Z'),
      ),
      throwsArgumentError,
    );
  });
}
