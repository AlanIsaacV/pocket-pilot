# CSV Import with Intermediate Mapping — Design Spec

## Context

Users need to import transaction history from CSV files (bank exports, spreadsheets). The CSV contains human-readable names ("Banamex", "Comida") while the database is UUID-based and relational. This feature bridges that gap through a 3-phase pipeline: extract entities → user resolves mapping → batch insert.

**Scope:** Business logic + data layer only. UI screens will be designed in a separate cycle.

---

## CSV Format

Expected headers (first row):

```
date,type,amount,currency,account,destination_account,category,tags,notes
```

| Column | Type | Rules |
|---|---|---|
| `date` | String | ISO 8601 `YYYY-MM-DD` |
| `type` | String | `EXPENSE`, `INCOME`, or `TRANSFER` |
| `amount` | Decimal | e.g. `150.50` — converted to cents in Dart |
| `currency` | String | ISO 4217 code, e.g. `MXN` |
| `account` | String | Human-readable account name |
| `destination_account` | String | Only populated for `TRANSFER` type |
| `category` | String | Human-readable category name (optional) |
| `tags` | String | Pipe-separated: `Viaje\|Urgente` |
| `notes` | String | Free text description |

---

## Feature Structure

```
lib/src/features/csv_import/
├── domain/
│   ├── csv_transaction_row.dart
│   ├── csv_extraction_result.dart
│   ├── csv_insert_batch.dart
│   └── mapping_dictionary.dart
├── data/
│   ├── csv_import_local_store.dart
│   ├── csv_import_repository.dart
│   └── csv_import_service.dart
└── (ui/ — second cycle)
```

---

## Domain DTOs

### `CsvTransactionRow`

Represents one parsed CSV row with Dart types:

```dart
class CsvTransactionRow {
  final String date;                        // "2024-03-15"
  final String type;                        // "EXPENSE" | "INCOME" | "TRANSFER"
  final double amount;                      // 150.50
  final String currencyCode;                // "MXN"
  final String accountName;                 // "Banamex"
  final String? destinationAccountName;     // only for TRANSFER
  final String? categoryName;               // "Comida" (nullable)
  final List<String> tagNames;              // ["Viaje", "Urgente"]
  final String notes;                       // "Cena con amigos"
}
```

### `CsvExtractionResult`

Output of Phase 1 — parsed rows + unique entity names for UI mapping:

```dart
class CsvExtractionResult {
  final List<CsvTransactionRow> rows;
  final Set<String> uniqueAccountNames;
  final Set<String> uniqueCategoryNames;
  final Set<String> uniqueTagNames;
}
```

### `MappingDictionary`

Built by UI after user resolves names → UUIDs:

```dart
class MappingDictionary {
  final Map<String, String> accountIdMap;   // "Banamex" → "uuid-..."
  final Map<String, String> categoryIdMap;  // "Comida" → "uuid-..."
  final Map<String, String> tagIdMap;       // "Viaje" → "uuid-..."
}
```

### `CsvInsertBatch`

Output of Phase 3 — ready for SQL batch execution:

```dart
class CsvInsertBatch {
  final List<Map<String, dynamic>> transactionMaps;
  final List<Map<String, dynamic>> outboxEntries;
}
```

---

## CsvImportService (Business Logic)

**File:** `data/csv_import_service.dart`

Stateless class. Receives `Uuid` instance via constructor.

### Phase 1: `parseAndExtract(String csvContent) → CsvExtractionResult`

1. Parse CSV string using `csv` package (`CsvToListConverter`)
2. Validate first row matches expected headers
3. For each subsequent row, construct a `CsvTransactionRow`:
   - Trim all string fields
   - Split `tags` field by `|`, trim each, filter empty
   - `destination_account` → null if empty or type is not TRANSFER
4. Collect unique non-empty values into Sets for accounts, categories, tags
5. Account names: collect from both `account` and `destination_account` columns
6. Return `CsvExtractionResult`

**Error handling:** Throw descriptive exceptions for:
- Malformed or missing headers
- Unparseable rows (with row number)
- Invalid `type` values (not EXPENSE, INCOME, or TRANSFER)
- TRANSFER rows with empty `destination_account`

