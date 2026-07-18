# YieldConfig Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the `yield_configs` module end-to-end (proto, backend, frontend, local yield generation, and sync) with deterministic UUIDv5 occurrences and offline-first LWW behavior.

**Architecture:** Add a new syncable `yield_config` entity following the same patterns as `transaction_template`. Keep generation on Flutter client, run it inside the existing `sync -> generate -> sync` cycle, and persist generated rows in `transactions` linked via nullable `yield_id`. Backend remains passive for yield-generated transactions and enforces LWW in CRUD/sync paths.

**Tech Stack:** Flutter (Dart, sqflite, Provider, grpc), Go (gRPC, pgx, PostgreSQL), Protocol Buffers, UUID v5

**Spec:** `docs/superpowers/specs/2026-03-29-yield-config-design.md`

---

## File Structure

| File | Action | Responsibility |
|---|---|---|
| `proto/pocket_pilot/v1/yield_config_service.proto` | Create | gRPC contract for yield config sync CRUD |
| `proto/pocket_pilot/v1/transaction_service.proto` | Modify | Add `optional string yield_id = 16` |
| `scripts/gen_proto.sh` | Modify | Include new proto in Go/Dart generation |
| `backend/migrations/003_yield_configs.sql` | Create | PostgreSQL schema for `yield_configs` + transaction linkage |
| `frontend/assets/migrations/003.sql` | Create | SQLite schema for `yield_configs` + transaction linkage |
| `frontend/lib/src/core/db/database_helper.dart` | Modify | Bump DB version to 3 |
| `backend/internal/yieldconfig/model.go` | Create | Domain model + lowercase normalization helpers |
| `backend/internal/yieldconfig/validation.go` | Create | Server validation rules |
| `backend/internal/yieldconfig/validation_test.go` | Create | Validation rule tests |
| `backend/internal/yieldconfig/repository.go` | Create | LWW list/upsert/delete persistence |
| `backend/internal/yieldconfig/handler.go` | Create | gRPC handler + proto/date mapping |
| `backend/cmd/server/main.go` | Modify | Register `YieldConfigService` |
| `backend/internal/transaction/repository.go` | Modify | Persist and return `yield_id` |
| `backend/internal/transaction/handler.go` | Modify | Map proto optional `yield_id` |
| `frontend/lib/src/core/ids/deterministic_namespace.dart` | Modify | Add `kDeterministicYieldNamespace` |
| `frontend/lib/src/features/yield_configs/domain/yield_config.dart` | Create | Yield model (`toMap/fromMap/fromProto/toServerMap`) |
| `frontend/lib/src/features/yield_configs/domain/yield_schedule_date_math.dart` | Create | Date advancement + `days_elapsed` helpers |
| `frontend/lib/src/features/yield_configs/domain/yield_interest_math.dart` | Create | Simple interest cents math |
| `frontend/lib/src/features/yield_configs/data/yield_config_local_store.dart` | Create | SQLite DAO |
| `frontend/lib/src/features/yield_configs/data/yield_config_repository.dart` | Create | Local-first writes + outbox |
| `frontend/lib/src/features/yield_configs/data/yield_config_remote_service.dart` | Create | gRPC client adapter |
| `frontend/lib/src/features/yield_configs/data/yield_config_sync_handler.dart` | Create | Sync handler (`entityType=yield_config`) |
| `frontend/lib/src/features/yield_configs/data/yield_transaction_generator.dart` | Create | Local deterministic yield generation |
| `frontend/lib/src/core/sync/composite_scheduled_generator_runner.dart` | Create | Run template + yield generators in sequence |
| `frontend/lib/main.dart` | Modify | Wire sync handler + composite generator |
| `frontend/lib/src/features/transactions/domain/transaction.dart` | Modify | Add `yieldId` mapping |
| `frontend/lib/src/features/transactions/data/transaction_remote_service.dart` | Modify | Send `yield_id` in upsert |
| `frontend/lib/src/features/transactions/data/transaction_sync_handler.dart` | Modify | Persist `yield_id` from server payload |
| `frontend/test/yield_schedule_date_math_test.dart` | Create | Date and `days_elapsed` tests |
| `frontend/test/yield_interest_math_test.dart` | Create | Interest rounding tests |
| `frontend/test/yield_transaction_generator_test.dart` | Create | Generator behavior/idempotency tests |
| `frontend/test/composite_scheduled_generator_runner_test.dart` | Create | Composite runner order tests |
| `docs/context/.journal.md` | Modify | Session log entry |

---

### Task 1: Proto Contracts and Code Generation

**Files:**
- Create: `proto/pocket_pilot/v1/yield_config_service.proto`
- Modify: `proto/pocket_pilot/v1/transaction_service.proto`
- Modify: `scripts/gen_proto.sh`

