# Transaction Templates and Scheduled Transactions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement offline-first transaction templates and recurring scheduled generation with deterministic UUIDs, transfer support, and backend passive sync/LWW behavior.

**Architecture:** Add a new syncable `transaction_template` entity across proto, backend, and frontend `sqflite` stacks. Keep generation on Flutter client using deterministic UUIDv5 and strict skip/retry rules, then rely on existing outbox + LWW sync. Split delivery into two executable tracks: Core templates/scheduler and Tags remediation.

**Tech Stack:** Flutter (Dart, Provider, sqflite, grpc), Go (gRPC, pgx/PostgreSQL), Protocol Buffers, UUID v5

**Spec:** `docs/superpowers/specs/2026-03-29-transaction-templates-scheduled-transactions-design.md`

---

## Scope Split (Required)

This plan is intentionally split into two workstreams that map to the spec's split requirement:

- **Plan A (Core):** contracts, migrations, backend template service, frontend template sync module, generator, orchestration.
- **Plan B (Tags remediation):** fix transaction `tags` persistence end-to-end in existing flows.

Do not start Plan B commits until Plan A Task 9 is green.

---

## File Structure

### Plan A (Core)

| File | Action | Responsibility |
|---|---|---|
| `proto/pocket_pilot/v1/transaction_template_service.proto` | Create | New template RPC contract |
| `proto/pocket_pilot/v1/transaction_service.proto` | Modify | Add `template_id` field in `Transaction` |
| `scripts/gen_proto.sh` | Modify | Include new proto in Go/Dart codegen |
| `backend/migrations/002_transaction_templates.sql` | Create | Postgres schema for templates + transactions linkage |
| `frontend/assets/migrations/002.sql` | Create | SQLite schema for templates + linkage index |
| `frontend/lib/src/core/db/database_helper.dart` | Modify | DB version bump to run 002 |
| `backend/internal/transactiontemplate/model.go` | Create | Internal template model |
| `backend/internal/transactiontemplate/validation.go` | Create | Server validation rules |
| `backend/internal/transactiontemplate/validation_test.go` | Create | Validation unit tests |
| `backend/internal/transactiontemplate/repository.go` | Create | LWW repository for templates |
| `backend/internal/transactiontemplate/handler.go` | Create | gRPC handler for templates |
| `backend/cmd/server/main.go` | Modify | Register template gRPC service |
| `backend/internal/transaction/repository.go` | Modify | Persist `template_id` and template-reference checks |
| `backend/internal/transaction/handler.go` | Modify | Proto mapping for `template_id` |
| `frontend/lib/src/features/transaction_templates/domain/transaction_template.dart` | Create | Flutter template model |
| `frontend/lib/src/features/transaction_templates/data/transaction_template_local_store.dart` | Create | SQLite DAO for templates |
| `frontend/lib/src/features/transaction_templates/data/transaction_template_repository.dart` | Create | Local-first repository + outbox |
| `frontend/lib/src/features/transaction_templates/data/transaction_template_remote_service.dart` | Create | gRPC client for templates |
| `frontend/lib/src/features/transaction_templates/data/transaction_template_sync_handler.dart` | Create | Sync bridge + degraded handling |
| `frontend/lib/src/core/ids/deterministic_namespace.dart` | Create | UUID v5 namespace constant |
| `frontend/lib/src/features/transaction_templates/domain/schedule_date_math.dart` | Create | Date advancement helpers |
| `frontend/lib/src/features/transaction_templates/domain/schedule_date_math_test.dart` | Create | Date math tests |
| `frontend/lib/src/features/transaction_templates/data/scheduled_transaction_generator.dart` | Create | Core generation loop |
| `frontend/lib/src/features/transaction_templates/data/scheduled_transaction_generator_test.dart` | Create | Generator behavior tests |
| `frontend/lib/src/core/sync/scheduled_generation_orchestrator.dart` | Create | Pull -> generate -> push flow |
| `frontend/lib/src/core/sync/scheduled_generation_orchestrator_test.dart` | Create | Orchestration order tests |
| `frontend/lib/main.dart` | Modify | Register template handler/orchestrator |
| `frontend/lib/src/ui/app.dart` | Modify | Trigger orchestrator on app resume |

### Plan B (Tags Remediation)

| File | Action | Responsibility |
|---|---|---|
| `frontend/lib/src/features/transactions/domain/transaction.dart` | Modify | Add `tags` and `templateId`, JSON mapping |
| `frontend/lib/src/features/transactions/data/transaction_repository.dart` | Modify | Pass tags/templateId on create/update/generation |
| `frontend/lib/src/features/transactions/data/transaction_remote_service.dart` | Modify | gRPC map includes tags/templateId |
| `frontend/lib/src/features/transactions/data/transaction_sync_handler.dart` | Modify | Persist tags/templateId in conflict paths |
| `frontend/lib/src/features/transactions/ui/transaction_form_screen.dart` | Modify | Save and preload tags |
| `frontend/lib/src/features/transactions/ui/transfer_form_screen.dart` | Modify | Ensure transfer tags propagate |
| `frontend/test/transaction_model_tags_test.dart` | Create | Model JSON tags tests |
| `frontend/test/transaction_repository_tags_test.dart` | Create | Repository tag propagation tests |

---

