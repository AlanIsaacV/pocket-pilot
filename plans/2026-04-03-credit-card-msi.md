# Credit Card MSI Support Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement end-to-end support for credit-card installment purchases (MSI) so budgets and dashboard liquidity reflect monthly cash-flow obligations instead of full purchase-month spikes.

**Architecture:** Extend the transaction contract with `installments_count`, enforce strict validation (`>= 1`) in backend/frontend mappings, and keep installment projection isolated in a dedicated `CreditCardOracle` domain unit. Integrate oracle output into dashboard safe-to-spend and update budget SQL to prorate installment impact by overlapping months.

**Tech Stack:** Flutter (Dart, sqflite RAW SQL, Provider, grpc), Go (gRPC, pgx, PostgreSQL), Protocol Buffers

**Spec:** `docs/superpowers/specs/2026-04-03-credit-card-msi-design.md`

---

## File Structure

| File | Action | Responsibility |
|---|---|---|
| `backend/migrations/001_initial_schema.sql` | Modify | Add `transactions.installments_count` baseline column in PostgreSQL |
| `frontend/assets/migrations/001.sql` | Modify | Add `transactions.installments_count` baseline column in SQLite |
| `proto/pocket_pilot/v1/transaction_service.proto` | Modify | Add `Transaction.installments_count = 17` |
| `backend/internal/gen/proto/pocket_pilot/v1/pocket_pilot/v1/transaction_service.pb.go` | Regenerate | Go protobuf messages/stubs |
| `frontend/lib/src/generated/pocket_pilot/v1/transaction_service.pb.dart` | Regenerate | Dart protobuf messages |
| `frontend/lib/src/generated/pocket_pilot/v1/transaction_service.pbgrpc.dart` | Regenerate | Dart gRPC client/server stubs |
| `backend/internal/transaction/validation.go` | Create | Strict transaction field validation for installments |
| `backend/internal/transaction/validation_test.go` | Create | Unit tests for strict installments validation |
| `backend/internal/transaction/repository.go` | Modify | Persist/read `installments_count` in SQL scans and upsert |
| `backend/internal/transaction/handler.go` | Modify | Proto/domain mapping + strict `installments_count` rejection |
| `frontend/lib/src/features/transactions/domain/transaction.dart` | Modify | Add `installmentsCount` to transaction domain model/mappers |
| `frontend/lib/src/features/transactions/data/transaction_repository.dart` | Modify | Carry `installments_count` in create/update payloads |
| `frontend/lib/src/features/transactions/data/transaction_remote_service.dart` | Modify | Send/read `installments_count` through gRPC |
| `frontend/test/transaction_installments_mapping_test.dart` | Create | Mapping and validation tests for `installments_count` |
| `frontend/lib/src/features/dashboard/domain/credit_card_account_cycle_dto.dart` | Create | Oracle input DTO for card cycle config |
| `frontend/lib/src/features/dashboard/domain/credit_card_movement_dto.dart` | Create | Oracle input DTO for credit-card transactions |
| `frontend/lib/src/features/dashboard/domain/credit_card_oracle.dart` | Create | Monthly gross/net card obligation engine |
| `frontend/test/credit_card_oracle_test.dart` | Create | Cycle/fallback/MSI/netting math tests |
| `frontend/lib/src/features/dashboard/data/dashboard_local_store.dart` | Modify | Read credit-card cycle + movement rows for oracle |
| `frontend/lib/src/features/dashboard/data/dashboard_repository.dart` | Modify | Subtract oracle net obligation from safe-to-spend |
| `frontend/test/dashboard_repository_credit_card_obligation_test.dart` | Create | Integration-style repository metric tests |
| `frontend/lib/src/features/budgets/data/budget_local_store.dart` | Modify | SQL month-overlap proration for MSI budget spend |
| `frontend/test/budget_installments_proration_test.dart` | Create | Installment proration math tests (month overlap/residuals) |
| `docs/context/.journal.md` | Modify | Session technical decision/implementation log |

---

### Task 1: Add Baseline Schema + Proto Contract for `installments_count`

**Files:**
- Modify: `backend/migrations/001_initial_schema.sql`
- Modify: `frontend/assets/migrations/001.sql`
- Modify: `proto/pocket_pilot/v1/transaction_service.proto`

- [ ] **Step 1: Add PostgreSQL baseline column**

```sql
-- backend/migrations/001_initial_schema.sql
CREATE TABLE transactions (
    id                    uuid PRIMARY KEY          DEFAULT gen_random_uuid(),
    user_id               uuid             NOT NULL,
    account_id            uuid             NOT NULL REFERENCES accounts (id),
    category_id           uuid REFERENCES categories (id),
    linked_transaction_id uuid,
    template_id           uuid REFERENCES transaction_templates (id),
    yield_id              uuid REFERENCES yield_configs (id),
    type                  transaction_type NOT NULL,
    amount_cents          BIGINT           NOT NULL,
    installments_count    INTEGER          NOT NULL DEFAULT 1,
    currency_code         TEXT             NOT NULL,
    status                TEXT             NOT NULL,
    tags                  TEXT[],
    description           TEXT             NOT NULL DEFAULT '',
    date                  DATE             NOT NULL,
    created_at            timestamptz      NOT NULL DEFAULT NOW(),
    updated_at            timestamptz      NOT NULL DEFAULT NOW(),
    deleted_at            timestamptz
);
```

- [ ] **Step 2: Add SQLite baseline column**

```sql
-- frontend/assets/migrations/001.sql
CREATE TABLE transactions (
    id                    TEXT PRIMARY KEY,
    account_id            TEXT     NOT NULL REFERENCES accounts (id),
    category_id           TEXT REFERENCES categories (id),
    linked_transaction_id TEXT,
    template_id           TEXT REFERENCES transaction_templates (id),
    yield_id              TEXT REFERENCES yield_configs (id),
    type                  TEXT     NOT NULL,
    amount_cents          BIGINT   NOT NULL,
    installments_count    INTEGER  NOT NULL DEFAULT 1,
    currency_code         TEXT     NOT NULL,
    status                TEXT     NOT NULL,
    tags                  TEXT,
    description           TEXT     NOT NULL DEFAULT '',
    date                  DATE     NOT NULL,
    created_at            DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at            DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    deleted_at            DATETIME
);
```

- [ ] **Step 3: Add proto field**

```proto
// proto/pocket_pilot/v1/transaction_service.proto
message Transaction {
  google.protobuf.Timestamp created_at = 1;
  google.protobuf.Timestamp updated_at = 2;
  google.protobuf.Timestamp deleted_at = 3;
  string id = 4;
  string account_id = 5;
  optional string category_id = 6;
  TransactionType type = 7;
  int64 amount_cents = 8;
  string currency_code = 9;
  string status = 10;
  repeated string tags = 11;
  string description = 12;
  google.protobuf.Timestamp date = 13;
  optional string linked_transaction_id = 14;
  optional string template_id = 15;
  optional string yield_id = 16;
  int32 installments_count = 17;
}
```

- [ ] **Step 4: Regenerate protobuf code**

Run: `cd /Volumes/rusty-drive/projects/pocket-pilot && make proto`

Expected: `✓ Done. Generated files:` and no protoc errors.