- [ ] **Step 1: Add `yield_config_service.proto`**

```proto
syntax = "proto3";

package pocket_pilot.v1;

import "pocket_pilot/v1/common.proto";
import "google/protobuf/empty.proto";
import "google/protobuf/timestamp.proto";

option go_package = "github.com/AlanIsaacV/pocket-pilot/backend/internal/gen/proto/pocket_pilot/v1;pocketpilotv1";

message YieldConfig {
  string id = 1;
  string account_id = 2;
  string name = 3;
  int64 amount_cents = 4;
  double apy_rate = 5;
  string payout_frequency = 6;
  string next_date = 7;
  optional string maturity_date = 8;
  bool auto_renew = 9;
  string status = 10;
  google.protobuf.Timestamp created_at = 11;
  google.protobuf.Timestamp updated_at = 12;
  google.protobuf.Timestamp deleted_at = 13;
  optional int32 term_days = 14;
}

service YieldConfigService {
  rpc ListYieldConfigs(ListYieldConfigsRequest) returns (ListYieldConfigsResponse);
  rpc UpsertYieldConfig(UpsertYieldConfigRequest) returns (UpsertYieldConfigResponse);
  rpc DeleteYieldConfig(DeleteYieldConfigRequest) returns (google.protobuf.Empty);
}

message ListYieldConfigsRequest {
  google.protobuf.Timestamp updated_since = 1;
  PageRequest page = 2;
}

message ListYieldConfigsResponse {
  repeated YieldConfig configs = 1;
  PageResponse page = 2;
  google.protobuf.Timestamp synced_at = 3;
}

message UpsertYieldConfigRequest {
  YieldConfig config = 1;
}

message UpsertYieldConfigResponse {
  YieldConfig config = 1;
  bool conflict_resolved = 2;
}

message DeleteYieldConfigRequest {
  string id = 1;
  google.protobuf.Timestamp deleted_at = 2;
}
```

- [ ] **Step 2: Extend transaction contract with `yield_id`**

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
  optional string yield_id = 16;
}
```

- [ ] **Step 3: Include new proto in generation script**

```bash
# scripts/gen_proto.sh
# Add to BOTH protoc invocations:
pocket_pilot/v1/yield_config_service.proto
```

- [ ] **Step 4: Regenerate stubs**

Run: `cd /Volumes/rusty-drive/projects/pocket-pilot && make proto`

Expected: `✓ Done. Generated files:` and no protoc errors.

- [ ] **Step 5: Commit**

```bash
cd /Volumes/rusty-drive/projects/pocket-pilot
git add proto/pocket_pilot/v1/yield_config_service.proto proto/pocket_pilot/v1/transaction_service.proto scripts/gen_proto.sh backend/internal/gen frontend/lib/src/generated
git commit -m "feat(proto): add yield config service and transaction yield_id"
```

---

### Task 2: Database Migrations (PostgreSQL + SQLite)

**Files:**
- Create: `backend/migrations/003_yield_configs.sql`
- Create: `frontend/assets/migrations/003.sql`
- Modify: `frontend/lib/src/core/db/database_helper.dart`

- [ ] **Step 1: Add PostgreSQL migration**

```sql
-- backend/migrations/003_yield_configs.sql
CREATE TABLE yield_configs (
    id               uuid PRIMARY KEY      DEFAULT gen_random_uuid(),
    user_id          uuid         NOT NULL,
    account_id       uuid         NOT NULL REFERENCES accounts (id),
    name             TEXT         NOT NULL,
    amount_cents     BIGINT       NOT NULL,
    apy_rate         NUMERIC(7,4) NOT NULL,
    payout_frequency TEXT         NOT NULL,
    next_date        DATE         NOT NULL,
    maturity_date    DATE,
    term_days        INTEGER,
    auto_renew       BOOLEAN      NOT NULL DEFAULT FALSE,
    status           TEXT         NOT NULL,
    created_at       timestamptz  NOT NULL DEFAULT NOW(),
    updated_at       timestamptz  NOT NULL DEFAULT NOW(),
    deleted_at       timestamptz
);

CREATE INDEX idx_yield_configs_user_updated_at
    ON yield_configs (user_id, updated_at);

CREATE INDEX idx_yield_configs_user_next_date_active
    ON yield_configs (user_id, next_date)
    WHERE deleted_at IS NULL AND status = 'active';

ALTER TABLE transactions
    ADD COLUMN yield_id uuid REFERENCES yield_configs (id);

CREATE INDEX idx_transactions_yield_id
    ON transactions (yield_id)
    WHERE yield_id IS NOT NULL;