### Task 1: Proto Contracts and Codegen

**Files:**
- Create: `proto/pocket_pilot/v1/transaction_template_service.proto`
- Modify: `proto/pocket_pilot/v1/transaction_service.proto`
- Modify: `scripts/gen_proto.sh`

- [ ] **Step 1: Add new template proto contract**

```proto
// proto/pocket_pilot/v1/transaction_template_service.proto
syntax = "proto3";

package pocket_pilot.v1;

import "pocket_pilot/v1/common.proto";
import "google/protobuf/empty.proto";
import "google/protobuf/timestamp.proto";

option go_package = "github.com/AlanIsaacV/pocket-pilot/backend/internal/gen/proto/pocket_pilot/v1;pocketpilotv1";

message TransactionTemplate {
  string id = 1;
  string name = 2;
  string account_id = 3;
  optional string category_id = 4;
  string type = 5;
  optional int64 amount_cents = 6;
  string currency_code = 7;
  repeated string tags = 8;
  string description = 9;
  optional string frequency = 10;
  optional string next_date = 11;
  optional string end_date = 12;
  google.protobuf.Timestamp created_at = 13;
  google.protobuf.Timestamp updated_at = 14;
  google.protobuf.Timestamp deleted_at = 15;
  optional string to_account_id = 16;
}

service TransactionTemplateService {
  rpc ListTransactionTemplates(ListTransactionTemplatesRequest) returns (ListTransactionTemplatesResponse);
  rpc UpsertTransactionTemplate(UpsertTransactionTemplateRequest) returns (UpsertTransactionTemplateResponse);
  rpc DeleteTransactionTemplate(DeleteTransactionTemplateRequest) returns (google.protobuf.Empty);
}

message ListTransactionTemplatesRequest {
  google.protobuf.Timestamp updated_since = 1;
  PageRequest page = 2;
}

message ListTransactionTemplatesResponse {
  repeated TransactionTemplate templates = 1;
  PageResponse page = 2;
  google.protobuf.Timestamp synced_at = 3;
}

message UpsertTransactionTemplateRequest {
  TransactionTemplate template = 1;
}

message UpsertTransactionTemplateResponse {
  TransactionTemplate template = 1;
  bool conflict_resolved = 2;
}

message DeleteTransactionTemplateRequest {
  string id = 1;
  google.protobuf.Timestamp deleted_at = 2;
}
```

- [ ] **Step 2: Extend transaction proto with template linkage**

```proto
// proto/pocket_pilot/v1/transaction_service.proto
message Transaction {
  string id = 1;
  string account_id = 2;
  optional string category_id = 3;
  TransactionType type = 4;
  int64 amount_cents = 5;
  string currency_code = 6;
  string status = 7;
  repeated string tags = 8;
  string description = 9;
  google.protobuf.Timestamp date = 10;
  google.protobuf.Timestamp created_at = 11;
  google.protobuf.Timestamp updated_at = 12;
  google.protobuf.Timestamp deleted_at = 13;
  optional string linked_transaction_id = 14;
  optional string template_id = 15;
  reserved 16;
}
```

- [ ] **Step 3: Update proto generation script inputs**

```bash
# scripts/gen_proto.sh
# Add this file to BOTH protoc invocations:
pocket_pilot/v1/transaction_template_service.proto
```

- [ ] **Step 4: Regenerate Go and Dart stubs**

Run: `cd /Volumes/rusty-drive/projects/pocket-pilot && ./scripts/gen_proto.sh`
Expected: `✓ Done. Generated files:` and no protoc errors.

- [ ] **Step 5: Commit**

```bash
cd /Volumes/rusty-drive/projects/pocket-pilot
git add proto/pocket_pilot/v1/transaction_template_service.proto proto/pocket_pilot/v1/transaction_service.proto scripts/gen_proto.sh backend/internal/gen/proto frontend/lib/src/generated
git commit -m "feat(proto): add transaction template service and transaction template_id"
```

---

### Task 2: Database Migrations (Postgres + SQLite)

**Files:**
- Create: `backend/migrations/002_transaction_templates.sql`
- Create: `frontend/assets/migrations/002.sql`
- Modify: `frontend/lib/src/core/db/database_helper.dart`

- [ ] **Step 1: Add backend migration SQL**

```sql
-- backend/migrations/002_transaction_templates.sql
CREATE TABLE transaction_templates (
    id               uuid PRIMARY KEY      DEFAULT gen_random_uuid(),
    user_id          uuid         NOT NULL,
    name             text         NOT NULL,
    account_id       uuid         NOT NULL REFERENCES accounts(id),
    to_account_id    uuid                  REFERENCES accounts(id),
    category_id      uuid                  REFERENCES categories(id),
    type             text         NOT NULL,
    amount_cents     bigint,
    currency_code    text         NOT NULL,
    tags             text[],
    description      text         NOT NULL DEFAULT '',
    frequency        text,
    next_date        date,
    end_date         date,
    created_at       timestamptz  NOT NULL DEFAULT now(),
    updated_at       timestamptz  NOT NULL DEFAULT now(),
    deleted_at       timestamptz
);

CREATE INDEX idx_transaction_templates_user_next_date
  ON transaction_templates(user_id, next_date)
  WHERE deleted_at IS NULL AND frequency IS NOT NULL AND next_date IS NOT NULL;

CREATE INDEX idx_transaction_templates_user_updated_at
  ON transaction_templates(user_id, updated_at);

ALTER TABLE transactions
  ADD COLUMN template_id uuid REFERENCES transaction_templates(id);

CREATE INDEX idx_transactions_template_id
  ON transactions(template_id)
  WHERE template_id IS NOT NULL;

CREATE TRIGGER set_updated_at_transaction_templates
    BEFORE UPDATE
    ON transaction_templates
    FOR EACH ROW
EXECUTE FUNCTION trigger_set_updated_at();
```

