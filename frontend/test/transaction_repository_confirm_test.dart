import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:pocket_pilot/src/core/db/database_helper.dart';
import 'package:pocket_pilot/src/core/sync/sync_outbox.dart';
import 'package:pocket_pilot/src/features/transactions/data/transaction_local_store.dart';
import 'package:pocket_pilot/src/features/transactions/data/transaction_repository.dart';

void main() {
  test(
    'confirmTransaction preserva linked_transaction_id en ambas piernas de una transferencia',
    () async {
      final local = _FakeTransactionLocalStore();
      final outbox = _CapturingSyncOutbox();
      final repository = TransactionRepository(local: local, outbox: outbox);

      final createdAt = DateTime.utc(2026, 4, 10).toIso8601String();
      local.rowsById['out-1'] = _baseRow(
        id: 'out-1',
        accountId: 'acc-a',
        type: 'transfer_out',
        linkedTransactionId: 'in-1',
        templateId: 'tpl-1',
        createdAt: createdAt,
      );
      local.rowsById['in-1'] = _baseRow(
        id: 'in-1',
        accountId: 'acc-b',
        type: 'transfer_in',
        linkedTransactionId: 'out-1',
        templateId: 'tpl-1',
        createdAt: createdAt,
      );

      await repository.confirmTransaction('out-1');
      await repository.confirmTransaction('in-1');

      final outRow = local.rowsById['out-1']!;
      final inRow = local.rowsById['in-1']!;
      expect(outRow['linked_transaction_id'], 'in-1');
      expect(inRow['linked_transaction_id'], 'out-1');
      expect(outRow['template_id'], 'tpl-1');
      expect(inRow['template_id'], 'tpl-1');
      expect(outRow['status'], 'cleared');
      expect(inRow['status'], 'cleared');
      expect(outRow['source'], 'manual');

      expect(outbox.payloads.length, 2);
      final outPayload = jsonDecode(outbox.payloads[0]) as Map<String, dynamic>;
      final inPayload = jsonDecode(outbox.payloads[1]) as Map<String, dynamic>;
      expect(outPayload['linked_transaction_id'], 'in-1');
      expect(outPayload['template_id'], 'tpl-1');
      expect(outPayload['status'], 'cleared');
      expect(outPayload['source'], 'manual');
      expect(inPayload['linked_transaction_id'], 'out-1');
      expect(inPayload['template_id'], 'tpl-1');
      expect(inPayload['status'], 'cleared');
    },
  );

  test('confirmTransaction es idempotente cuando ya está cleared', () async {
    final local = _FakeTransactionLocalStore();
    final outbox = _CapturingSyncOutbox();
    final repository = TransactionRepository(local: local, outbox: outbox);

    local.rowsById['tx-1'] = _baseRow(
      id: 'tx-1',
      accountId: 'acc-a',
      type: 'expense',
      status: 'cleared',
      createdAt: DateTime.utc(2026, 4, 10).toIso8601String(),
    );

    await repository.confirmTransaction('tx-1');

    expect(outbox.payloads, isEmpty);
  });

  test('createTransaction persists the manual source by default', () async {
    final local = _FakeTransactionLocalStore();
    final outbox = _CapturingSyncOutbox();
    final repository = TransactionRepository(local: local, outbox: outbox);

    await repository.createTransaction(
      id: 'tx-1',
      accountId: 'acc-a',
      categoryId: null,
      amountMinor: 5000,
      currencyCode: 'MXN',
      description: 'Compra',
      date: '2026-07-18',
      type: 'expense',
      status: 'cleared',
      tags: const [],
    );

    expect(local.rowsById['tx-1']!['source'], 'manual');
    final payload = jsonDecode(outbox.payloads.single) as Map<String, dynamic>;
    expect(payload['source'], 'manual');
  });

  test('updateTransaction preserves an auto transaction source', () async {
    final local = _FakeTransactionLocalStore();
    final outbox = _CapturingSyncOutbox();
    final repository = TransactionRepository(local: local, outbox: outbox);
    final createdAt = DateTime.utc(2026, 7, 18).toIso8601String();
    local.rowsById['auto-1'] = {
      ..._baseRow(
        id: 'auto-1',
        accountId: 'acc-a',
        type: 'expense',
        createdAt: createdAt,
      ),
      'source': 'auto_notification',
    };

    await repository.updateTransaction(
      id: 'auto-1',
      accountId: 'acc-a',
      categoryId: null,
      amountMinor: 5000,
      currencyCode: 'MXN',
      description: 'Compra editada',
      date: '2026-07-18',
      type: 'expense',
      status: 'cleared',
      tags: const [],
      createdAt: DateTime.parse(createdAt),
    );

    expect(local.rowsById['auto-1']!['source'], 'auto_notification');
    final payload = jsonDecode(outbox.payloads.single) as Map<String, dynamic>;
    expect(payload['source'], 'auto_notification');
  });

  test(
    'confirmTransaction preserva yield_id en transacciones de yield',
    () async {
      final local = _FakeTransactionLocalStore();
      final outbox = _CapturingSyncOutbox();
      final repository = TransactionRepository(local: local, outbox: outbox);

      local.rowsById['yld-1'] = _baseRow(
        id: 'yld-1',
        accountId: 'acc-a',
        type: 'income',
        yieldId: 'yield-cfg-1',
        createdAt: DateTime.utc(2026, 4, 10).toIso8601String(),
      );

      await repository.confirmTransaction('yld-1');

      final row = local.rowsById['yld-1']!;
      expect(row['yield_id'], 'yield-cfg-1');
      expect(row['status'], 'cleared');

      final payload =
          jsonDecode(outbox.payloads.single) as Map<String, dynamic>;
      expect(payload['yield_id'], 'yield-cfg-1');
    },
  );
}

Map<String, dynamic> _baseRow({
  required String id,
  required String accountId,
  required String type,
  String? linkedTransactionId,
  String? templateId,
  String? yieldId,
  String? holdingId,
  String? lotId,
  String status = 'pending',
  required String createdAt,
}) {
  return {
    'id': id,
    'account_id': accountId,
    'category_id': null,
    'linked_transaction_id': linkedTransactionId,
    'template_id': templateId,
    'yield_id': yieldId,
    'holding_id': holdingId,
    'lot_id': lotId,
    'amount_cents': 5000,
    'installments_count': 1,
    'currency_code': 'USD',
    'tags': '[]',
    'description': '',
    'nature': '',
    'date': '2026-04-10',
    'type': type,
    'status': status,
    'source': 'manual',
    'created_at': createdAt,
    'updated_at': createdAt,
  };
}

class _FakeTransactionLocalStore extends TransactionLocalStore {
  _FakeTransactionLocalStore() : super(db: DatabaseHelper());

  final Map<String, Map<String, dynamic>> rowsById = {};

  @override
  Future<Map<String, dynamic>?> findRowById(String id) async {
    final row = rowsById[id];
    if (row == null) return null;
    return Map<String, dynamic>.from(row);
  }

  @override
  Future<void> upsertRow(Map<String, dynamic> row) async {
    rowsById[row['id'] as String] = Map<String, dynamic>.from(row);
  }
}

class _CapturingSyncOutbox extends SyncOutbox {
  _CapturingSyncOutbox() : super(db: DatabaseHelper());

  final List<String> payloads = [];

  @override
  Future<void> enqueue({
    required String entityType,
    required String entityId,
    required String operation,
    required String payload,
  }) async {
    payloads.add(payload);
  }
}