CREATE TRIGGER set_updated_at_yield_configs
    BEFORE UPDATE
    ON yield_configs
    FOR EACH ROW
EXECUTE FUNCTION trigger_set_updated_at();
```

- [ ] **Step 2: Add SQLite migration**

```sql
-- frontend/assets/migrations/003.sql
CREATE TABLE yield_configs (
    id               TEXT PRIMARY KEY,
    account_id       TEXT     NOT NULL REFERENCES accounts (id),
    name             TEXT     NOT NULL,
    amount_cents     BIGINT   NOT NULL,
    apy_rate         NUMERIC(7,4) NOT NULL,
    payout_frequency TEXT     NOT NULL,
    next_date        DATE     NOT NULL,
    maturity_date    DATE,
    term_days        INTEGER,
    auto_renew       INTEGER  NOT NULL DEFAULT 0,
    status           TEXT     NOT NULL,
    created_at       DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at       DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    deleted_at       DATETIME
);

CREATE INDEX idx_yield_configs_next_date_active
    ON yield_configs (next_date)
    WHERE deleted_at IS NULL AND status = 'active';

CREATE INDEX idx_yield_configs_updated_at
    ON yield_configs (updated_at);

CREATE TRIGGER set_updated_at_yield_configs
    AFTER UPDATE
    ON yield_configs
    FOR EACH ROW
    WHEN new.updated_at = old.updated_at
BEGIN
    UPDATE yield_configs
    SET updated_at = CURRENT_TIMESTAMP
    WHERE id = new.id;
END;

ALTER TABLE transactions
    ADD COLUMN yield_id TEXT REFERENCES yield_configs (id);

CREATE INDEX idx_transactions_yield_id
    ON transactions (yield_id)
    WHERE yield_id IS NOT NULL;
```

- [ ] **Step 3: Bump frontend schema version**

```dart
// frontend/lib/src/core/db/database_helper.dart
static const int _version = 3;
```

- [ ] **Step 4: Validate migration wiring compiles**

Run: `cd /Volumes/rusty-drive/projects/pocket-pilot/frontend && flutter analyze lib/src/core/db/database_helper.dart`

Expected: `No issues found!`

- [ ] **Step 5: Commit**

```bash
cd /Volumes/rusty-drive/projects/pocket-pilot
git add backend/migrations/003_yield_configs.sql frontend/assets/migrations/003.sql frontend/lib/src/core/db/database_helper.dart
git commit -m "feat(db): add yield_configs schema and transaction yield linkage"
```

---

### Task 3: Backend YieldConfig Model and Validation (TDD)

**Files:**
- Create: `backend/internal/yieldconfig/model.go`
- Create: `backend/internal/yieldconfig/validation.go`
- Create: `backend/internal/yieldconfig/validation_test.go`

- [ ] **Step 1: Write failing validation tests**

```go
// backend/internal/yieldconfig/validation_test.go
package yieldconfig

import (
    "testing"
    "time"
)

func TestValidateYieldConfig(t *testing.T) {
    next := dateOnly(time.Date(2026, 4, 1, 0, 0, 0, 0, time.UTC))
    maturity := dateOnly(time.Date(2026, 6, 30, 0, 0, 0, 0, time.UTC))
    term90 := int32(90)

    tests := []struct {
        name    string
        cfg     YieldConfig
        wantErr bool
    }{
        {
            name: "valid daily active",
            cfg: YieldConfig{AmountCents: 100000, ApyRate: 14.5, PayoutFrequency: "daily", NextDate: next, Status: "active"},
            wantErr: false,
        },
        {
            name: "invalid status",
            cfg: YieldConfig{AmountCents: 100000, ApyRate: 14.5, PayoutFrequency: "daily", NextDate: next, Status: "running"},
            wantErr: true,
        },
        {
            name: "at_maturity missing term_days",
            cfg: YieldConfig{AmountCents: 100000, ApyRate: 14.5, PayoutFrequency: "at_maturity", NextDate: maturity, MaturityDate: &maturity, Status: "active"},
            wantErr: true,
        },
        {
            name: "at_maturity valid",
            cfg: YieldConfig{AmountCents: 100000, ApyRate: 14.5, PayoutFrequency: "at_maturity", NextDate: maturity, MaturityDate: &maturity, TermDays: &term90, Status: "active"},
            wantErr: false,
        },
    }

    for _, tc := range tests {
        t.Run(tc.name, func(t *testing.T) {
            err := ValidateYieldConfig(tc.cfg)
            if tc.wantErr && err == nil {
                t.Fatalf("expected error")
            }
            if !tc.wantErr && err != nil {
                t.Fatalf("unexpected error: %v", err)
            }
        })
    }
}
```

- [ ] **Step 2: Run test to verify failure**

Run: `cd /Volumes/rusty-drive/projects/pocket-pilot/backend && go test ./internal/yieldconfig -run TestValidateYieldConfig -v`

Expected: FAIL (package/files missing).

- [ ] **Step 3: Implement model + validation**

```go
// backend/internal/yieldconfig/model.go
package yieldconfig