- [ ] **Step 2: Add frontend migration SQL**

```sql
-- frontend/assets/migrations/002.sql
CREATE TABLE transaction_templates (
    id            TEXT PRIMARY KEY,
    name          TEXT NOT NULL,
    account_id    TEXT NOT NULL REFERENCES accounts(id),
    to_account_id TEXT REFERENCES accounts(id),
    category_id   TEXT REFERENCES categories(id),
    type          TEXT NOT NULL,
    amount_cents  BIGINT,
    currency_code TEXT NOT NULL,
    tags          TEXT,
    description   TEXT NOT NULL DEFAULT '',
    frequency     TEXT,
    next_date     DATE,
    end_date      DATE,
    created_at    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    deleted_at    DATETIME
);

CREATE INDEX idx_transaction_templates_next_date
  ON transaction_templates(next_date)
  WHERE deleted_at IS NULL AND frequency IS NOT NULL AND next_date IS NOT NULL;

CREATE INDEX idx_transaction_templates_updated_at
  ON transaction_templates(updated_at);

CREATE TRIGGER set_updated_at_transaction_templates
    AFTER UPDATE
    ON transaction_templates
    FOR EACH ROW
    WHEN new.updated_at = old.updated_at
BEGIN
    UPDATE transaction_templates
    SET updated_at = CURRENT_TIMESTAMP
    WHERE id = new.id;
END;

ALTER TABLE transactions
  ADD COLUMN template_id TEXT REFERENCES transaction_templates(id);

CREATE INDEX idx_transactions_template_id
  ON transactions(template_id)
  WHERE template_id IS NOT NULL;
```

- [ ] **Step 3: Bump frontend DB version to run migration**

```dart
// frontend/lib/src/core/db/database_helper.dart
static const int _version = 2;
```

- [ ] **Step 4: Run analyzer/test smoke checks**

Run: `cd /Volumes/rusty-drive/projects/pocket-pilot/frontend && flutter analyze lib/src/core/db/database_helper.dart`
Expected: `No issues found!`

- [ ] **Step 5: Commit**

```bash
cd /Volumes/rusty-drive/projects/pocket-pilot
git add backend/migrations/002_transaction_templates.sql frontend/assets/migrations/002.sql frontend/lib/src/core/db/database_helper.dart
git commit -m "feat(db): add transaction_templates schema and transaction template linkage"
```

---

### Task 3: Backend Template Validation (TDD)

**Files:**
- Create: `backend/internal/transactiontemplate/model.go`
- Create: `backend/internal/transactiontemplate/validation.go`
- Create: `backend/internal/transactiontemplate/validation_test.go`

- [ ] **Step 1: Write failing validation tests**

```go
// backend/internal/transactiontemplate/validation_test.go
package transactiontemplate

import (
  "testing"
  "time"
)

func TestValidateTemplate(t *testing.T) {
  next := dateOnly(time.Date(2026, 4, 1, 0, 0, 0, 0, time.UTC))
  end := dateOnly(time.Date(2026, 12, 1, 0, 0, 0, 0, time.UTC))

  tests := []struct {
    name string
    tpl  Template
    wantErr bool
  }{
    {
      name: "manual income valid",
      tpl: Template{Type: "income", Frequency: nil, NextDate: nil, EndDate: nil},
      wantErr: false,
    },
    {
      name: "manual with next_date invalid",
      tpl: Template{Type: "expense", NextDate: &next},
      wantErr: true,
    },
    {
      name: "scheduled missing amount invalid",
      tpl: Template{Type: "expense", Frequency: ptr("MONTHLY"), NextDate: &next},
      wantErr: true,
    },
    {
      name: "scheduled with end before next invalid",
      tpl: Template{Type: "expense", Frequency: ptr("MONTHLY"), NextDate: &end, EndDate: &next, AmountCents: ptrInt64(1000)},
      wantErr: true,
    },
    {
      name: "transfer requires to_account",
      tpl: Template{Type: "transfer_out", Frequency: ptr("MONTHLY"), NextDate: &next, AmountCents: ptrInt64(1000)},
      wantErr: true,
    },
  }

  for _, tc := range tests {
    tc := tc
    t.Run(tc.name, func(t *testing.T) {
      err := ValidateTemplate(tc.tpl)
      if tc.wantErr && err == nil {
        t.Fatalf("expected error")
      }
      if !tc.wantErr && err != nil {
        t.Fatalf("unexpected error: %v", err)
      }
    })
  }
}

func ptr(s string) *string { return &s }
func ptrInt64(v int64) *int64 { return &v }
```

- [ ] **Step 2: Run test and confirm failure**