- [ ] **Step 5: Compile gates after contract change**

Run: `cd /Volumes/rusty-drive/projects/pocket-pilot/backend && go test ./...`

Expected: backend compiles cleanly.

Run: `cd /Volumes/rusty-drive/projects/pocket-pilot/frontend && flutter analyze`

Expected: no new errors caused by generated API updates.

- [ ] **Step 6: Commit**

```bash
cd /Volumes/rusty-drive/projects/pocket-pilot
git add backend/migrations/001_initial_schema.sql frontend/assets/migrations/001.sql proto/pocket_pilot/v1/transaction_service.proto backend/internal/gen frontend/lib/src/generated
git commit -m "feat(transaction): add installments_count to schema and proto"
```

---

### Task 2: Enforce Strict Backend Validation and Persistence (TDD)

**Files:**
- Create: `backend/internal/transaction/validation_test.go`
- Create: `backend/internal/transaction/validation.go`
- Modify: `backend/internal/transaction/handler.go`
- Modify: `backend/internal/transaction/repository.go`

- [ ] **Step 1: Write failing backend tests first**

```go
// backend/internal/transaction/validation_test.go
package transaction

import (
    "testing"
    "time"

    "github.com/google/uuid"
    pb "github.com/AlanIsaacV/pocket-pilot/internal/gen/proto/pocket_pilot/v1/pocket_pilot/v1"
    "google.golang.org/grpc/codes"
    "google.golang.org/grpc/status"
    "google.golang.org/protobuf/types/known/timestamppb"
)

func TestValidateInstallmentsCount(t *testing.T) {
    tests := []struct {
        name    string
        value   int32
        wantErr bool
    }{
        {name: "one installment", value: 1, wantErr: false},
        {name: "twelve installments", value: 12, wantErr: false},
        {name: "zero invalid", value: 0, wantErr: true},
        {name: "negative invalid", value: -3, wantErr: true},
    }

    for _, tc := range tests {
        tc := tc
        t.Run(tc.name, func(t *testing.T) {
            err := validateInstallmentsCount(tc.value)
            if tc.wantErr && err == nil {
                t.Fatalf("expected error")
            }
            if !tc.wantErr && err != nil {
                t.Fatalf("unexpected error: %v", err)
            }
        })
    }
}

func TestFromProtoRejectsInstallmentsCountLessThanOne(t *testing.T) {
    now := time.Date(2026, 4, 3, 0, 0, 0, 0, time.UTC)
    tx := &pb.Transaction{
        Id:                uuid.NewString(),
        AccountId:         uuid.NewString(),
        Type:              pb.TransactionType_TRANSACTION_TYPE_EXPENSE,
        AmountCents:       1000,
        InstallmentsCount: 0,
        CurrencyCode:      "MXN",
        Status:            "cleared",
        Description:       "Compra",
        Date:              timestamppb.New(now),
        CreatedAt:         timestamppb.New(now),
        UpdatedAt:         timestamppb.New(now),
    }

    _, err := fromProto(tx, uuid.New())
    if err == nil {
        t.Fatalf("expected invalid argument error")
    }

    st, ok := status.FromError(err)
    if !ok {
        t.Fatalf("expected grpc status error")
    }
    if st.Code() != codes.InvalidArgument {
        t.Fatalf("expected InvalidArgument, got %s", st.Code())
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Volumes/rusty-drive/projects/pocket-pilot/backend && go test ./internal/transaction -run "TestValidateInstallmentsCount|TestFromProtoRejectsInstallmentsCountLessThanOne" -v`

Expected: FAIL (missing validation helper and mapping updates).

- [ ] **Step 3: Implement strict validation helper**

```go
// backend/internal/transaction/validation.go
package transaction

import "fmt"

func validateInstallmentsCount(value int32) error {
    if value < 1 {
        return fmt.Errorf("transaction.installments_count must be >= 1")
    }
    return nil
}
```

- [ ] **Step 4: Wire validation + mapping in handler**

```go
// backend/internal/transaction/handler.go
func toProto(t *Transaction) *pb.Transaction {
    proto := &pb.Transaction{
        Id:                t.ID.String(),
        AccountId:         t.AccountID.String(),
        Type:              stringToTransactionType(t.Type),
        AmountCents:       t.AmountCents,
        InstallmentsCount: t.InstallmentsCount,
        CurrencyCode:      t.CurrencyCode,
        Status:            t.Status,
        Tags:              t.Tags,
        Description:       t.Description,
        Date:              timestamppb.New(t.Date),
        CreatedAt:         timestamppb.New(t.CreatedAt),
        UpdatedAt:         timestamppb.New(t.UpdatedAt),
    }
    // ...existing optional field mapping unchanged...
    return proto
}

func fromProto(p *pb.Transaction, userID uuid.UUID) (*Transaction, error) {
    // ...existing parsing...
    if err := validateInstallmentsCount(p.InstallmentsCount); err != nil {
        return nil, status.Error(codes.InvalidArgument, err.Error())
    }

    // ...existing date parsing...
    return &Transaction{
        ID:                  id,
        UserID:              userID,
        AccountID:           accountID,
        CategoryID:          categoryID,
        LinkedTransactionID: linkedID,
        TemplateID:          templateID,
        YieldID:             yieldID,
        Type:                transactionTypeToString(p.Type),
        AmountCents:         p.AmountCents,
        InstallmentsCount:   p.InstallmentsCount,
        CurrencyCode:        p.CurrencyCode,
        Status:              p.Status,
        Tags:                p.Tags,
        Description:         p.Description,
        Date:                date,
        CreatedAt:           p.CreatedAt.AsTime(),
        UpdatedAt:           p.UpdatedAt.AsTime(),
    }, nil
}
```

- [ ] **Step 5: Persist field in repository SQL + scans**

```go
// backend/internal/transaction/repository.go
type Transaction struct {
    ID                  uuid.UUID
    UserID              uuid.UUID
    AccountID           uuid.UUID
    CategoryID          *uuid.UUID
    LinkedTransactionID *uuid.UUID
    TemplateID          *uuid.UUID
    YieldID             *uuid.UUID
    Type                string
    AmountCents         int64
    InstallmentsCount   int32
    CurrencyCode        string
    Status              string
    Tags                []string
    Description         string
    Date                time.Time
    CreatedAt           time.Time
    UpdatedAt           time.Time
    DeletedAt           *time.Time
}

const scanColumns = `id, user_id, account_id, category_id, linked_transaction_id, template_id, yield_id, type, amount_cents, installments_count, currency_code, status, tags, description, date, created_at, updated_at, deleted_at`

// in scans:
// &t.Type, &t.AmountCents, &t.InstallmentsCount, &t.CurrencyCode, &t.Status,

// in upsert SQL:
// INSERT INTO transactions (..., amount_cents, installments_count, currency_code, ...)
// VALUES (..., $9, $10, $11, ...)
// ON CONFLICT (id) DO UPDATE SET
//   installments_count = EXCLUDED.installments_count,

// and argument list includes t.InstallmentsCount between amount and currency.
```

- [ ] **Step 6: Run backend tests**

Run: `cd /Volumes/rusty-drive/projects/pocket-pilot/backend && go test ./internal/transaction -v`