import (
    "strings"
    "time"

    "github.com/google/uuid"
)

type YieldConfig struct {
    ID              uuid.UUID
    UserID          uuid.UUID
    AccountID       uuid.UUID
    Name            string
    AmountCents     int64
    ApyRate         float64
    PayoutFrequency string
    NextDate        time.Time
    MaturityDate    *time.Time
    TermDays        *int32
    AutoRenew       bool
    Status          string
    CreatedAt       time.Time
    UpdatedAt       time.Time
    DeletedAt       *time.Time
}

func dateOnly(t time.Time) time.Time {
    utc := t.UTC()
    return time.Date(utc.Year(), utc.Month(), utc.Day(), 0, 0, 0, 0, time.UTC)
}

func normalizeLower(value string) string {
    return strings.ToLower(strings.TrimSpace(value))
}
```

```go
// backend/internal/yieldconfig/validation.go
package yieldconfig

import "fmt"

func ValidateYieldConfig(cfg YieldConfig) error {
    status := normalizeLower(cfg.Status)
    freq := normalizeLower(cfg.PayoutFrequency)

    if status != "active" && status != "paused" && status != "completed" {
        return fmt.Errorf("invalid status")
    }
    if freq != "daily" && freq != "weekly" && freq != "monthly" && freq != "at_maturity" {
        return fmt.Errorf("invalid payout_frequency")
    }
    if cfg.AmountCents <= 0 {
        return fmt.Errorf("amount_cents must be > 0")
    }
    if cfg.ApyRate < 0 {
        return fmt.Errorf("apy_rate must be >= 0")
    }
    if freq == "at_maturity" {
        if cfg.TermDays == nil || *cfg.TermDays <= 0 {
            return fmt.Errorf("at_maturity requires term_days > 0")
        }
        if cfg.MaturityDate == nil {
            return fmt.Errorf("at_maturity requires maturity_date")
        }
        if !dateOnly(cfg.NextDate).Equal(dateOnly(*cfg.MaturityDate)) {
            return fmt.Errorf("at_maturity requires next_date == maturity_date")
        }
    }
    if cfg.AutoRenew && cfg.MaturityDate != nil {
        if cfg.TermDays == nil || *cfg.TermDays <= 0 {
            return fmt.Errorf("auto_renew requires term_days > 0 when maturity_date is set")
        }
    }
    return nil
}
```

- [ ] **Step 4: Run validation tests**

Run: `cd /Volumes/rusty-drive/projects/pocket-pilot/backend && go test ./internal/yieldconfig -v`

Expected: `ok` for `internal/yieldconfig`.

- [ ] **Step 5: Commit**

```bash
cd /Volumes/rusty-drive/projects/pocket-pilot
git add backend/internal/yieldconfig/model.go backend/internal/yieldconfig/validation.go backend/internal/yieldconfig/validation_test.go
git commit -m "feat(back-yield): add model and validation rules"
```

---

### Task 4: Backend YieldConfig Repository, Handler, and Server Wiring

**Files:**
- Create: `backend/internal/yieldconfig/repository.go`
- Create: `backend/internal/yieldconfig/handler.go`
- Modify: `backend/cmd/server/main.go`

- [ ] **Step 1: Implement repository with LWW semantics**

```go
// backend/internal/yieldconfig/repository.go (core constants)
const scanColumns = `id, user_id, account_id, name, amount_cents, apy_rate, payout_frequency, next_date, maturity_date, term_days, auto_renew, status, created_at, updated_at, deleted_at`

// Upsert WHERE clause must be:
// WHERE yield_configs.updated_at < EXCLUDED.updated_at
```

- [ ] **Step 2: Implement handler proto mapping and normalization**

```go
// backend/internal/yieldconfig/handler.go (required behavior)
// - parse date-only strings using format "2006-01-02"
// - normalize status/frequency to lowercase before ValidateYieldConfig + repo.Upsert
// - list: full sync paginated non-deleted rows; delta ignores request.page
// - delete: missing row is idempotent success
```

- [ ] **Step 3: Register service in gRPC startup**

```go
// backend/cmd/server/main.go
import "github.com/AlanIsaacV/pocket-pilot/internal/yieldconfig"