Run: `cd /Volumes/rusty-drive/projects/pocket-pilot/backend && go test ./internal/transactiontemplate -run TestValidateTemplate -v`
Expected: FAIL with missing package/symbols.

- [ ] **Step 3: Implement model + validation**

```go
// backend/internal/transactiontemplate/model.go
package transactiontemplate

import (
  "time"
  "github.com/google/uuid"
)

type Template struct {
  ID uuid.UUID
  UserID uuid.UUID
  Name string
  AccountID uuid.UUID
  ToAccountID *uuid.UUID
  CategoryID *uuid.UUID
  Type string
  AmountCents *int64
  CurrencyCode string
  Tags []string
  Description string
  Frequency *string
  NextDate *time.Time
  EndDate *time.Time
  CreatedAt time.Time
  UpdatedAt time.Time
  DeletedAt *time.Time
}

func dateOnly(t time.Time) time.Time {
  return t.UTC().Truncate(24 * time.Hour)
}
```

```go
// backend/internal/transactiontemplate/validation.go
package transactiontemplate

import "fmt"

func ValidateTemplate(t Template) error {
  switch t.Type {
  case "income", "expense", "transfer_out":
  default:
    return fmt.Errorf("invalid type")
  }

  if t.Frequency == nil {
    if t.NextDate != nil || t.EndDate != nil {
      return fmt.Errorf("manual template cannot have schedule fields")
    }
  } else {
    switch *t.Frequency {
    case "DAILY", "WEEKLY", "MONTHLY", "YEARLY":
    default:
      return fmt.Errorf("invalid frequency")
    }
    if t.NextDate == nil {
      return fmt.Errorf("scheduled template requires next_date")
    }
    if t.AmountCents == nil {
      return fmt.Errorf("scheduled template requires amount_cents")
    }
    if t.EndDate != nil && t.EndDate.Before(*t.NextDate) {
      return fmt.Errorf("end_date must be >= next_date")
    }
  }

  if t.Type == "transfer_out" {
    if t.ToAccountID == nil {
      return fmt.Errorf("transfer template requires to_account_id")
    }
    if t.AccountID == *t.ToAccountID {
      return fmt.Errorf("to_account_id must differ from account_id")
    }
    if t.CategoryID != nil {
      return fmt.Errorf("transfer template must not have category_id")
    }
  } else if t.ToAccountID != nil {
    return fmt.Errorf("non-transfer template must not have to_account_id")
  }

  return nil
}
```

- [ ] **Step 4: Run validation tests and full backend tests**

Run: `cd /Volumes/rusty-drive/projects/pocket-pilot/backend && go test ./internal/transactiontemplate ./...`
Expected: `ok` for package and no compile failures.

- [ ] **Step 5: Commit**

```bash
cd /Volumes/rusty-drive/projects/pocket-pilot
git add backend/internal/transactiontemplate/model.go backend/internal/transactiontemplate/validation.go backend/internal/transactiontemplate/validation_test.go
git commit -m "feat(back-templates): add template model and validation rules"
```

---

### Task 4: Backend Template Repository, Handler, and Server Wiring

**Files:**
- Create: `backend/internal/transactiontemplate/repository.go`
- Create: `backend/internal/transactiontemplate/handler.go`
- Modify: `backend/cmd/server/main.go`

- [ ] **Step 1: Create repository with LWW list/upsert/delete**

```go
// backend/internal/transactiontemplate/repository.go (core signatures)
type Repository struct { pool *pgxpool.Pool }

func (r *Repository) List(ctx context.Context, userID uuid.UUID, updatedSince *time.Time, limit, offset int) ([]*Template, time.Time, error)
func (r *Repository) Upsert(ctx context.Context, t *Template) (*Template, bool, error)
func (r *Repository) SoftDelete(ctx context.Context, id, userID uuid.UUID, deletedAt time.Time) error
func (r *Repository) GetByID(ctx context.Context, id, userID uuid.UUID) (*Template, error)
```

Use SQL pattern matching existing modules:

```sql
ON CONFLICT (id) DO UPDATE SET
  ...,
  updated_at = EXCLUDED.updated_at,
  deleted_at = EXCLUDED.deleted_at
WHERE transaction_templates.updated_at < EXCLUDED.updated_at
```

- [ ] **Step 2: Add handler with proto mapping and ownership checks**

```go
// backend/internal/transactiontemplate/handler.go (required RPCs)
func (h *Handler) ListTransactionTemplates(ctx context.Context, req *pb.ListTransactionTemplatesRequest) (*pb.ListTransactionTemplatesResponse, error)
func (h *Handler) UpsertTransactionTemplate(ctx context.Context, req *pb.UpsertTransactionTemplateRequest) (*pb.UpsertTransactionTemplateResponse, error)
func (h *Handler) DeleteTransactionTemplate(ctx context.Context, req *pb.DeleteTransactionTemplateRequest) (*emptypb.Empty, error)
```

Validation in `UpsertTransactionTemplate` must call `ValidateTemplate(...)` before repo upsert.

- [ ] **Step 3: Register service in gRPC server startup**

```go
// backend/cmd/server/main.go
import "github.com/AlanIsaacV/pocket-pilot/internal/transactiontemplate"

templateHandler := transactiontemplate.NewHandler(transactiontemplate.NewRepository(pool))
pb.RegisterTransactionTemplateServiceServer(srv, templateHandler)
```