### Phase 3: `buildInsertBatch(List<CsvTransactionRow> rows, MappingDictionary mapping) → CsvInsertBatch`

For each row, apply transformation rules:

**Amount conversion:**
```dart
final amountCents = (row.amount * 100).round();
```

**Entity resolution:**
```dart
final accountId = mapping.accountIdMap[row.accountName]!;
final categoryId = row.categoryName != null
    ? mapping.categoryIdMap[row.categoryName]
    : null;
final tagIds = row.tagNames
    .map((name) => mapping.tagIdMap[name]!)
    .toList();
```

**Tags encoding:** `jsonEncode(tagIds)` — stored as JSON array string in `tags` column, consistent with existing pattern.

**Timestamps:**
```dart
final now = DateTime.now().toUtc().toIso8601String();
// Both created_at and updated_at = now
```

**Default fields:**
- `status = 'cleared'`
- `installments_count = 1`
- `description = row.notes`
- `template_id = null`
- `yield_id = null`
- Note: `deleted_at` is omitted from the map (SQLite defaults to NULL), consistent with `TransactionModel.toMap()`

**Error handling in entity resolution:** If a name from the CSV row is not found in the `MappingDictionary`, throw a descriptive error indicating the missing mapping and row number. The `!` null assertion operator is insufficient — use explicit lookups with meaningful errors.

#### Standard transaction (EXPENSE / INCOME)

Generate 1 UUID. Create 1 transaction map + 1 outbox entry.

Type mapping:
- `EXPENSE` → `'expense'`
- `INCOME` → `'income'`

```dart
final id = _uuid.v4();
final txMap = {
  'id': id,
  'account_id': accountId,
  'category_id': categoryId,
  'linked_transaction_id': null,
  'template_id': null,
  'yield_id': null,
  'type': type,  // 'expense' or 'income'
  'amount_cents': amountCents,
  'installments_count': 1,
  'currency_code': row.currencyCode,
  'status': 'cleared',
  'tags': jsonEncode(tagIds),
  'description': row.notes,
  'date': row.date,
  'created_at': now,
  'updated_at': now,
};
```

#### Transfer (TRANSFER) — Double-entry

Generate 2 UUIDs (`outId`, `inId`). Create 2 transaction maps + 2 outbox entries.

**Known limitation:** The CSV format has a single `amount` and `currency` per row. Both transfer legs use the same amount and currency. The existing `createTransfer()` supports different amounts per leg (for cross-currency transfers), but that is out of scope for CSV import. Users needing cross-currency transfers should create them manually.

```dart
final outId = _uuid.v4();
final inId = _uuid.v4();
final destAccountId = mapping.accountIdMap[row.destinationAccountName]!;

// Shared fields for both legs
final sharedFields = {
  'category_id': categoryId,
  'template_id': null,
  'yield_id': null,
  'amount_cents': amountCents,
  'installments_count': 1,
  'currency_code': row.currencyCode,
  'status': 'cleared',
  'tags': jsonEncode(tagIds),
  'description': row.notes,
  'date': row.date,
  'created_at': now,
  'updated_at': now,
};

// transfer_out from source account
final outMap = {
  ...sharedFields,
  'id': outId,
  'account_id': accountId,
  'linked_transaction_id': inId,
  'type': 'transfer_out',
};

// transfer_in to destination account
final inMap = {
  ...sharedFields,
  'id': inId,
  'account_id': destAccountId,
  'linked_transaction_id': outId,
  'type': 'transfer_in',
};
```

#### Outbox entries

**Design decision:** We bypass `SyncOutbox.enqueue()` and insert outbox rows directly into the batch. This is intentional — `enqueue()` does individual `db.insert()` calls, and we need all outbox entries in the same atomic batch as the transactions. This is the only code path that writes to `sync_outbox` directly; if `SyncOutbox.enqueue()` changes its schema in the future, this code must be updated accordingly.

For each transaction map, build a server-format payload map. The key difference from the SQLite map: `tags` must be a `List<String>` (not JSON-encoded string), matching `TransactionModel.toServerMap()`:

```dart
// Build server payload — tags as List<String>, not JSON string
final serverPayload = Map<String, dynamic>.from(txMap)
  ..['tags'] = tagIds;  // List<String>, not jsonEncode(tagIds)

// Outbox entry — omit created_at (SQLite DEFAULT handles it)
{
  'entity_type': 'transaction',
  'entity_id': txMap['id'],
  'operation': 'upsert',
  'payload': jsonEncode(serverPayload),
}
```

The `sync_outbox` table has a UNIQUE constraint on `(entity_type, entity_id)`, so `ConflictAlgorithm.replace` ensures no duplicates. Fields `created_at`, `retry_count`, and `last_error` use their SQLite defaults.

---

## Data Layer

### `CsvImportLocalStore`

**File:** `data/csv_import_local_store.dart`

Receives `DatabaseHelper` via constructor. Single method:

```dart
class CsvImportLocalStore {
  final DatabaseHelper _db;

  CsvImportLocalStore({required DatabaseHelper db}) : _db = db;

  Future<void> insertBatch(CsvInsertBatch batch) async {
    final db = await _db.database;
    final dbBatch = db.batch();

    for (final txMap in batch.transactionMaps) {
      dbBatch.insert(
        'transactions',
        txMap,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    for (final entry in batch.outboxEntries) {
      dbBatch.insert(
        'sync_outbox',
        entry,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    await dbBatch.commit(noResult: true);
  }
}
```

### `CsvImportRepository`

**File:** `data/csv_import_repository.dart`

Thin orchestrator in this first iteration:

```dart
class CsvImportRepository {
  final CsvImportLocalStore _local;

  CsvImportRepository({required CsvImportLocalStore local}) : _local = local;

  Future<void> importTransactions(CsvInsertBatch batch) async {
    await _local.insertBatch(batch);
  }
}
```

---

## New Dependency

Add to `frontend/pubspec.yaml`:

```yaml
csv: ^6.0.0
```

---

## Critical Files to Modify

| File | Action |
|---|---|
| `frontend/pubspec.yaml` | Add `csv: ^6.0.0` dependency |
| `frontend/lib/src/features/csv_import/domain/csv_transaction_row.dart` | **Create** |
| `frontend/lib/src/features/csv_import/domain/csv_extraction_result.dart` | **Create** |
| `frontend/lib/src/features/csv_import/domain/csv_insert_batch.dart` | **Create** |
| `frontend/lib/src/features/csv_import/domain/mapping_dictionary.dart` | **Create** |
| `frontend/lib/src/features/csv_import/data/csv_import_service.dart` | **Create** |
| `frontend/lib/src/features/csv_import/data/csv_import_local_store.dart` | **Create** |
| `frontend/lib/src/features/csv_import/data/csv_import_repository.dart` | **Create** |

## Existing Patterns to Reuse

| Pattern | Source File |
|---|---|
| `TransactionModel.toMap()` field structure | `lib/src/features/transactions/domain/transaction.dart` |
| `TransactionRepository.createTransfer()` double-entry logic | `lib/src/features/transactions/data/transaction_repository.dart` |
| `TransactionLocalStore.upsertRows()` batch pattern | `lib/src/features/transactions/data/transaction_local_store.dart` |
| `SyncOutbox.enqueue()` outbox entry format | `lib/src/core/sync/sync_outbox.dart` |
| UUID generation via `Uuid().v4()` | `lib/src/features/transactions/data/transaction_repository.dart` |

---

## Verification Plan

1. **Unit test `parseAndExtract`:** Feed a CSV string with mixed types (EXPENSE, INCOME, TRANSFER), verify CsvExtractionResult contains correct unique names and row count
2. **Unit test `buildInsertBatch`:** Feed rows + mapping, verify:
   - `amount_cents` is correctly rounded from decimals
   - TRANSFER generates exactly 2 maps with crossed `linked_transaction_id`
   - Tags are JSON-encoded as ID arrays
   - Outbox entries match transaction count (including both transfer legs)
3. **Integration test `insertBatch`:** Use in-memory sqflite, insert a batch, query `transactions` and `sync_outbox` tables to verify row counts and data integrity
4. **Edge cases:** Empty tags, null category, TRANSFER without destination_account (should error), invalid type value (should error), missing mapping key (should error with row number), duplicate account names in CSV