yieldConfigHandler := yieldconfig.NewHandler(yieldconfig.NewRepository(pool))
pb.RegisterYieldConfigServiceServer(srv, yieldConfigHandler)
```

- [ ] **Step 4: Run backend compilation/tests**

Run: `cd /Volumes/rusty-drive/projects/pocket-pilot/backend && go test ./...`

Expected: all backend packages pass.

- [ ] **Step 5: Commit**

```bash
cd /Volumes/rusty-drive/projects/pocket-pilot
git add backend/internal/yieldconfig/repository.go backend/internal/yieldconfig/handler.go backend/cmd/server/main.go
git commit -m "feat(back-yield): add repository handler and service registration"
```

---

### Task 5: Backend Transactions `yield_id` Mapping

**Files:**
- Modify: `backend/internal/transaction/repository.go`
- Modify: `backend/internal/transaction/handler.go`

- [ ] **Step 1: Add nullable `YieldID` to model and scan columns**

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
    // ...
}

const scanColumns = `id, user_id, account_id, category_id, linked_transaction_id, template_id, yield_id, type, amount_cents, currency_code, status, tags, description, date, created_at, updated_at, deleted_at`
```

- [ ] **Step 2: Persist `yield_id` in SQL upsert path**

```sql
INSERT INTO transactions (..., template_id, yield_id, type, ...)
VALUES (...)
ON CONFLICT (id) DO UPDATE SET
    template_id = EXCLUDED.template_id,
    yield_id = EXCLUDED.yield_id,
    ...
WHERE transactions.updated_at < EXCLUDED.updated_at
```

- [ ] **Step 3: Map optional proto `yield_id` in handler**

```go
// toProto
if t.YieldID != nil {
    s := t.YieldID.String()
    proto.YieldId = &s
}

// fromProto
if p.YieldId != nil && *p.YieldId != "" {
    yid, err := parseUUID(*p.YieldId, "transaction.yield_id")
    if err != nil {
        return nil, err
    }
    yieldID = &yid
}
```

- [ ] **Step 4: Run backend tests**

Run: `cd /Volumes/rusty-drive/projects/pocket-pilot/backend && go test ./...`

Expected: all pass.

- [ ] **Step 5: Commit**

```bash
cd /Volumes/rusty-drive/projects/pocket-pilot
git add backend/internal/transaction/repository.go backend/internal/transaction/handler.go
git commit -m "feat(back-transactions): persist optional yield_id linkage"
```

---

### Task 6: Flutter YieldConfig Domain, Data, Remote, and Sync

**Files:**
- Create: `frontend/lib/src/features/yield_configs/domain/yield_config.dart`
- Create: `frontend/lib/src/features/yield_configs/data/yield_config_local_store.dart`
- Create: `frontend/lib/src/features/yield_configs/data/yield_config_repository.dart`
- Create: `frontend/lib/src/features/yield_configs/data/yield_config_remote_service.dart`
- Create: `frontend/lib/src/features/yield_configs/data/yield_config_sync_handler.dart`
- Modify: `frontend/lib/main.dart`
- Modify: `frontend/lib/src/features/transactions/data/transaction_sync_handler.dart`

- [ ] **Step 1: Add domain model with normalization + mapping**

```dart
// frontend/lib/src/features/yield_configs/domain/yield_config.dart
class YieldConfigModel {
  final String id;
  final String accountId;
  final String name;
  final int amountCents;
  final double apyRate;
  final String payoutFrequency; // lowercase
  final String nextDate;        // YYYY-MM-DD
  final String? maturityDate;   // YYYY-MM-DD
  final int? termDays;
  final bool autoRenew;
  final String status;          // lowercase
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  // include fromMap(), toMap(), fromProto(), toServerMap() with lowercase normalization
}
```

- [ ] **Step 2: Implement local store + repository with outbox writes**

```dart
// yield_config_local_store.dart required methods
Future<List<Map<String, dynamic>>> queryRows();
Future<List<Map<String, dynamic>>> querySchedulableRows({required String horizonDate});
Future<void> upsertRow(Map<String, dynamic> row);
Future<void> upsertRows(List<Map<String, dynamic>> rows);
Future<void> softDelete(String id, DateTime deletedAt);
```

```dart
// yield_config_repository.dart required behavior
// - normalize status/frequency before local write and before outbox payload
// - enqueue entity_type: 'yield_config'
```

- [ ] **Step 3: Implement remote service and sync handler**

```dart
// yield_config_sync_handler.dart
@override
String get entityType => 'yield_config';

@override
int get syncOrder => 5;
```

`pull` must map `deleted_at`, `term_days`, and lowercase normalization defensively before save.

- [ ] **Step 4: Wire handler order in app startup**

```dart
// frontend/lib/main.dart handlers order
handlers: [
  accountSyncHandler,
  categorySyncHandler,
  tagSyncHandler,
  transactionTemplateSyncHandler,
  yieldConfigSyncHandler,
  transactionSyncHandler,
  userPreferenceSyncHandler,
]
```