- [ ] **Step 4: Run backend test suite**

Run: `cd /Volumes/rusty-drive/projects/pocket-pilot/backend && go test ./...`
Expected: all packages compile and tests pass.

- [ ] **Step 5: Commit**

```bash
cd /Volumes/rusty-drive/projects/pocket-pilot
git add backend/internal/transactiontemplate/repository.go backend/internal/transactiontemplate/handler.go backend/cmd/server/main.go
git commit -m "feat(back-templates): add template repository handler and server registration"
```

---

### Task 5: Backend Transactions Template Linkage Rules

**Files:**
- Modify: `backend/internal/transaction/repository.go`
- Modify: `backend/internal/transaction/handler.go`

- [ ] **Step 1: Add `TemplateID` to backend transaction model and SQL scan columns**

```go
// backend/internal/transaction/repository.go
type Transaction struct {
  ...
  TemplateID *uuid.UUID
}

const scanColumns = `id, user_id, account_id, category_id, linked_transaction_id, template_id, type, amount_cents, currency_code, status, tags, description, date, created_at, updated_at, deleted_at`
```

- [ ] **Step 2: Update insert/upsert SQL to persist template_id**

```sql
INSERT INTO transactions (..., linked_transaction_id, template_id, type, ...)
VALUES (...)
ON CONFLICT (id) DO UPDATE SET
  ...,
  template_id = EXCLUDED.template_id,
  ...
```

- [ ] **Step 3: Map proto optional `template_id` in handler**

```go
// backend/internal/transaction/handler.go
if t.TemplateID != nil {
  s := t.TemplateID.String()
  proto.TemplateId = &s
}

if p.TemplateId != nil && *p.TemplateId != "" {
  tid, err := parseUUID(*p.TemplateId, "transaction.template_id")
  if err != nil { return nil, err }
  tx.TemplateID = &tid
}
```

- [ ] **Step 4: Run backend tests**

Run: `cd /Volumes/rusty-drive/projects/pocket-pilot/backend && go test ./...`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
cd /Volumes/rusty-drive/projects/pocket-pilot
git add backend/internal/transaction/repository.go backend/internal/transaction/handler.go
git commit -m "feat(back-transactions): support template_id linkage in transaction service"
```

---

### Task 6: Flutter Transaction Template Data + Sync Layer

**Files:**
- Create: `frontend/lib/src/features/transaction_templates/domain/transaction_template.dart`
- Create: `frontend/lib/src/features/transaction_templates/data/transaction_template_local_store.dart`
- Create: `frontend/lib/src/features/transaction_templates/data/transaction_template_repository.dart`
- Create: `frontend/lib/src/features/transaction_templates/data/transaction_template_remote_service.dart`
- Create: `frontend/lib/src/features/transaction_templates/data/transaction_template_sync_handler.dart`
- Modify: `frontend/lib/main.dart`
- Modify: `frontend/lib/src/features/transactions/data/transaction_sync_handler.dart`

- [ ] **Step 1: Create domain model with JSON tags and date-string fields**

```dart
// frontend/lib/src/features/transaction_templates/domain/transaction_template.dart
class TransactionTemplateModel {
  final String id;
  final String name;
  final String accountId;
  final String? toAccountId;
  final String? categoryId;
  final String type;
  final int? amountCents;
  final String currencyCode;
  final List<String> tags;
  final String description;
  final String? frequency;
  final String? nextDate;
  final String? endDate;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  // include fromMap/toMap/fromProto/toProtoMap helpers
}
```

- [ ] **Step 2: Implement local store and repository with outbox integration**

```dart
// local store required methods
Future<List<Map<String, dynamic>>> querySchedulableRows({required String horizonDate});
Future<void> upsertRow(Map<String, dynamic> row);
Future<void> upsertRows(List<Map<String, dynamic>> rows);
Future<void> softDelete(String id, DateTime deletedAt);
```

```dart
// repository required methods
Future<void> createOrUpdateTemplate(TransactionTemplateModel model);
Future<void> deleteTemplate(String id);
Future<List<TransactionTemplateModel>> getTemplates();
```

- [ ] **Step 3: Implement remote service + sync handler with degraded-mode handling**

```dart
// transaction_template_sync_handler.dart
@override
Future<SyncPullResult> pull(DateTime? updatedSince) async {
  try {
    final response = await _remote.listTemplates(updatedSince: updatedSince);
    ...
  } on GrpcError catch (e) {
    if (_isNonFatalUnsupported(e.code)) {
      return SyncPullResult(items: const [], syncedAt: DateTime.now().toUtc());
    }
    rethrow;
  }
}
```

Also move `TransactionSyncHandler.syncOrder` from `4` to `5`.

- [ ] **Step 4: Register template sync handler in `main.dart` before transaction handler**

```dart
final templateSyncHandler = TransactionTemplateSyncHandler(
  local: TransactionTemplateLocalStore(db: dbHelper),
  remote: TransactionTemplateRemoteService(),
);