Expected: PASS for new validation tests.

Run: `cd /Volumes/rusty-drive/projects/pocket-pilot/backend && go test ./...`

Expected: full backend suite passes.

- [ ] **Step 7: Commit**

```bash
cd /Volumes/rusty-drive/projects/pocket-pilot
git add backend/internal/transaction/validation_test.go backend/internal/transaction/validation.go backend/internal/transaction/handler.go backend/internal/transaction/repository.go
git commit -m "feat(back-transaction): enforce and persist installments_count"
```

---

### Task 3: Add Frontend Transaction Mapping + Payload Support (TDD)

**Files:**
- Create: `frontend/test/transaction_installments_mapping_test.dart`
- Modify: `frontend/lib/src/features/transactions/domain/transaction.dart`
- Modify: `frontend/lib/src/features/transactions/data/transaction_repository.dart`
- Modify: `frontend/lib/src/features/transactions/data/transaction_remote_service.dart`

- [ ] **Step 1: Write failing frontend mapping tests**

```dart
// frontend/test/transaction_installments_mapping_test.dart
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Volumes/rusty-drive/projects/pocket-pilot/frontend && flutter test test/transaction_installments_mapping_test.dart`

Expected: FAIL (model/repository/remote not updated yet).

- [ ] **Step 3: Implement domain mapping and strict invariant**

```dart
// frontend/lib/src/features/transactions/domain/transaction.dart
class TransactionModel {
  final String id;
  final String accountId;
  final String? categoryId;
  final String? linkedTransactionId;
  final String? templateId;
  final String? yieldId;
  final int amount;
  final int installmentsCount;
  final String currencyCode;
  final String description;
  final String date;
  final String type;
  final String status;
  final List<String> tags;
  final DateTime createdAt;
  final DateTime updatedAt;

  TransactionModel({
    required this.id,
    required this.accountId,
    this.categoryId,
    this.linkedTransactionId,
    this.templateId,
    this.yieldId,
    required this.amount,
    required int installmentsCount,
    required this.currencyCode,
    required this.description,
    required this.date,
    required this.type,
    required this.status,
    required this.tags,
    required this.createdAt,
    required this.updatedAt,
  }) : installmentsCount = _ensureInstallmentsCount(installmentsCount);

  factory TransactionModel.fromProto(Transaction proto) {
    return TransactionModel(
      id: proto.id,
      accountId: proto.accountId,
      categoryId: proto.hasCategoryId() ? proto.categoryId : null,
      linkedTransactionId:
          proto.hasLinkedTransactionId() ? proto.linkedTransactionId : null,
      templateId: proto.hasTemplateId() ? proto.templateId : null,
      yieldId: proto.hasYieldId() ? proto.yieldId : null,
      amount: proto.amountCents.toInt(),
      installmentsCount: proto.installmentsCount,
      currencyCode: proto.currencyCode,
      description: proto.description,
      date: proto.date.toDateTime().toIso8601String().substring(0, 10),
      type: _transactionTypeToString(proto.type),
      status: proto.status,
      tags: List<String>.from(proto.tags),
      createdAt: proto.createdAt.toDateTime(),
      updatedAt: proto.updatedAt.toDateTime(),
    );
  }

  factory TransactionModel.fromMap(Map<String, dynamic> map) {
    return TransactionModel(
      id: map['id'] as String,
      accountId: map['account_id'] as String,
      categoryId: map['category_id'] as String?,
      linkedTransactionId: map['linked_transaction_id'] as String?,
      templateId: map['template_id'] as String?,
      yieldId: map['yield_id'] as String?,
      amount: map['amount_cents'] as int,
      installmentsCount: map['installments_count'] as int,
      currencyCode: map['currency_code'] as String,
      description: map['description'] as String,
      date: map['date'] as String,
      type: map['type'] as String,
      status: map['status'] as String,
      tags: _decodeTags(map['tags']),
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'account_id': accountId,
      'category_id': categoryId,
      'linked_transaction_id': linkedTransactionId,
      'template_id': templateId,
      'yield_id': yieldId,
      'amount_cents': amount,
      'installments_count': installmentsCount,
      'currency_code': currencyCode,
      'tags': jsonEncode(tags),
      'description': description,
      'date': date,
      'type': type,
      'status': status,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  Map<String, dynamic> toServerMap() {
    return {
      'id': id,
      'account_id': accountId,
      'category_id': categoryId,
      'linked_transaction_id': linkedTransactionId,
      'template_id': templateId,
      'yield_id': yieldId,
      'amount_cents': amount,
      'installments_count': installmentsCount,
      'currency_code': currencyCode,
      'tags': tags,
      'description': description,
      'date': date,
      'type': type,
      'status': status,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  static int _ensureInstallmentsCount(int value) {
    if (value < 1) {
      throw ArgumentError.value(
        value,
        'installmentsCount',
        'installmentsCount must be >= 1',
      );
    }
    return value;
  }
}
```

- [ ] **Step 4: Update repository and remote payload mapping**

```dart
// frontend/lib/src/features/transactions/data/transaction_repository.dart
Future<void> createTransaction({
  required String id,
  required String accountId,
  required String? categoryId,
  String? templateId,
  required int amountMinor,
  int installmentsCount = 1,
  required String currencyCode,
  required String description,
  required String date,
  required String type,
  required String status,
  required List<String> tags,
}) async {
  final now = DateTime.now().toUtc();
  final model = TransactionModel(
    id: id,
    accountId: accountId,
    categoryId: categoryId,
    templateId: templateId,
    amount: amountMinor,
    installmentsCount: installmentsCount,
    currencyCode: currencyCode,
    description: description,
    date: date,
    type: type,
    status: status,
    tags: tags,
    createdAt: now,
    updatedAt: now,
  );
  // ...existing save + outbox...
}

Future<void> updateTransaction({
  required String id,
  required String accountId,
  required String? categoryId,
  String? templateId,
  required int amountMinor,
  int installmentsCount = 1,
  required String currencyCode,
  required String description,
  required String date,
  required String type,
  required String status,
  required List<String> tags,
  required DateTime createdAt,
}) async {
  final model = TransactionModel(
    id: id,
    accountId: accountId,
    categoryId: categoryId,
    templateId: templateId,
    amount: amountMinor,
    installmentsCount: installmentsCount,
    currencyCode: currencyCode,
    description: description,
    date: date,
    type: type,
    status: status,
    tags: tags,
    createdAt: createdAt,
    updatedAt: DateTime.now().toUtc(),
  );
  // ...existing save + outbox...
}

// transfer legs remain fixed one-shot
installmentsCount: 1,
```