Also bump `TransactionSyncHandler.syncOrder` from `5` to `6`.

- [ ] **Step 5: Run Flutter analyze/tests**

Run: `cd /Volumes/rusty-drive/projects/pocket-pilot/frontend && flutter analyze && flutter test`

Expected: no analyzer errors and tests green.

- [ ] **Step 6: Commit**

```bash
cd /Volumes/rusty-drive/projects/pocket-pilot
git add frontend/lib/main.dart frontend/lib/src/features/yield_configs frontend/lib/src/features/transactions/data/transaction_sync_handler.dart
git commit -m "feat(front-yield): add yield config local/remote/sync layers"
```

---

### Task 7: Flutter Transaction `yield_id` Mapping

**Files:**
- Modify: `frontend/lib/src/features/transactions/domain/transaction.dart`
- Modify: `frontend/lib/src/features/transactions/data/transaction_remote_service.dart`
- Modify: `frontend/lib/src/features/transactions/data/transaction_sync_handler.dart`

- [ ] **Step 1: Add `yieldId` in transaction model mapping**

```dart
// frontend/lib/src/features/transactions/domain/transaction.dart
final String? yieldId;

// fromProto
yieldId: proto.hasYieldId() ? proto.yieldId : null,

// fromMap
yieldId: map['yield_id'] as String?,

// toMap/toServerMap
'yield_id': yieldId,
```

- [ ] **Step 2: Send optional `yield_id` in remote upsert payload**

```dart
// frontend/lib/src/features/transactions/data/transaction_remote_service.dart
if (map['yield_id'] != null) {
  transaction.yieldId = map['yield_id'] as String;
}
```

- [ ] **Step 3: Preserve `yield_id` in conflict save path**

```dart
// frontend/lib/src/features/transactions/data/transaction_sync_handler.dart
final model = TransactionModel.fromProto(response.transaction);
final serverRow = <String, dynamic>{
  ...model.toMap(),
  'deleted_at': response.transaction.hasDeletedAt()
      ? response.transaction.deletedAt.toDateTime().toUtc().toIso8601String()
      : null,
};
```

- [ ] **Step 4: Run transaction-focused tests**

Run: `cd /Volumes/rusty-drive/projects/pocket-pilot/frontend && flutter test test/transaction_model_tags_test.dart`

Expected: pass (no regression on existing transaction mapping tests).

- [ ] **Step 5: Commit**

```bash
cd /Volumes/rusty-drive/projects/pocket-pilot
git add frontend/lib/src/features/transactions/domain/transaction.dart frontend/lib/src/features/transactions/data/transaction_remote_service.dart frontend/lib/src/features/transactions/data/transaction_sync_handler.dart
git commit -m "feat(front-transactions): map optional yield_id end-to-end"
```

---

### Task 8: Yield Date/Math Helpers (TDD)

**Files:**
- Modify: `frontend/lib/src/core/ids/deterministic_namespace.dart`
- Create: `frontend/lib/src/features/yield_configs/domain/yield_schedule_date_math.dart`
- Create: `frontend/lib/src/features/yield_configs/domain/yield_interest_math.dart`
- Create: `frontend/test/yield_schedule_date_math_test.dart`
- Create: `frontend/test/yield_interest_math_test.dart`

- [ ] **Step 1: Write failing helper tests**

```dart
// frontend/test/yield_schedule_date_math_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_pilot/src/features/yield_configs/domain/yield_schedule_date_math.dart';

void main() {
  test('monthly previous anchor from 2026-03-31 is 2026-02-28', () {
    expect(previousScheduleDate('monthly', '2026-03-31', termDays: null), '2026-02-28');
  });

  test('at_maturity next date uses term_days', () {
    expect(nextScheduleDate('at_maturity', '2026-06-30', termDays: 90), '2026-09-28');
  });
}
```

```dart
// frontend/test/yield_interest_math_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_pilot/src/features/yield_configs/domain/yield_interest_math.dart';

void main() {
  test('simple interest rounds to nearest cent', () {
    expect(computeInterestCents(amountCents: 100000, apyRate: 14.5, daysElapsed: 30), 1192);
  });

  test('tiny values can round to zero', () {
    expect(computeInterestCents(amountCents: 1, apyRate: 1.0, daysElapsed: 1), 0);
  });
}
```

- [ ] **Step 2: Run tests to verify failure**

Run: `cd /Volumes/rusty-drive/projects/pocket-pilot/frontend && flutter test test/yield_schedule_date_math_test.dart test/yield_interest_math_test.dart`

Expected: FAIL (files/functions missing).

- [ ] **Step 3: Implement helpers and namespace constant**