handlers: [
  accountSyncHandler,
  categorySyncHandler,
  tagSyncHandler,
  templateSyncHandler,
  transactionSyncHandler,
  userPreferenceSyncHandler,
]
```

- [ ] **Step 5: Run Flutter analyze**

Run: `cd /Volumes/rusty-drive/projects/pocket-pilot/frontend && flutter analyze`
Expected: no analyzer errors.

- [ ] **Step 6: Commit**

```bash
cd /Volumes/rusty-drive/projects/pocket-pilot
git add frontend/lib/main.dart frontend/lib/src/features/transaction_templates frontend/lib/src/features/transactions/data/transaction_sync_handler.dart
git commit -m "feat(front-templates): add template domain data and sync handlers"
```

---

### Task 7: Deterministic ID and Date-Math Helpers (TDD)

**Files:**
- Create: `frontend/lib/src/core/ids/deterministic_namespace.dart`
- Create: `frontend/lib/src/features/transaction_templates/domain/schedule_date_math.dart`
- Create: `frontend/test/schedule_date_math_test.dart`

- [ ] **Step 1: Write failing date-math tests**

```dart
// frontend/test/schedule_date_math_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_pilot/src/features/transaction_templates/domain/schedule_date_math.dart';

void main() {
  test('monthly clamps 31 Jan -> 29 Feb in leap year', () {
    expect(nextScheduleDate('MONTHLY', '2024-01-31'), '2024-02-29');
  });

  test('yearly clamps Feb 29 -> Feb 28 in non-leap year', () {
    expect(nextScheduleDate('YEARLY', '2024-02-29'), '2025-02-28');
  });

  test('daily increments by one day', () {
    expect(nextScheduleDate('DAILY', '2026-04-01'), '2026-04-02');
  });
}
```

- [ ] **Step 2: Run test and confirm fail**

Run: `cd /Volumes/rusty-drive/projects/pocket-pilot/frontend && flutter test test/schedule_date_math_test.dart`
Expected: FAIL missing helper.

- [ ] **Step 3: Implement helper and deterministic namespace constant**

```dart
// frontend/lib/src/core/ids/deterministic_namespace.dart
const String kDeterministicTemplateNamespace = '2f9b87e8-6a3f-5bb6-a54f-24d7a77d24fe';
```

```dart
// frontend/lib/src/features/transaction_templates/domain/schedule_date_math.dart
String nextScheduleDate(String frequency, String currentDate) {
  final d = DateTime.parse(currentDate);
  switch (frequency) {
    case 'DAILY':
      return _fmt(d.add(const Duration(days: 1)));
    case 'WEEKLY':
      return _fmt(d.add(const Duration(days: 7)));
    case 'MONTHLY':
      return _fmt(DateTime(d.year, d.month + 2, 0).day < d.day
          ? DateTime(d.year, d.month + 2, 0)
          : DateTime(d.year, d.month + 1, d.day));
    case 'YEARLY':
      final target = DateTime(d.year + 1, d.month, 1);
      final lastDay = DateTime(target.year, d.month + 1, 0).day;
      final day = d.day > lastDay ? lastDay : d.day;
      return _fmt(DateTime(target.year, d.month, day));
    default:
      throw ArgumentError('invalid frequency: $frequency');
  }
}