```dart
// frontend/lib/src/features/transactions/data/transaction_remote_service.dart
Future<UpsertTransactionResponse> upsertTransaction(
  Map<String, dynamic> map,
) async {
  final installmentsCount = (map['installments_count'] as int?) ?? 1;
  if (installmentsCount < 1) {
    throw ArgumentError.value(
      installmentsCount,
      'installments_count',
      'installments_count must be >= 1',
    );
  }

  final transaction = Transaction(
    id: map['id'] as String,
    accountId: map['account_id'] as String,
    type: TransactionModel.stringToTransactionType(map['type'] as String),
    amountCents: Int64(map['amount_cents'] as int),
    installmentsCount: installmentsCount,
    currencyCode: map['currency_code'] as String,
    status: map['status'] as String? ?? 'cleared',
    tags: _toTags(map['tags']),
    description: map['description'] as String,
    date: Timestamp.fromDateTime(DateTime.parse(map['date'] as String).toUtc()),
    updatedAt: Timestamp.fromDateTime(
      map['updated_at'] != null
          ? DateTime.parse(map['updated_at'] as String).toUtc()
          : DateTime.now().toUtc(),
    ),
  );
  // ...existing optional field mapping and RPC...
}
```

- [ ] **Step 5: Run frontend tests and analyze**

Run: `cd /Volumes/rusty-drive/projects/pocket-pilot/frontend && flutter test test/transaction_installments_mapping_test.dart`

Expected: PASS.

Run: `cd /Volumes/rusty-drive/projects/pocket-pilot/frontend && flutter analyze lib/src/features/transactions`

Expected: no analyzer errors in transaction feature files.

- [ ] **Step 6: Commit**

```bash
cd /Volumes/rusty-drive/projects/pocket-pilot
git add frontend/test/transaction_installments_mapping_test.dart frontend/lib/src/features/transactions/domain/transaction.dart frontend/lib/src/features/transactions/data/transaction_repository.dart frontend/lib/src/features/transactions/data/transaction_remote_service.dart
git commit -m "feat(front-transaction): add installments_count mapping and payload support"
```

---

### Task 4: Implement `CreditCardOracle` Monthly Projection Engine (TDD)

**Files:**
- Create: `frontend/test/credit_card_oracle_test.dart`
- Create: `frontend/lib/src/features/dashboard/domain/credit_card_account_cycle_dto.dart`
- Create: `frontend/lib/src/features/dashboard/domain/credit_card_movement_dto.dart`
- Create: `frontend/lib/src/features/dashboard/domain/credit_card_oracle.dart`

- [ ] **Step 1: Write failing oracle tests first**

```dart
// frontend/test/credit_card_oracle_test.dart
import 'package:flutter_test/flutter_test.dart';

import 'package:pocket_pilot/src/features/dashboard/domain/credit_card_account_cycle_dto.dart';
import 'package:pocket_pilot/src/features/dashboard/domain/credit_card_movement_dto.dart';
import 'package:pocket_pilot/src/features/dashboard/domain/credit_card_oracle.dart';

void main() {
  test('cycle mode includes one-shot + MSI and nets applied payments', () {
    final oracle = CreditCardOracle();
    final result = oracle.estimateNetMonthlyObligation(
      targetMonth: DateTime.utc(2026, 5, 1),
      now: DateTime.utc(2026, 5, 4),
      accounts: const [
        CreditCardAccountCycleDTO(
          accountId: 'card-1',
          currencyCode: 'MXN',
          statementDay: 20,
          paymentDueDay: 5,
        ),
      ],
      movements: const [
        CreditCardMovementDTO(
          accountId: 'card-1',
          type: 'expense',
          amountCents: 30000,
          installmentsCount: 1,
          date: '2026-04-10',
        ),
        CreditCardMovementDTO(
          accountId: 'card-1',
          type: 'expense',
          amountCents: 12000,
          installmentsCount: 3,
          date: '2026-04-15',
        ),
        CreditCardMovementDTO(
          accountId: 'card-1',
          type: 'transfer_in',
          amountCents: 2000,
          installmentsCount: 1,
          date: '2026-05-02',
        ),
      ],
    );

    expect(result.netByCurrency['MXN'], 32000);
    expect(result.netByAccountId['card-1'], 32000);
  });

  test('residual goes to first installment only', () {
    final oracle = CreditCardOracle();
    final accounts = const [
      CreditCardAccountCycleDTO(
        accountId: 'card-1',
        currencyCode: 'MXN',
        statementDay: 20,
        paymentDueDay: 5,
      ),
    ];
    const movements = [
      CreditCardMovementDTO(
        accountId: 'card-1',
        type: 'expense',
        amountCents: 1000,
        installmentsCount: 3,
        date: '2026-04-15',
      ),
    ];

    final may = oracle.estimateNetMonthlyObligation(
      targetMonth: DateTime.utc(2026, 5, 1),
      now: DateTime.utc(2026, 5, 3),
      accounts: accounts,
      movements: movements,
    );
    final jun = oracle.estimateNetMonthlyObligation(
      targetMonth: DateTime.utc(2026, 6, 1),
      now: DateTime.utc(2026, 6, 3),
      accounts: accounts,
      movements: movements,
    );

    expect(may.netByCurrency['MXN'], 334);
    expect(jun.netByCurrency['MXN'], 333);
  });

  test('fallback mode uses calendar and floors net at zero', () {
    final oracle = CreditCardOracle();
    final result = oracle.estimateNetMonthlyObligation(
      targetMonth: DateTime.utc(2026, 6, 1),
      now: DateTime.utc(2026, 6, 10),
      accounts: const [
        CreditCardAccountCycleDTO(
          accountId: 'card-2',
          currencyCode: 'USD',
          statementDay: null,
          paymentDueDay: null,
        ),
      ],
      movements: const [
        CreditCardMovementDTO(
          accountId: 'card-2',
          type: 'expense',
          amountCents: 4000,
          installmentsCount: 1,
          date: '2026-05-12',
        ),
        CreditCardMovementDTO(
          accountId: 'card-2',
          type: 'expense',
          amountCents: 1001,
          installmentsCount: 2,
          date: '2026-05-15',
        ),
        CreditCardMovementDTO(
          accountId: 'card-2',
          type: 'income',
          amountCents: 6000,
          installmentsCount: 1,
          date: '2026-06-03',
        ),
      ],
    );

    expect(result.netByCurrency['USD'], 0);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Volumes/rusty-drive/projects/pocket-pilot/frontend && flutter test test/credit_card_oracle_test.dart`

Expected: FAIL because oracle and DTO files do not exist.

- [ ] **Step 3: Implement oracle input DTOs**

```dart
// frontend/lib/src/features/dashboard/domain/credit_card_account_cycle_dto.dart
class CreditCardAccountCycleDTO {
  final String accountId;
  final String currencyCode;
  final int? statementDay;
  final int? paymentDueDay;

  const CreditCardAccountCycleDTO({
    required this.accountId,
    required this.currencyCode,
    required this.statementDay,
    required this.paymentDueDay,
  });

  factory CreditCardAccountCycleDTO.fromMap(Map<String, dynamic> map) {
    return CreditCardAccountCycleDTO(
      accountId: map['account_id'] as String,
      currencyCode: map['currency_code'] as String,
      statementDay: map['statement_day'] as int?,
      paymentDueDay: map['payment_due_day'] as int?,
    );
  }
}
```

```dart
// frontend/lib/src/features/dashboard/domain/credit_card_movement_dto.dart
class CreditCardMovementDTO {
  final String accountId;
  final String type;
  final int amountCents;
  final int installmentsCount;
  final String date;

  const CreditCardMovementDTO({
    required this.accountId,
    required this.type,
    required this.amountCents,
    required this.installmentsCount,
    required this.date,
  });

  factory CreditCardMovementDTO.fromMap(Map<String, dynamic> map) {
    return CreditCardMovementDTO(
      accountId: map['account_id'] as String,
      type: map['type'] as String,
      amountCents: (map['amount_cents'] as num).toInt(),
      installmentsCount: (map['installments_count'] as num).toInt(),
      date: map['date'] as String,
    );
  }
}
```