```dart
// frontend/lib/src/core/ids/deterministic_namespace.dart
const kDeterministicTemplateNamespace = 'f3b6f4d2-5c8b-4f87-9f03-2ec2f7d32651';
const kDeterministicYieldNamespace = '9b7dc9b8-9e4f-4e0b-a178-6f6b1b39b4f1';
```

```dart
// frontend/lib/src/features/yield_configs/domain/yield_interest_math.dart
int computeInterestCents({
  required int amountCents,
  required double apyRate,
  required int daysElapsed,
}) {
  final raw = amountCents * (apyRate / 100.0) * (daysElapsed / 365.0);
  return raw.round();
}
```

- [ ] **Step 4: Run helper tests again**

Run: `cd /Volumes/rusty-drive/projects/pocket-pilot/frontend && flutter test test/yield_schedule_date_math_test.dart test/yield_interest_math_test.dart`

Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
cd /Volumes/rusty-drive/projects/pocket-pilot
git add frontend/lib/src/core/ids/deterministic_namespace.dart frontend/lib/src/features/yield_configs/domain/yield_schedule_date_math.dart frontend/lib/src/features/yield_configs/domain/yield_interest_math.dart frontend/test/yield_schedule_date_math_test.dart frontend/test/yield_interest_math_test.dart
git commit -m "feat(front-yield): add deterministic namespace and yield math helpers"
```

---

### Task 9: Yield Transaction Generator (TDD)

**Files:**
- Create: `frontend/lib/src/features/yield_configs/data/yield_transaction_generator.dart`
- Create: `frontend/test/yield_transaction_generator_test.dart`

- [ ] **Step 1: Write failing generator behavior tests**

```dart
// frontend/test/yield_transaction_generator_test.dart
test('generates deterministic income transaction with yield_id linkage', () async {
  // arrange one active daily config with next_date=today
  // act run generator twice
  // assert one insert only and outbox one transaction upsert
});

test('marks completed when maturity passed and no auto_renew', () async {
  // arrange at_maturity config with cursor beyond maturity
  // assert status completed and no new transactions
});

test('auto_renew at_maturity advances maturity by term_days', () async {
  // arrange at_maturity auto_renew config
  // assert maturity/next_date moved to next boundary
});

test('interest zero advances cursor but does not create transaction', () async {
  // arrange tiny amount + low APY
  // assert no inserted rows, cursor advanced, config upsert enqueued
});
```

- [ ] **Step 2: Run test and verify failure**

Run: `cd /Volumes/rusty-drive/projects/pocket-pilot/frontend && flutter test test/yield_transaction_generator_test.dart`

Expected: FAIL (generator missing).

- [ ] **Step 3: Implement generator with deterministic UUIDv5 and policy matrix**

```dart
// frontend/lib/src/features/yield_configs/data/yield_transaction_generator.dart
class YieldTransactionGenerator implements ScheduledGeneratorRunner {
  @override
  Future<YieldGenerationReport> run({required DateTime nowUtc}) async {
    // - query active, non-deleted, next_date <= horizon
    // - while cursor <= horizon
    // - handle maturity + auto_renew rules
    // - compute daysElapsed and interest_cents
    // - if interest_cents > 0 insert transaction with
    //   id = uuid.v5(kDeterministicYieldNamespace, '${cfg.id}-$cursor')
    // - status cleared/pending
    // - category_id null, yield_id cfg.id
    // - insert ignore + enqueue outbox only if inserted
    // - persist cfg cursor/status/maturity updates
  }
}
```

- [ ] **Step 4: Run generator tests and full Flutter tests**

Run: `cd /Volumes/rusty-drive/projects/pocket-pilot/frontend && flutter test test/yield_transaction_generator_test.dart && flutter test`

Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
cd /Volumes/rusty-drive/projects/pocket-pilot
git add frontend/lib/src/features/yield_configs/data/yield_transaction_generator.dart frontend/test/yield_transaction_generator_test.dart
git commit -m "feat(front-yield): implement local yield transaction generator"
```

---

### Task 10: Composite Generation Runner and App Wiring

**Files:**
- Create: `frontend/lib/src/core/sync/composite_scheduled_generator_runner.dart`
- Create: `frontend/test/composite_scheduled_generator_runner_test.dart`
- Modify: `frontend/lib/main.dart`

- [ ] **Step 1: Write failing order test**

```dart
// frontend/test/composite_scheduled_generator_runner_test.dart
test('composite runner executes child generators in order', () async {
  // fake runner A and B append names to list
  // expect order ['templates', 'yields']
});
```

- [ ] **Step 2: Run test and verify failure**

Run: `cd /Volumes/rusty-drive/projects/pocket-pilot/frontend && flutter test test/composite_scheduled_generator_runner_test.dart`