String _fmt(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
```

- [ ] **Step 4: Run helper tests**

Run: `cd /Volumes/rusty-drive/projects/pocket-pilot/frontend && flutter test test/schedule_date_math_test.dart`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
cd /Volumes/rusty-drive/projects/pocket-pilot
git add frontend/lib/src/core/ids/deterministic_namespace.dart frontend/lib/src/features/transaction_templates/domain/schedule_date_math.dart frontend/test/schedule_date_math_test.dart
git commit -m "feat(front-templates): add deterministic namespace and schedule date helpers"
```

---

### Task 8: Scheduled Generator Core (TDD)

**Files:**
- Create: `frontend/lib/src/features/transaction_templates/data/scheduled_transaction_generator.dart`
- Create: `frontend/test/scheduled_transaction_generator_test.dart`
- Modify: `frontend/lib/src/features/transactions/data/transaction_local_store.dart`

- [ ] **Step 1: Write failing generator tests for idempotency and skip policy**

```dart
// frontend/test/scheduled_transaction_generator_test.dart
test('generator uses deterministic UUID and does not duplicate on second run', () async {
  // arrange in-memory fake stores with one DAILY template
  // act run twice
  // assert one transaction inserted and next_date advanced once per run window
});

test('generator skips when category missing and leaves next_date unchanged', () async {
  // arrange template with missing category
  // act run
  // assert no insert and template next_date unchanged
});

test('transfer template creates out/in pair with linked ids', () async {
  // arrange valid transfer template
  // assert two transactions with reciprocal linked_transaction_id
});
```

- [ ] **Step 2: Run generator tests and confirm fail**

Run: `cd /Volumes/rusty-drive/projects/pocket-pilot/frontend && flutter test test/scheduled_transaction_generator_test.dart`
Expected: FAIL missing generator.

- [ ] **Step 3: Implement generator with strict algorithm contract**

```dart
// scheduled_transaction_generator.dart (core API)
class ScheduledTransactionGenerator {
  Future<GenerationReport> run({required DateTime nowUtc}) async { ... }
}

// required behavior
// - horizon = todayUtc + 30 days
// - loop template.next_date <= horizon
// - break-without-advance for reference-integrity skip reasons
// - advance for permanent data-shape errors
// - INSERT OR IGNORE for transactions
// - transfer pair reconciliation: insert missing leg when exactly one exists
// - update template next_date only when cursor advanced or template ended
```

- [ ] **Step 4: Add insert-or-ignore API in transaction local store**

```dart
// transaction_local_store.dart
Future<void> insertRowIgnoreConflict(Map<String, dynamic> row) async {
  final db = await _db.database;
  await db.insert('transactions', row, conflictAlgorithm: ConflictAlgorithm.ignore);
}
```

- [ ] **Step 5: Run generator tests + full Flutter tests**

Run: `cd /Volumes/rusty-drive/projects/pocket-pilot/frontend && flutter test`
Expected: all tests pass.

- [ ] **Step 6: Commit**

```bash
cd /Volumes/rusty-drive/projects/pocket-pilot
git add frontend/lib/src/features/transaction_templates/data/scheduled_transaction_generator.dart frontend/lib/src/features/transactions/data/transaction_local_store.dart frontend/test/scheduled_transaction_generator_test.dart
git commit -m "feat(front-templates): implement scheduled transaction generator"
```

---

### Task 9: Sync Orchestration (Pull -> Generate -> Push)

**Files:**
- Create: `frontend/lib/src/core/sync/scheduled_generation_orchestrator.dart`
- Create: `frontend/test/scheduled_generation_orchestrator_test.dart`
- Modify: `frontend/lib/main.dart`
- Modify: `frontend/lib/src/ui/app.dart`

- [ ] **Step 1: Write failing orchestration-order tests**

```dart
// frontend/test/scheduled_generation_orchestrator_test.dart
test('orchestrator runs sync, generator, sync in order', () async {
  // fake sync service and fake generator capture call order
  // expect ['sync', 'generate', 'sync']
});

test('overlapping calls are coalesced', () async {
  // trigger run twice while active
  // expect second run queued once
});
```

- [ ] **Step 2: Run tests and confirm fail**

Run: `cd /Volumes/rusty-drive/projects/pocket-pilot/frontend && flutter test test/scheduled_generation_orchestrator_test.dart`
Expected: FAIL missing orchestrator.

- [ ] **Step 3: Implement orchestrator with mutex + queued rerun**

```dart
// scheduled_generation_orchestrator.dart
class ScheduledGenerationOrchestrator {
  bool _running = false;
  bool _queued = false;

  Future<void> runCycle() async {
    if (_running) {
      _queued = true;
      return;
    }
    _running = true;
    try {
      do {
        _queued = false;
        await _syncService.sync();      // pull dependencies + baseline push
        await _generator.run(nowUtc: DateTime.now().toUtc());
        await _syncService.sync();      // push generated transactions/templates
      } while (_queued);
    } finally {
      _running = false;
    }
  }
}
```

- [ ] **Step 4: Wire orchestrator in app startup and resume**

```dart
// main.dart: build orchestrator and provide it
final orchestrator = ScheduledGenerationOrchestrator(
  syncService: syncService,
  generator: scheduledGenerator,
);

// app.dart: call orchestrator on resumed instead of direct sync
context.read<ScheduledGenerationOrchestrator>().runCycle();
```

- [ ] **Step 5: Run Flutter test + analyze**

Run: `cd /Volumes/rusty-drive/projects/pocket-pilot/frontend && flutter test && flutter analyze`
Expected: all green.

- [ ] **Step 6: Commit**

```bash
cd /Volumes/rusty-drive/projects/pocket-pilot
git add frontend/lib/src/core/sync/scheduled_generation_orchestrator.dart frontend/test/scheduled_generation_orchestrator_test.dart frontend/lib/main.dart frontend/lib/src/ui/app.dart
git commit -m "feat(front-sync): orchestrate pull-generate-push scheduled cycles"
```

---

### Task 10: Backend and Frontend Core Regression Pass

**Files:**
- Modify: `docs/context/.journal.md`

- [ ] **Step 1: Run backend regression suite**

Run: `cd /Volumes/rusty-drive/projects/pocket-pilot/backend && go test ./...`
Expected: all packages `ok`.

- [ ] **Step 2: Run frontend regression suite**

Run: `cd /Volumes/rusty-drive/projects/pocket-pilot/frontend && flutter test && flutter analyze`
Expected: tests pass, analyzer clean.

- [ ] **Step 3: Record implementation decisions in journal**

```md
* [2026-03-29] [Templates/Scheduler] Implemented transaction templates + recurring generator + transfer pair generation + deterministic UUIDv5 + template sync service/order updates.
```

- [ ] **Step 4: Commit regression + docs update**

```bash
cd /Volumes/rusty-drive/projects/pocket-pilot
git add docs/context/.journal.md
git commit -m "docs: log templates and scheduled generator implementation"
```

---

## Plan B - Tags Remediation (Start after Task 9)

### Task 11: Transaction Model and Data-Layer Tags Fix (TDD)

**Files:**
- Modify: `frontend/lib/src/features/transactions/domain/transaction.dart`
- Modify: `frontend/lib/src/features/transactions/data/transaction_repository.dart`
- Modify: `frontend/lib/src/features/transactions/data/transaction_remote_service.dart`
- Modify: `frontend/lib/src/features/transactions/data/transaction_sync_handler.dart`
- Create: `frontend/test/transaction_model_tags_test.dart`

- [ ] **Step 1: Write failing model tags serialization tests**

```dart
// frontend/test/transaction_model_tags_test.dart
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
      'amount_cents': 100,
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
}
```

- [ ] **Step 2: Run failing test**

Run: `cd /Volumes/rusty-drive/projects/pocket-pilot/frontend && flutter test test/transaction_model_tags_test.dart`
Expected: FAIL because `tags` field not present.

- [ ] **Step 3: Implement tags/templateId across model + data mapping**

```dart
// transaction.dart additions
final List<String> tags;
final String? templateId;

// toMap
'tags': jsonEncode(tags),
'template_id': templateId,

// fromMap
tags: _decodeTags(map['tags'] as String?),
templateId: map['template_id'] as String?,
```

```dart
// transaction_remote_service.dart
if (map['template_id'] != null) {
  transaction.templateId = map['template_id'] as String;
}
transaction.tags.addAll((map['tags'] as List<dynamic>? ?? []).cast<String>());
```

- [ ] **Step 4: Run targeted and full Flutter tests**

Run: `cd /Volumes/rusty-drive/projects/pocket-pilot/frontend && flutter test test/transaction_model_tags_test.dart && flutter test`
Expected: pass.

- [ ] **Step 5: Commit**

```bash
cd /Volumes/rusty-drive/projects/pocket-pilot
git add frontend/lib/src/features/transactions/domain/transaction.dart frontend/lib/src/features/transactions/data/transaction_repository.dart frontend/lib/src/features/transactions/data/transaction_remote_service.dart frontend/lib/src/features/transactions/data/transaction_sync_handler.dart frontend/test/transaction_model_tags_test.dart
git commit -m "fix(front-transactions): persist tags and template_id end-to-end"
```

---

### Task 12: Form Flows and Transfer Paths Use Tags Correctly

**Files:**
- Modify: `frontend/lib/src/features/transactions/ui/transaction_form_screen.dart`
- Modify: `frontend/lib/src/features/transactions/ui/transfer_form_screen.dart`
- Create: `frontend/test/transaction_repository_tags_test.dart`

- [ ] **Step 1: Write failing repository/form propagation test**

```dart
// frontend/test/transaction_repository_tags_test.dart
test('createTransaction passes tags to local map payload', () async {
  // fake local store captures inserted row
  // expect inserted row['tags'] contains JSON array with provided tags
});
```

- [ ] **Step 2: Run test and confirm fail**

Run: `cd /Volumes/rusty-drive/projects/pocket-pilot/frontend && flutter test test/transaction_repository_tags_test.dart`
Expected: FAIL because create/update signatures ignore tags.

- [ ] **Step 3: Update form save paths and repository signatures**

```dart
// transaction_form_screen.dart _onSave()
tags: _selectedTags.map((t) => t.name).toList(),

// in edit mode preload
_selectedTags.addAll(_allTags.where((t) => widget.transaction!.tags.contains(t.name)));
```

```dart
// transfer_form_screen.dart ensure createTransfer/updateTransfer keep passing tags
tags: _selectedTags.map((t) => t.name).toList(),
```

- [ ] **Step 4: Run full Flutter regression**

Run: `cd /Volumes/rusty-drive/projects/pocket-pilot/frontend && flutter test && flutter analyze`
Expected: green.

- [ ] **Step 5: Commit**

```bash
cd /Volumes/rusty-drive/projects/pocket-pilot
git add frontend/lib/src/features/transactions/ui/transaction_form_screen.dart frontend/lib/src/features/transactions/ui/transfer_form_screen.dart frontend/test/transaction_repository_tags_test.dart
git commit -m "fix(front-forms): propagate transaction tags from form flows"
```

---

## Final Verification Gate

- [ ] Run: `cd /Volumes/rusty-drive/projects/pocket-pilot && ./scripts/gen_proto.sh`
- [ ] Run: `cd /Volumes/rusty-drive/projects/pocket-pilot/backend && go test ./...`
- [ ] Run: `cd /Volumes/rusty-drive/projects/pocket-pilot/frontend && flutter test && flutter analyze`
- [ ] Run: `cd /Volumes/rusty-drive/projects/pocket-pilot && git status` (expect clean)

---

## Self-Review

### 1) Spec coverage check

- **Contracts/migrations:** Tasks 1-2.
- **Backend template CRUD + LWW + delete idempotency path:** Tasks 3-5.
- **Template linkage in transactions:** Task 5.
- **Flutter template data/sync + degraded backend handling:** Task 6.
- **UUIDv5/date math/generator/transfer pair logic/skip policies:** Tasks 7-9.
- **Strict orchestration pull -> generate -> push:** Task 9.
- **Tags remediation split:** Tasks 11-12.
- **Testing + regression + journal updates:** Tasks 10, Final Verification Gate.

### 2) Placeholder scan

No `TODO`, `TBD`, "implement later", or unresolved placeholders are present in task steps.

### 3) Type and naming consistency

- Canonical template frequency strings: `DAILY|WEEKLY|MONTHLY|YEARLY`.
- Canonical template type strings: `income|expense|transfer_out`.
- Generated transaction status strings: `cleared|pending`.
- `template_id` field used consistently in proto/backend/frontend mapping.