- [ ] **Step 4: Implement `CreditCardOracle`**

```dart
// frontend/lib/src/features/dashboard/domain/credit_card_oracle.dart
import 'package:pocket_pilot/src/features/dashboard/domain/credit_card_account_cycle_dto.dart';
import 'package:pocket_pilot/src/features/dashboard/domain/credit_card_movement_dto.dart';

class CreditCardOracleResult {
  final Map<String, int> netByCurrency;
  final Map<String, int> netByAccountId;

  const CreditCardOracleResult({
    required this.netByCurrency,
    required this.netByAccountId,
  });
}

class CreditCardOracle {
  CreditCardOracleResult estimateNetMonthlyObligation({
    required DateTime targetMonth,
    required List<CreditCardAccountCycleDTO> accounts,
    required List<CreditCardMovementDTO> movements,
    DateTime? now,
  }) {
    final month = DateTime.utc(targetMonth.year, targetMonth.month, 1);
    final nowUtc = (now ?? DateTime.now()).toUtc();

    final byAccount = <String, List<CreditCardMovementDTO>>{};
    for (final m in movements) {
      byAccount.putIfAbsent(m.accountId, () => <CreditCardMovementDTO>[]).add(m);
    }

    final netByAccountId = <String, int>{};
    final netByCurrency = <String, int>{};

    for (final account in accounts) {
      final rows = byAccount[account.accountId] ?? const <CreditCardMovementDTO>[];
      final net = _estimateForAccount(
        account: account,
        movements: rows,
        month: month,
        nowUtc: nowUtc,
      );
      netByAccountId[account.accountId] = net;
      netByCurrency[account.currencyCode] =
          (netByCurrency[account.currencyCode] ?? 0) + net;
    }

    return CreditCardOracleResult(
      netByCurrency: netByCurrency,
      netByAccountId: netByAccountId,
    );
  }

  int _estimateForAccount({
    required CreditCardAccountCycleDTO account,
    required List<CreditCardMovementDTO> movements,
    required DateTime month,
    required DateTime nowUtc,
  }) {
    if ((account.statementDay ?? 0) < 1 || (account.paymentDueDay ?? 0) < 1) {
      return _estimateFallbackCalendar(
        movements: movements,
        month: month,
        nowUtc: nowUtc,
      );
    }
    return _estimateWithCycle(
      movements: movements,
      month: month,
      nowUtc: nowUtc,
      statementDay: account.statementDay!,
      paymentDueDay: account.paymentDueDay!,
    );
  }

  int _estimateWithCycle({
    required List<CreditCardMovementDTO> movements,
    required DateTime month,
    required DateTime nowUtc,
    required int statementDay,
    required int paymentDueDay,
  }) {
    final dueDate = _clampedDate(month.year, month.month, paymentDueDay);
    final closeCurr = _latestCloseOnOrBefore(dueDate, statementDay);
    final closePrevMonth = _addMonths(closeCurr, -1);
    final closePrev =
        _clampedDate(closePrevMonth.year, closePrevMonth.month, statementDay);

    var gross = 0;
    for (final m in movements) {
      if (!_isCharge(m.type)) continue;
      final txDate = DateTime.parse(m.date).toUtc();

      if (m.installmentsCount == 1) {
        if (txDate.isAfter(closePrev) && !txDate.isAfter(closeCurr)) {
          gross += m.amountCents;
        }
        continue;
      }

      final purchaseClose = _firstCloseOnOrAfter(txDate, statementDay);
      final k = _monthIndex(closeCurr) - _monthIndex(purchaseClose);
      if (k >= 0 && k < m.installmentsCount) {
        gross += _installmentAmount(
          amountCents: m.amountCents,
          installmentsCount: m.installmentsCount,
          installmentIndex: k,
        );
      }
    }

    final monthStart = DateTime.utc(month.year, month.month, 1);
    final paymentWindowEnd = nowUtc.isBefore(dueDate) ? nowUtc : dueDate;
    var payments = 0;
    if (!paymentWindowEnd.isBefore(monthStart)) {
      for (final m in movements) {
        if (!_isPayment(m.type)) continue;
        final txDate = DateTime.parse(m.date).toUtc();
        final inWindow =
            (!txDate.isBefore(monthStart)) && (!txDate.isAfter(paymentWindowEnd));
        if (inWindow) {
          payments += m.amountCents;
        }
      }
    }

    final net = gross - payments;
    return net > 0 ? net : 0;
  }

  int _estimateFallbackCalendar({
    required List<CreditCardMovementDTO> movements,
    required DateTime month,
    required DateTime nowUtc,
  }) {
    final prev = _addMonths(month, -1);
    final prevStart = DateTime.utc(prev.year, prev.month, 1);
    final prevEnd = DateTime.utc(prev.year, prev.month, _lastDayOfMonth(prev.year, prev.month));

    var gross = 0;
    for (final m in movements) {
      if (!_isCharge(m.type)) continue;
      final txDate = DateTime.parse(m.date).toUtc();

      if (m.installmentsCount == 1) {
        final inPrevMonth =
            !txDate.isBefore(prevStart) && !txDate.isAfter(prevEnd);
        if (inPrevMonth) {
          gross += m.amountCents;
        }
        continue;
      }

      final firstDueMonth = _addMonths(DateTime.utc(txDate.year, txDate.month, 1), 1);
      final k = _monthIndex(month) - _monthIndex(firstDueMonth);
      if (k >= 0 && k < m.installmentsCount) {
        gross += _installmentAmount(
          amountCents: m.amountCents,
          installmentsCount: m.installmentsCount,
          installmentIndex: k,
        );
      }
    }

    final monthStart = DateTime.utc(month.year, month.month, 1);
    final monthEnd = DateTime.utc(month.year, month.month, _lastDayOfMonth(month.year, month.month));
    final paymentWindowEnd = nowUtc.isBefore(monthEnd) ? nowUtc : monthEnd;

    var payments = 0;
    if (!paymentWindowEnd.isBefore(monthStart)) {
      for (final m in movements) {
        if (!_isPayment(m.type)) continue;
        final txDate = DateTime.parse(m.date).toUtc();
        final inWindow =
            !txDate.isBefore(monthStart) && !txDate.isAfter(paymentWindowEnd);
        if (inWindow) {
          payments += m.amountCents;
        }
      }
    }

    final net = gross - payments;
    return net > 0 ? net : 0;
  }

  DateTime _latestCloseOnOrBefore(DateTime date, int statementDay) {
    final closeThisMonth = _clampedDate(date.year, date.month, statementDay);
    if (!closeThisMonth.isAfter(date)) return closeThisMonth;
    final prev = _addMonths(date, -1);
    return _clampedDate(prev.year, prev.month, statementDay);
  }

  DateTime _firstCloseOnOrAfter(DateTime txDate, int statementDay) {
    final closeThisMonth = _clampedDate(txDate.year, txDate.month, statementDay);
    if (!txDate.isAfter(closeThisMonth)) return closeThisMonth;
    final next = _addMonths(txDate, 1);
    return _clampedDate(next.year, next.month, statementDay);
  }

  static bool _isCharge(String type) => type == 'expense' || type == 'transfer_out';
  static bool _isPayment(String type) => type == 'income' || type == 'transfer_in';

  static int _installmentAmount({
    required int amountCents,
    required int installmentsCount,
    required int installmentIndex,
  }) {
    final base = amountCents ~/ installmentsCount;
    final residual = amountCents % installmentsCount;
    return installmentIndex == 0 ? base + residual : base;
  }

  static DateTime _clampedDate(int year, int month, int requestedDay) {
    final lastDay = _lastDayOfMonth(year, month);
    final day = requestedDay > lastDay ? lastDay : requestedDay;
    return DateTime.utc(year, month, day);
  }

  static DateTime _addMonths(DateTime date, int delta) {
    final monthBase = date.month + delta;
    final year = date.year + ((monthBase - 1) ~/ 12);
    final month = ((monthBase - 1) % 12) + 1;
    final lastDay = _lastDayOfMonth(year, month);
    final day = date.day > lastDay ? lastDay : date.day;
    return DateTime.utc(year, month, day);
  }

  static int _lastDayOfMonth(int year, int month) => DateTime.utc(year, month + 1, 0).day;
  static int _monthIndex(DateTime d) => d.year * 12 + (d.month - 1);
}
```