Expected: FAIL (composite runner missing).

- [ ] **Step 3: Implement composite runner**

```dart
// frontend/lib/src/core/sync/composite_scheduled_generator_runner.dart
import 'scheduled_generation_orchestrator.dart';

class CompositeScheduledGeneratorRunner implements ScheduledGeneratorRunner {
  final List<ScheduledGeneratorRunner> _runners;

  CompositeScheduledGeneratorRunner({required List<ScheduledGeneratorRunner> runners})
      : _runners = List<ScheduledGeneratorRunner>.unmodifiable(runners);

  @override
  Future<Object?> run({required DateTime nowUtc}) async {
    for (final runner in _runners) {
      await runner.run(nowUtc: nowUtc);
    }
    return null;
  }
}
```

- [ ] **Step 4: Wire template + yield generators in `main.dart`**

```dart
final compositeGenerator = CompositeScheduledGeneratorRunner(
  runners: [
    scheduledGenerator,
    yieldGenerator,
  ],
);

final scheduledOrchestrator = ScheduledGenerationOrchestrator(
  sync: syncService,
  generator: compositeGenerator,
);
```

- [ ] **Step 5: Run Flutter regression/analyze**

Run: `cd /Volumes/rusty-drive/projects/pocket-pilot/frontend && flutter test && flutter analyze`

Expected: all green.

- [ ] **Step 6: Commit**

```bash
cd /Volumes/rusty-drive/projects/pocket-pilot
git add frontend/lib/src/core/sync/composite_scheduled_generator_runner.dart frontend/test/composite_scheduled_generator_runner_test.dart frontend/lib/main.dart
git commit -m "feat(front-sync): run template and yield generators in one cycle"
```

---

### Task 11: Final Verification and Journal Update

**Files:**
- Modify: `docs/context/.journal.md`

- [ ] **Step 1: Run proto generation gate**

Run: `cd /Volumes/rusty-drive/projects/pocket-pilot && make proto`

Expected: successful generation output.

- [ ] **Step 2: Run backend regression gate**

Run: `cd /Volumes/rusty-drive/projects/pocket-pilot/backend && go test ./...`

Expected: all packages `ok`.

- [ ] **Step 3: Run frontend regression gate**

Run: `cd /Volumes/rusty-drive/projects/pocket-pilot/frontend && flutter test && flutter analyze`

Expected: all tests pass and analyzer clean.

- [ ] **Step 4: Log implementation summary**

```md
* [2026-03-29] [YieldConfig] Implemented `yield_configs` end-to-end: proto + migrations + backend service/repository + frontend data/sync + deterministic local yield generator + `transactions.yield_id` linkage and orchestration integration.
```

- [ ] **Step 5: Commit**

```bash
cd /Volumes/rusty-drive/projects/pocket-pilot
git add docs/context/.journal.md
git commit -m "docs: log yield config implementation rollout"
```

---

## Final Verification Gate

- [ ] Run: `cd /Volumes/rusty-drive/projects/pocket-pilot && make proto`
- [ ] Run: `cd /Volumes/rusty-drive/projects/pocket-pilot/backend && go test ./...`
- [ ] Run: `cd /Volumes/rusty-drive/projects/pocket-pilot/frontend && flutter test && flutter analyze`
- [ ] Run: `cd /Volumes/rusty-drive/projects/pocket-pilot && git status` (expect clean)

---

## Self-Review

### 1) Spec coverage check

- Contracts (`YieldConfigService`, `Transaction.yield_id`): Task 1.
- DB schema (`yield_configs`, `transactions.yield_id`, `term_days`): Task 2.
- Backend CRUD/sync + LWW + lowercase normalization: Tasks 3-4.
- Backend passive transaction linkage for `yield_id`: Task 5.
- Frontend local/outbox/sync module for `yield_config`: Task 6.
- Local lowercase normalization in repository and pull mapping: Task 6.
- Deterministic UUID namespace + date/math helpers: Task 8.
- Generator loop behavior (horizon, maturity, auto-renew, zero-interest skip): Task 9.
- Shared generation cycle integration (`sync -> generate -> sync`): Task 10.
- Regression gates and journal entry: Task 11 + Final Verification Gate.

### 2) Placeholder scan

- No `TODO`, `TBD`, or unresolved implementation placeholders are used.
- Each task includes explicit file targets, commands, and expected outcomes.

### 3) Type and naming consistency

- Canonical persisted values: `status` and `payout_frequency` lowercase.
- Transaction linkage field is consistently named `yield_id` across proto/backend/frontend.
- Generator uses `kDeterministicYieldNamespace` for UUIDv5 in tests and runtime.
- Sync entity type is consistently `yield_config`.
