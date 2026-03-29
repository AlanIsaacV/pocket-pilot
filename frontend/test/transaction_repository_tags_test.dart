import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:pocket_pilot/src/core/db/database_helper.dart';
import 'package:pocket_pilot/src/core/sync/sync_outbox.dart';
import 'package:pocket_pilot/src/features/transactions/data/transaction_local_store.dart';
import 'package:pocket_pilot/src/features/transactions/data/transaction_repository.dart';

void main() {
  test('createTransaction passes tags to local map payload', () async {
    final local = _FakeTransactionLocalStore();
    final outbox = _FakeSyncOutbox();
    final repository = TransactionRepository(local: local, outbox: outbox);

    await repository.createTransaction(
      id: 'tx-1',
      accountId: 'acc-1',
      categoryId: 'cat-1',
      amountMinor: 1000,
      currencyCode: 'USD',
      description: 'Test',
      date: '2026-04-01',
      type: 'expense',
      status: 'cleared',
      tags: const ['rent', 'fixed'],
    );

    expect(local.lastUpsertedRow, isNotNull);
    expect(local.lastUpsertedRow!['tags'], '["rent","fixed"]');

    final payload = jsonDecode(outbox.lastPayload!) as Map<String, dynamic>;
    expect(payload['tags'], ['rent', 'fixed']);
  });

  test('createTransfer propagates tags to both transfer legs', () async {
    final local = _FakeTransactionLocalStore();
    final outbox = _FakeSyncOutbox();
    final repository = TransactionRepository(local: local, outbox: outbox);

    await repository.createTransfer(
      outId: 'out-1',
      inId: 'in-1',
      fromAccountId: 'acc-1',
      toAccountId: 'acc-2',
      amountOutCents: 1200,
      currencyOut: 'USD',
      amountInCents: 1200,
      currencyIn: 'USD',
      date: '2026-04-01',
      descriptionOut: 'Transfer out',
      descriptionIn: 'Transfer in',
      tags: const ['wallet', 'internal'],
    );

    final outRow = local.rowsById['out-1'];
    final inRow = local.rowsById['in-1'];
    expect(outRow, isNotNull);
    expect(inRow, isNotNull);
    expect(outRow!['tags'], '["wallet","internal"]');
    expect(inRow!['tags'], '["wallet","internal"]');
  });
}

class _FakeTransactionLocalStore extends TransactionLocalStore {
  _FakeTransactionLocalStore() : super(db: DatabaseHelper());

  final Map<String, Map<String, dynamic>> rowsById = {};
  Map<String, dynamic>? lastUpsertedRow;

  @override
  Future<void> upsertRow(Map<String, dynamic> row) async {
    final copy = Map<String, dynamic>.from(row);
    rowsById[copy['id'] as String] = copy;
    lastUpsertedRow = copy;
  }
}

class _FakeSyncOutbox extends SyncOutbox {
  _FakeSyncOutbox() : super(db: DatabaseHelper());

  String? lastPayload;

  @override
  Future<void> enqueue({
    required String entityType,
    required String entityId,
    required String operation,
    required String payload,
  }) async {
    lastPayload = payload;
  }
}