- [ ] **Step 5: Run oracle tests**

Run: `cd /Volumes/rusty-drive/projects/pocket-pilot/frontend && flutter test test/credit_card_oracle_test.dart`

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
cd /Volumes/rusty-drive/projects/pocket-pilot
git add frontend/test/credit_card_oracle_test.dart frontend/lib/src/features/dashboard/domain/credit_card_account_cycle_dto.dart frontend/lib/src/features/dashboard/domain/credit_card_movement_dto.dart frontend/lib/src/features/dashboard/domain/credit_card_oracle.dart
git commit -m "feat(front-dashboard): add credit card oracle for monthly net obligation"
```

---

### Task 5: Integrate Oracle into Dashboard Metrics (TDD)

**Files:**
- Create: `frontend/test/dashboard_repository_credit_card_obligation_test.dart`
- Modify: `frontend/lib/src/features/dashboard/data/dashboard_local_store.dart`
- Modify: `frontend/lib/src/features/dashboard/data/dashboard_repository.dart`

- [ ] **Step 1: Write failing repository integration test**

```dart
// frontend/test/dashboard_repository_credit_card_obligation_test.dart
import 'package:flutter_test/flutter_test.dart';

import 'package:pocket_pilot/src/core/db/database_helper.dart';
import 'package:pocket_pilot/src/features/dashboard/data/dashboard_local_store.dart';
import 'package:pocket_pilot/src/features/dashboard/data/dashboard_repository.dart';
import 'package:pocket_pilot/src/features/dashboard/domain/account_balance_dto.dart';
import 'package:pocket_pilot/src/features/dashboard/domain/credit_card_account_cycle_dto.dart';
import 'package:pocket_pilot/src/features/dashboard/domain/credit_card_movement_dto.dart';
import 'package:pocket_pilot/src/features/dashboard/domain/goal_target_dto.dart';

void main() {
  test('safe_to_spend subtracts net card obligation', () async {
    final local = _FakeDashboardLocalStore();
    final repository = DashboardRepository(
      local: local,
      nowProvider: () => DateTime.utc(2026, 5, 4),
    );

    final metricsByCurrency = await repository.calculateAllMetrics();
    final mxn = metricsByCurrency['MXN']!;

    expect(mxn.liquidAssetsCents, 100000);
    expect(mxn.safeToSpendCents, 50000); // 100000 - 20000 goals - 30000 card net
    expect(mxn.buyingPowerCents, 90000); // safe 50000 + revolving 40000
  });
}

class _FakeDashboardLocalStore extends DashboardLocalStore {
  _FakeDashboardLocalStore() : super(db: DatabaseHelper());

  @override
  Future<List<AccountBalanceDTO>> getBalancesPerAccount({Set<String>? accountIds}) async {
    return const [
      AccountBalanceDTO(
        accountId: 'bank-1',
        accountName: 'Bank',
        accountType: 'bank',
        currencyCode: 'MXN',
        balanceCents: 100000,
      ),
      AccountBalanceDTO(
        accountId: 'card-1',
        accountName: 'Card',
        accountType: 'credit_card',
        currencyCode: 'MXN',
        balanceCents: -10000,
        creditLimitCents: 50000,
      ),
    ];
  }

  @override
  Future<List<GoalTargetDTO>> getTotalTargetInGoals() async {
    return const [GoalTargetDTO(currencyCode: 'MXN', totalTargetCents: 20000)];
  }

  @override
  Future<List<CreditCardAccountCycleDTO>> getCreditCardAccounts({Set<String>? accountIds}) async {
    return const [
      CreditCardAccountCycleDTO(
        accountId: 'card-1',
        currencyCode: 'MXN',
        statementDay: 20,
        paymentDueDay: 5,
      ),
    ];
  }

  @override
  Future<List<CreditCardMovementDTO>> getCreditCardMovementsForProjection(
    String maxDate, {
    Set<String>? accountIds,
    String? currencyCode,
  }) async {
    return const [
      CreditCardMovementDTO(
        accountId: 'card-1',
        type: 'expense',
        amountCents: 28000,
        installmentsCount: 1,
        date: '2026-04-10',
      ),
      CreditCardMovementDTO(
        accountId: 'card-1',
        type: 'expense',
        amountCents: 6000,
        installmentsCount: 3,
        date: '2026-04-15',
      ),
      CreditCardMovementDTO(
        accountId: 'card-1',
        type: 'transfer_in',
        amountCents: 0,
        installmentsCount: 1,
        date: '2026-05-02',
      ),
    ];
  }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Volumes/rusty-drive/projects/pocket-pilot/frontend && flutter test test/dashboard_repository_credit_card_obligation_test.dart`

Expected: FAIL (missing local store methods and repository integration).

- [ ] **Step 3: Add local-store read methods for oracle input**

```dart
// frontend/lib/src/features/dashboard/data/dashboard_local_store.dart
Future<List<CreditCardAccountCycleDTO>> getCreditCardAccounts({
  Set<String>? accountIds,
}) async {
  final db = await _db.database;
  final where = StringBuffer("deleted_at IS NULL AND type = 'credit_card'");
  final args = <dynamic>[];

  if (accountIds != null && accountIds.isNotEmpty) {
    final placeholders = List.filled(accountIds.length, '?').join(',');
    where.write(' AND id IN ($placeholders)');
    args.addAll(accountIds);
  }

  final rows = await db.rawQuery('''
    SELECT
      id AS account_id,
      currency_code,
      statement_day,
      payment_due_day
    FROM accounts
    WHERE ${where.toString()}
  ''', args);

  return rows.map(CreditCardAccountCycleDTO.fromMap).toList();
}

Future<List<CreditCardMovementDTO>> getCreditCardMovementsForProjection(
  String maxDate, {
  Set<String>? accountIds,
  String? currencyCode,
}) async {
  final db = await _db.database;
  final where = StringBuffer(
    "t.deleted_at IS NULL"
    " AND t.status = 'cleared'"
    " AND a.deleted_at IS NULL"
    " AND a.type = 'credit_card'"
    " AND t.type IN ('expense', 'transfer_out', 'income', 'transfer_in')"
    ' AND t.date <= ?',
  );
  final args = <dynamic>[maxDate];

  if (accountIds != null && accountIds.isNotEmpty) {
    final placeholders = List.filled(accountIds.length, '?').join(',');
    where.write(' AND t.account_id IN ($placeholders)');
    args.addAll(accountIds);
  }

  if (currencyCode != null) {
    where.write(' AND a.currency_code = ?');
    args.add(currencyCode);
  }

  final rows = await db.rawQuery('''
    SELECT
      t.account_id,
      t.type,
      t.amount_cents,
      t.installments_count,
      t.date
    FROM transactions t
    INNER JOIN accounts a ON a.id = t.account_id
    WHERE ${where.toString()}
    ORDER BY t.date ASC
  ''', args);

  return rows.map(CreditCardMovementDTO.fromMap).toList();
}
```

- [ ] **Step 4: Integrate oracle in repository formula**

```dart
// frontend/lib/src/features/dashboard/data/dashboard_repository.dart
import 'package:pocket_pilot/src/features/dashboard/domain/credit_card_oracle.dart';

class DashboardRepository {
  final DashboardLocalStore _local;
  final CreditCardOracle _oracle;
  final DateTime Function() _nowProvider;

