# Quick Balance Reconciliation (Ajuste Rápido de Saldo)

## Context

Users need to reconcile their app balance with their real bank balance. Discrepancies arise from missed transactions, rounding, or bank fees not tracked in the app. The feature creates a single compensatory transaction so the app balance matches exactly, without polluting category-based budget analytics.

## Design

### New File

`lib/src/features/accounts/data/account_adjustment_service.dart`

### Dependencies (constructor injection)

| Dependency | Purpose |
|---|---|
| `TransactionLocalStore _local` | New method: `queryBalanceCents(accountId)` for account balance |
| `TransactionRepository _repository` | `createTransaction()` to insert + sync (reuses existing logic) |

This avoids bypassing the repository's outbox orchestration. The service does not need `DatabaseHelper` or `SyncOutbox` directly.

### Public API

```dart
/// Returns `true` if an adjustment was created, `false` if balance already matched.
Future<bool> adjustAccountBalance({
  required String accountId,
  required double realBalance,
  required String currencyCode,
}) async
```

### Algorithm

**Step 1 — Calculate current balance** via new method on `TransactionLocalStore`:

```dart
// New method added to TransactionLocalStore
Future<int> queryBalanceCents(String accountId) async {
  final db = await _db.database;
  final rows = await db.rawQuery(
    'SELECT COALESCE(SUM('
    '  CASE'
    "    WHEN type IN ('income', 'transfer_in') THEN amount_cents"
    "    WHEN type IN ('expense', 'transfer_out') THEN -amount_cents"
    '    ELSE 0'
    '  END'
    '), 0) AS balance_cents '
    'FROM transactions '
    "WHERE account_id = ? AND deleted_at IS NULL AND status = 'cleared'",
    [accountId],
  );
  return rows.first['balance_cents'] as int;
}
```

**Step 2 — Calculate difference:**

```dart
final realBalanceCents = (realBalance * 100).round();
final difference = realBalanceCents - currentBalanceCents;
```

**Step 3 — Early return** if `difference == 0` → return `false`.

**Step 4 — Delegate to `TransactionRepository.createTransaction()`:**

```dart
final now = DateTime.now().toUtc();
await _repository.createTransaction(
  id: _uuid.v4(),
  accountId: accountId,
  categoryId: null,
  amountMinor: difference.abs(),
  currencyCode: currencyCode,
  description: 'Ajuste manual de saldo',
  nature: '',
  date: now.toIso8601String().substring(0, 10),  // YYYY-MM-DD string
  type: difference > 0 ? 'income' : 'expense',
  status: 'cleared',
  tags: [],
);
```

**Step 5 — Return `true`.**

### Key Decisions

- **Delegates to `TransactionRepository.createTransaction()`**: Reuses the existing model construction, local insert (`upsertRow`), and outbox enqueue logic. No duplication.
- **Balance query lives on `TransactionLocalStore`**: All transaction SQL stays in the DAO layer, consistent with the project pattern.
- **`categoryId = null`**: Ensures the adjustment doesn't appear in budget/category analytics.
- **`nature = ''`**: Doesn't contaminate financial nature reports.
- **`status = 'cleared'`**: Immediately effective.
- **`date` is a `String` (`YYYY-MM-DD`)**: Matches `TransactionModel.date` type and the schema's `DATE` column.
- **`(realBalance * 100).round()`**: Avoids floating-point precision errors.
- **No account existence check**: The service trusts the caller provides a valid `accountId`. If the account is deleted, the balance query returns 0 and the FK constraint in SQLite guards against orphaned transactions. This matches the trust level of other repository methods in the project.
- **Concurrent sync**: The balance could be stale if a sync is running simultaneously. This is acceptable — the same race exists for all manual transaction creation in the app. The user can re-adjust if needed.

### Files Modified

| File | Change |
|---|---|
| `lib/src/features/accounts/data/account_adjustment_service.dart` | **New** — service class with `adjustAccountBalance()` |
| `lib/src/features/transactions/data/transaction_local_store.dart` | **Add** `queryBalanceCents(String accountId)` method |

### Verification

1. Run the app, navigate to an account with known balance
2. Trigger adjustment with a different balance value
3. Verify: new transaction appears in transaction list with correct type (income/expense) and amount
4. Verify: transaction has no category (`categoryId = null`)
5. Verify: budget/category analytics are unaffected
6. Verify: account balance now matches the entered value
7. Verify: sync outbox contains the new transaction (check `sync_outbox` table)