  DashboardRepository({
    required DashboardLocalStore local,
    CreditCardOracle? oracle,
    DateTime Function()? nowProvider,
  })  : _local = local,
        _oracle = oracle ?? CreditCardOracle(),
        _nowProvider = nowProvider ?? DateTime.now;

  Future<Map<String, DashboardMetrics>> calculateAllMetrics({
    Set<String>? accountIds,
  }) async {
    final balances = await _local.getBalancesPerAccount(accountIds: accountIds);
    final goalTargets = await _local.getTotalTargetInGoals();

    final now = _nowProvider().toUtc();
    final month = DateTime.utc(now.year, now.month, 1);
    final monthEnd = DateTime.utc(now.year, now.month + 1, 0);
    final maxDate =
        '${monthEnd.year.toString().padLeft(4, '0')}-${monthEnd.month.toString().padLeft(2, '0')}-${monthEnd.day.toString().padLeft(2, '0')}';

    final cardAccounts = await _local.getCreditCardAccounts(accountIds: accountIds);
    final cardMovements = await _local.getCreditCardMovementsForProjection(
      maxDate,
      accountIds: accountIds,
    );
    final cardNetByCurrency = _oracle
        .estimateNetMonthlyObligation(
          targetMonth: month,
          now: now,
          accounts: cardAccounts,
          movements: cardMovements,
        )
        .netByCurrency;

    // existing balances/goals aggregation unchanged...
    // replace safeToSpend formula:
    // safeToSpend = liquidCents - goalTarget - (cardNetByCurrency[cc] ?? 0)
  }
}
```

- [ ] **Step 5: Run dashboard test and focused analyze**

Run: `cd /Volumes/rusty-drive/projects/pocket-pilot/frontend && flutter test test/dashboard_repository_credit_card_obligation_test.dart`

Expected: PASS.

Run: `cd /Volumes/rusty-drive/projects/pocket-pilot/frontend && flutter analyze lib/src/features/dashboard`

Expected: no analyzer errors in dashboard feature.

- [ ] **Step 6: Commit**

```bash
cd /Volumes/rusty-drive/projects/pocket-pilot
git add frontend/test/dashboard_repository_credit_card_obligation_test.dart frontend/lib/src/features/dashboard/data/dashboard_local_store.dart frontend/lib/src/features/dashboard/data/dashboard_repository.dart
git commit -m "feat(front-dashboard): subtract net card obligation from safe-to-spend"
```

---

### Task 6: Update Budget SQL to Prorate MSI by Overlapping Months (TDD)

**Files:**
- Create: `frontend/test/budget_installments_proration_test.dart`
- Modify: `frontend/lib/src/features/budgets/data/budget_local_store.dart`

- [ ] **Step 1: Write failing proration math tests first**

```dart
// frontend/test/budget_installments_proration_test.dart
import 'package:flutter_test/flutter_test.dart';

import 'package:pocket_pilot/src/features/budgets/data/budget_local_store.dart';

void main() {
  test('one-shot contributes full amount when month overlaps', () {
    final amount = BudgetLocalStore.proratedAmountForPeriod(
      amountCents: 1000,
      installmentsCount: 1,
      purchaseMonthIndex: 2026 * 12 + 3, // 2026-04
      periodStartMonthIndex: 2026 * 12 + 3,
      periodEndMonthIndex: 2026 * 12 + 3,
    );

    expect(amount, 1000);
  });

  test('residual goes to first month only', () {
    final april = BudgetLocalStore.proratedAmountForPeriod(
      amountCents: 1000,
      installmentsCount: 3,
      purchaseMonthIndex: 2026 * 12 + 3,
      periodStartMonthIndex: 2026 * 12 + 3,
      periodEndMonthIndex: 2026 * 12 + 3,
    );
    final may = BudgetLocalStore.proratedAmountForPeriod(
      amountCents: 1000,
      installmentsCount: 3,
      purchaseMonthIndex: 2026 * 12 + 3,
      periodStartMonthIndex: 2026 * 12 + 4,
      periodEndMonthIndex: 2026 * 12 + 4,
    );

    expect(april, 334);
    expect(may, 333);
  });

  test('yearly overlap includes only months inside target year', () {
    final amount = BudgetLocalStore.proratedAmountForPeriod(
      amountCents: 1001,
      installmentsCount: 3,
      purchaseMonthIndex: 2025 * 12 + 11, // 2025-12
      periodStartMonthIndex: 2026 * 12 + 0, // 2026-01
      periodEndMonthIndex: 2026 * 12 + 11, // 2026-12
    );

    expect(amount, 666); // Jan+Feb only, residual was in Dec 2025
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Volumes/rusty-drive/projects/pocket-pilot/frontend && flutter test test/budget_installments_proration_test.dart`

Expected: FAIL (helper function does not exist yet).

- [ ] **Step 3: Add proration helper and update SQL query**

```dart
// frontend/lib/src/features/budgets/data/budget_local_store.dart
import 'package:flutter/foundation.dart';

class BudgetLocalStore {
  // ...existing constructor and CRUD...

  @visibleForTesting
  static int proratedAmountForPeriod({
    required int amountCents,
    required int installmentsCount,
    required int purchaseMonthIndex,
    required int periodStartMonthIndex,
    required int periodEndMonthIndex,
  }) {
    if (installmentsCount < 1) {
      throw ArgumentError.value(
        installmentsCount,
        'installmentsCount',
        'installmentsCount must be >= 1',
      );
    }

    final txStart = purchaseMonthIndex;
    final txEnd = purchaseMonthIndex + installmentsCount - 1;
    final overlapStart = txStart > periodStartMonthIndex ? txStart : periodStartMonthIndex;
    final overlapEnd = txEnd < periodEndMonthIndex ? txEnd : periodEndMonthIndex;
    final overlapMonths = overlapEnd >= overlapStart ? (overlapEnd - overlapStart + 1) : 0;
    if (overlapMonths == 0) return 0;

    final base = amountCents ~/ installmentsCount;
    final residual = amountCents % installmentsCount;
    final firstInstallmentInPeriod =
        purchaseMonthIndex >= periodStartMonthIndex &&
        purchaseMonthIndex <= periodEndMonthIndex;

    return (base * overlapMonths) + (firstInstallmentInPeriod ? residual : 0);
  }

  Future<int> computeSpentCents(String categoryId, String period) async {
    final db = await _db.database;
    final now = DateTime.now();

    final periodStartIdx = period == 'MONTHLY'
        ? (now.year * 12 + (now.month - 1))
        : (now.year * 12);
    final periodEndIdx = period == 'MONTHLY'
        ? periodStartIdx
        : (now.year * 12 + 11);

    final result = await db.rawQuery('''
      SELECT COALESCE(SUM(
        CASE
          WHEN type NOT IN ('expense', 'income') THEN 0
          ELSE
            (CASE WHEN type = 'expense' THEN 1 ELSE -1 END) * (
              (
                CAST(amount_cents / installments_count AS INTEGER) *
                MAX(
                  0,
                  MIN(
                    (CAST(strftime('%Y', date) AS INTEGER) * 12 + CAST(strftime('%m', date) AS INTEGER) - 1 + installments_count - 1),
                    ?
                  )
                  -
                  MAX(
                    (CAST(strftime('%Y', date) AS INTEGER) * 12 + CAST(strftime('%m', date) AS INTEGER) - 1),
                    ?
                  )
                  + 1
                )
              )
              +
              CASE
                WHEN (amount_cents % installments_count) > 0
                  AND (CAST(strftime('%Y', date) AS INTEGER) * 12 + CAST(strftime('%m', date) AS INTEGER) - 1) BETWEEN ? AND ?
                THEN (amount_cents % installments_count)
                ELSE 0
              END
            )
        END
      ), 0) AS spent
      FROM transactions
      WHERE category_id = ?
        AND deleted_at IS NULL
        AND installments_count >= 1
        AND (CAST(strftime('%Y', date) AS INTEGER) * 12 + CAST(strftime('%m', date) AS INTEGER) - 1) <= ?
        AND (CAST(strftime('%Y', date) AS INTEGER) * 12 + CAST(strftime('%m', date) AS INTEGER) - 1 + installments_count - 1) >= ?
    ''', [
      periodEndIdx,
      periodStartIdx,
      periodStartIdx,
      periodEndIdx,
      categoryId,
      periodEndIdx,
      periodStartIdx,
    ]);

    return (result.first['spent'] as num?)?.toInt() ?? 0;
  }
}
```

- [ ] **Step 4: Run budget proration tests**

Run: `cd /Volumes/rusty-drive/projects/pocket-pilot/frontend && flutter test test/budget_installments_proration_test.dart`

Expected: PASS.

- [ ] **Step 5: Run focused analyze on budget module**

Run: `cd /Volumes/rusty-drive/projects/pocket-pilot/frontend && flutter analyze lib/src/features/budgets`

Expected: no analyzer errors in budget feature.

- [ ] **Step 6: Commit**

```bash
cd /Volumes/rusty-drive/projects/pocket-pilot
git add frontend/test/budget_installments_proration_test.dart frontend/lib/src/features/budgets/data/budget_local_store.dart
git commit -m "feat(front-budget): prorate MSI spend by overlapping months"
```

---

### Task 7: End-to-End Verification and Context Journal Update

**Files:**
- Modify: `docs/context/.journal.md`

- [ ] **Step 1: Run protobuf generation check**

Run: `cd /Volumes/rusty-drive/projects/pocket-pilot && make proto`

Expected: generation succeeds without warnings/errors.

- [ ] **Step 2: Run backend verification**

Run: `cd /Volumes/rusty-drive/projects/pocket-pilot/backend && go test ./...`

Expected: all backend tests pass.

- [ ] **Step 3: Run frontend verification**

Run: `cd /Volumes/rusty-drive/projects/pocket-pilot/frontend && flutter test`

Expected: all frontend tests pass.

Run: `cd /Volumes/rusty-drive/projects/pocket-pilot/frontend && flutter analyze`

Expected: no new analyzer errors.

- [ ] **Step 4: Append context journal entry**

```md
* [2026-04-03] [Transactions/Dashboard/Budgets] Implemented MSI support end-to-end: added strict `transactions.installments_count` (`>=1`) across PostgreSQL/SQLite/proto/Go/Dart mappings, introduced `CreditCardOracle` to compute monthly net card obligations (cycle-aware with calendar fallback and first-installment residual handling), updated dashboard `safe_to_spend = liquid - goals - estimated_card_payment`, and updated budget spend query to prorate installment impact by month overlap instead of full purchase-month amount.
```

- [ ] **Step 5: Commit journal update**

```bash
cd /Volumes/rusty-drive/projects/pocket-pilot
git add docs/context/.journal.md
git commit -m "docs: log MSI credit card projection rollout"
```

---

## Final Verification Gate

- [ ] Run: `cd /Volumes/rusty-drive/projects/pocket-pilot && make proto`
- [ ] Run: `cd /Volumes/rusty-drive/projects/pocket-pilot/backend && go test ./...`
- [ ] Run: `cd /Volumes/rusty-drive/projects/pocket-pilot/frontend && flutter test`
- [ ] Run: `cd /Volumes/rusty-drive/projects/pocket-pilot/frontend && flutter analyze`
- [ ] Run: `cd /Volumes/rusty-drive/projects/pocket-pilot && git status` (expect clean working tree)

---

## Self-Review

### 1) Spec coverage check

- Migration `001` updates for transactions in PostgreSQL/SQLite: Task 1.
- Proto `Transaction.installments_count`: Task 1.
- Strict validation `installments_count >= 1` (no normalization): Tasks 2 and 3.
- CreditCardOracle class with cycle mode, fallback mode, residual-first installment, netting floor zero: Task 4.
- Dashboard safe-to-spend subtracts estimated card payment: Task 5.
- Budget SQL proration by installment overlap: Task 6.
- Testing coverage for oracle math, repository metric integration, and proration arithmetic: Tasks 4, 5, and 6.
- Context journal log requirement: Task 7.

### 2) Placeholder scan

- No `TODO`, `TBD`, or “implement later” markers remain.
- Each code step includes concrete code and each verification step includes exact command + expected result.

### 3) Type/signature consistency

- `installments_count` (snake_case) used in SQL/proto payload maps; `installmentsCount` used in Dart model fields.
- Validation rule `>= 1` is consistent in backend validator, backend proto mapping, and Dart model/remote mapping.
- Oracle includes only agreed transaction type sets:
  - charges: `expense`, `transfer_out`
  - payments: `income`, `transfer_in`
- Dashboard formula uses per-currency aggregation and keeps existing `buying_power = safe_to_spend + revolving`.
