# Sync Preflight Cursors Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a per-user, per-entity cursor table in PostgreSQL and a `SyncService.GetSyncStatus()` preflight RPC so the Flutter client can skip full delta-pulls for entities that did not change since the last sync.

**Architecture:** A new `backend/internal/sync` package owns a `user_sync_cursors` table and a `CursorStore` helper. Every existing repository calls `CursorStore.Bump` inside the same transaction as its `Upsert`/`SoftDelete` write. A new gRPC service returns the per-entity cursors in a single call. The Flutter `SyncService` runs this preflight once per sync cycle, compares against its local `sync_metadata`, and skips pulls when the server cursor is not newer than the local one. If the preflight fails, the client falls back to the current behavior (9 pulls).

**Tech Stack:** Go 1.22 + pgx v5 + gRPC + PostgreSQL 16 (backend); Flutter + SQLite + grpc-dart (frontend); protoc for code generation.

**Spec:** `/Volumes/rusty-drive/projects/pocket-pilot/docs/superpowers/specs/2026-04-16-sync-preflight-cursors-design.md`

---

## File Structure

### New files

| Path | Responsibility |
|------|----------------|
| `backend/migrations/002_sync_cursors.sql` | PostgreSQL schema for `user_sync_cursors`. |
| `backend/internal/sync/entity_type.go` | `EntityType` constants + `AllEntityTypes()`. |
| `backend/internal/sync/cursor.go` | `CursorStore.Bump` and `CursorStore.GetAll`. |
| `backend/internal/sync/cursor_test.go` | Integration tests for `CursorStore`. |
| `backend/internal/sync/handler.go` | `Handler` implementing `pb.SyncServiceServer`. |
| `backend/internal/sync/cursor_integration_test.go` | Per-repo integration tests verifying bump on Upsert/SoftDelete. |
| `backend/internal/testdb/testdb.go` | Test helper that opens a pool against `TEST_DATABASE_URL` or skips. |
| `proto/pocket_pilot/v1/sync_service.proto` | `SyncService.GetSyncStatus` RPC. |
| `frontend/lib/src/core/sync/sync_status_remote_service.dart` | Thin gRPC wrapper over `SyncService.GetSyncStatus`. |

### Modified files

| Path | What changes |
|------|--------------|
| `backend/cmd/server/main.go` | Build one `sync.CursorStore`, inject into every repo constructor, register `sync.Handler`. |
| `backend/internal/account/repository.go` | `Upsert` + `SoftDelete` become transactional and call `cursor.Bump`. Constructor accepts `*sync.CursorStore`. |
| `backend/internal/transaction/repository.go` | Same pattern. `SoftDelete` already uses a tx — just add the bump. |
| `backend/internal/category/repository.go` | Same pattern. |
| `backend/internal/tag/repository.go` | Same pattern. |
| `backend/internal/transactiontemplate/repository.go` | Same pattern. |
| `backend/internal/goal/repository.go` | Same pattern. |
| `backend/internal/budget/repository.go` | Same pattern. |
| `backend/internal/yieldconfig/repository.go` | Same pattern. |
| `backend/internal/userpreference/repository.go` | Same pattern (note: `SoftDelete(userID, prefKey, deletedAt)` signature differs). |
| `frontend/lib/src/core/sync/sync_service.dart` | Inject `SyncStatusRemoteService`; add preflight + skip loop + `lastCycleSkippedCount`. |
| `frontend/lib/main.dart` | Wire `SyncStatusRemoteService` into `SyncService`. |
| `frontend/lib/src/ui/screens/settings/sync_status_screen.dart` | Display `lastCycleSkippedCount` in the details card. |

---

## Task 1: Migration `002_sync_cursors.sql`

**Files:**
- Create: `backend/migrations/002_sync_cursors.sql`

- [ ] **Step 1: Write the migration**

```sql
-- 002_sync_cursors.sql
-- Per-user, per-entity cursor table feeding SyncService.GetSyncStatus.
-- A cursor is bumped by the owning repository inside the same transaction
-- as the Upsert/SoftDelete that produced a new updated_at.
CREATE TABLE user_sync_cursors (
    user_id     uuid        NOT NULL,
    entity_type TEXT        NOT NULL,
    cursor_at   timestamptz NOT NULL,
    PRIMARY KEY (user_id, entity_type)
);

CREATE INDEX idx_user_sync_cursors_user ON user_sync_cursors(user_id);
```

- [ ] **Step 2: Apply the migration**

Run: `make migrate` (from repo root; this iterates `backend/migrations/*.sql` against the Docker `pocket-pilot-db` container).

Expected output: `Applying backend/migrations/002_sync_cursors.sql` with no error.

- [ ] **Step 3: Verify the table exists**

Run:
```bash
docker exec pocket-pilot-db psql -U ${POSTGRES_USER:-pocket} -d ${POSTGRES_DB:-pocket_pilot} -c "\d user_sync_cursors"
```

Expected: table with columns `user_id uuid`, `entity_type text`, `cursor_at timestamptz`, PK on `(user_id, entity_type)`.

- [ ] **Step 4: Commit**

```bash
git add backend/migrations/002_sync_cursors.sql
git commit -m "feat(backend): add user_sync_cursors table for sync preflight"
```

---

## Task 2: `sync` package — entity types

**Files:**
- Create: `backend/internal/sync/entity_type.go`

- [ ] **Step 1: Write the file**

```go
package sync

// EntityType is the canonical identifier shared by backend cursor storage
// and the frontend sync handler's entityType string. Keep the values in
// sync with the frontend SyncHandler.entityType getters.
type EntityType string

const (
	EntityAccount             EntityType = "account"
	EntityTransaction         EntityType = "transaction"
	EntityCategory            EntityType = "category"
	EntityGoal                EntityType = "goal"
	EntityTag                 EntityType = "tag"
	EntityBudget              EntityType = "budget"
	EntityTransactionTemplate EntityType = "transaction_template"
	EntityUserPreference      EntityType = "user_preference"
	EntityYieldConfig         EntityType = "yield_config"
)

// AllEntityTypes returns every entity type a client may ask about.
// GetSyncStatus uses this to fill missing cursors with the epoch.
// Adding a new sync-participating entity REQUIRES appending it here.
func AllEntityTypes() []EntityType {
	return []EntityType{
		EntityAccount,
		EntityTransaction,
		EntityCategory,
		EntityGoal,
		EntityTag,
		EntityBudget,
		EntityTransactionTemplate,
		EntityUserPreference,
		EntityYieldConfig,
	}
}
```

- [ ] **Step 2: Verify it builds**

Run: `cd backend && go build ./internal/sync/...`
Expected: no output (success).

- [ ] **Step 3: Commit**

```bash
git add backend/internal/sync/entity_type.go
git commit -m "feat(backend): add sync entity type constants"
```

---

## Task 3: `sync` package — `CursorStore`

**Files:**
- Create: `backend/internal/sync/cursor.go`

- [ ] **Step 1: Write the file**

```go
package sync

import (
	"context"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"
)

// DBTX is the minimal interface satisfied by both *pgxpool.Pool and pgx.Tx.
// Repositories pass their active tx to CursorStore.Bump so the cursor
// update is atomic with the triggering write.
type DBTX interface {
	Exec(ctx context.Context, sql string, args ...any) (pgconn.CommandTag, error)
}

// CursorStore reads and writes rows in user_sync_cursors.
type CursorStore struct {
	pool *pgxpool.Pool
}

func NewCursorStore(pool *pgxpool.Pool) *CursorStore {
	return &CursorStore{pool: pool}
}

// Bump upserts the cursor using LWW semantics: it only advances
// cursor_at if updatedAt is strictly greater than the stored value.
// Callers MUST pass the tx of their triggering write so the bump is atomic.
func (c *CursorStore) Bump(
	ctx context.Context,
	tx DBTX,
	userID uuid.UUID,
	entityType EntityType,
	updatedAt time.Time,
) error {
	_, err := tx.Exec(ctx, `
		INSERT INTO user_sync_cursors (user_id, entity_type, cursor_at)
		VALUES ($1, $2, $3)
		ON CONFLICT (user_id, entity_type) DO UPDATE
		SET cursor_at = EXCLUDED.cursor_at
		WHERE user_sync_cursors.cursor_at < EXCLUDED.cursor_at
	`, userID, string(entityType), updatedAt)
	return err
}

// GetAll returns one cursor per known entity type. Entities with no
// recorded cursor are reported as the Unix epoch so the client always
// sees a complete map.
func (c *CursorStore) GetAll(
	ctx context.Context,
	userID uuid.UUID,
) (map[EntityType]time.Time, error) {
	rows, err := c.pool.Query(ctx, `
		SELECT entity_type, cursor_at
		FROM user_sync_cursors
		WHERE user_id = $1
	`, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	stored := make(map[EntityType]time.Time, len(AllEntityTypes()))
	for rows.Next() {
		var t string
		var at time.Time
		if err := rows.Scan(&t, &at); err != nil {
			return nil, err
		}
		stored[EntityType(t)] = at.UTC()
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}

	epoch := time.Unix(0, 0).UTC()
	out := make(map[EntityType]time.Time, len(AllEntityTypes()))
	for _, e := range AllEntityTypes() {
		if at, ok := stored[e]; ok {
			out[e] = at
		} else {
			out[e] = epoch
		}
	}
	return out, nil
}

// Silence unused-import warnings for pgx/pgconn when Bump doesn't yet
// need them — keep the explicit imports because cursor_integration_test.go
// uses them.
var _ pgx.Tx
var _ pgconn.CommandTag
```

- [ ] **Step 2: Verify it builds**

Run: `cd backend && go build ./internal/sync/...`
Expected: no output.

- [ ] **Step 3: Commit**

```bash
git add backend/internal/sync/cursor.go
git commit -m "feat(backend): add sync.CursorStore with Bump and GetAll"
```

---

## Task 4: Test helper for integration tests

**Files:**
- Create: `backend/internal/testdb/testdb.go`

The existing codebase has no integration test helper. Introduce a minimal one that opens a pool against `TEST_DATABASE_URL` or calls `t.Skip` when absent. Tests using it run with `TEST_DATABASE_URL=postgres://... go test ./...`.

- [ ] **Step 1: Write the file**

```go
// Package testdb provides a minimal helper for repository integration
// tests. Tests require the TEST_DATABASE_URL env var to point at a
// disposable PostgreSQL instance. If unset, tests are skipped.
package testdb

import (
	"context"
	"os"
	"testing"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
)

// OpenPool returns a pgxpool connected to TEST_DATABASE_URL, or skips
// the test if the env var is empty.
func OpenPool(t *testing.T) *pgxpool.Pool {
	t.Helper()
	url := os.Getenv("TEST_DATABASE_URL")
	if url == "" {
		t.Skip("TEST_DATABASE_URL not set; skipping integration test")
	}
	pool, err := pgxpool.New(context.Background(), url)
	if err != nil {
		t.Fatalf("pgxpool.New: %v", err)
	}
	t.Cleanup(pool.Close)
	return pool
}

// NewUser inserts a fresh users row and returns its id. Rows inserted
// via this helper are cleaned up automatically in t.Cleanup.
func NewUser(t *testing.T, pool *pgxpool.Pool) uuid.UUID {
	t.Helper()
	ctx := context.Background()
	id := uuid.New()
	_, err := pool.Exec(ctx, `
		INSERT INTO users (id, email, created_at, updated_at)
		VALUES ($1, $2, NOW(), NOW())
	`, id, id.String()+"@test.local")
	if err != nil {
		t.Fatalf("insert user: %v", err)
	}
	t.Cleanup(func() {
		_, _ = pool.Exec(ctx, `DELETE FROM users WHERE id = $1`, id)
	})
	return id
}
```

- [ ] **Step 2: Verify it builds**

Run: `cd backend && go build ./internal/testdb/...`
Expected: no output.

- [ ] **Step 3: Commit**

```bash
git add backend/internal/testdb/testdb.go
git commit -m "test(backend): add testdb helper for integration tests"
```

---

## Task 5: `CursorStore` integration test

**Files:**
- Create: `backend/internal/sync/cursor_test.go`

- [ ] **Step 1: Write the failing tests**

```go
package sync_test

import (
	"context"
	"testing"
	"time"

	"github.com/AlanIsaacV/pocket-pilot/internal/sync"
	"github.com/AlanIsaacV/pocket-pilot/internal/testdb"
)

func TestCursorStore_Bump_InsertsThenAdvancesWithLWW(t *testing.T) {
	ctx := context.Background()
	pool := testdb.OpenPool(t)
	user := testdb.NewUser(t, pool)
	store := sync.NewCursorStore(pool)

	t.Cleanup(func() {
		_, _ = pool.Exec(ctx, `DELETE FROM user_sync_cursors WHERE user_id = $1`, user)
	})

	older := time.Date(2026, 1, 1, 0, 0, 0, 0, time.UTC)
	newer := time.Date(2026, 2, 1, 0, 0, 0, 0, time.UTC)

	if err := store.Bump(ctx, pool, user, sync.EntityAccount, older); err != nil {
		t.Fatalf("Bump older: %v", err)
	}
	got, err := store.GetAll(ctx, user)
	if err != nil {
		t.Fatalf("GetAll: %v", err)
	}
	if !got[sync.EntityAccount].Equal(older) {
		t.Fatalf("after first bump: want %v got %v", older, got[sync.EntityAccount])
	}

	if err := store.Bump(ctx, pool, user, sync.EntityAccount, newer); err != nil {
		t.Fatalf("Bump newer: %v", err)
	}
	got, _ = store.GetAll(ctx, user)
	if !got[sync.EntityAccount].Equal(newer) {
		t.Fatalf("after advance: want %v got %v", newer, got[sync.EntityAccount])
	}

	// LWW guard: older timestamp must not regress the cursor.
	if err := store.Bump(ctx, pool, user, sync.EntityAccount, older); err != nil {
		t.Fatalf("Bump older-again: %v", err)
	}
	got, _ = store.GetAll(ctx, user)
	if !got[sync.EntityAccount].Equal(newer) {
		t.Fatalf("LWW regressed: want %v got %v", newer, got[sync.EntityAccount])
	}
}

func TestCursorStore_GetAll_FillsMissingWithEpoch(t *testing.T) {
	ctx := context.Background()
	pool := testdb.OpenPool(t)
	user := testdb.NewUser(t, pool)
	store := sync.NewCursorStore(pool)

	got, err := store.GetAll(ctx, user)
	if err != nil {
		t.Fatalf("GetAll: %v", err)
	}
	if len(got) != len(sync.AllEntityTypes()) {
		t.Fatalf("expected %d entries, got %d", len(sync.AllEntityTypes()), len(got))
	}
	epoch := time.Unix(0, 0).UTC()
	for _, e := range sync.AllEntityTypes() {
		if !got[e].Equal(epoch) {
			t.Fatalf("%s: want epoch, got %v", e, got[e])
		}
	}
}
```

- [ ] **Step 2: Run the tests — verify they pass (or skip if env absent)**

Run:
```bash
cd backend
TEST_DATABASE_URL="postgres://${POSTGRES_USER:-pocket}:${POSTGRES_PASSWORD:-pocket}@localhost:5432/${POSTGRES_DB:-pocket_pilot}?sslmode=disable" \
  go test ./internal/sync/... -run 'TestCursorStore_' -v
```

Expected: both tests `PASS`. If `TEST_DATABASE_URL` is unset, both print `SKIP`.

- [ ] **Step 3: Commit**

```bash
git add backend/internal/sync/cursor_test.go
git commit -m "test(backend): integration tests for sync.CursorStore LWW"
```

---

## Task 6: Proto contract `sync_service.proto`

**Files:**
- Create: `proto/pocket_pilot/v1/sync_service.proto`
- Modify: `scripts/gen_proto.sh`

- [ ] **Step 1: Write the proto**

```proto
syntax = "proto3";

package pocket_pilot.v1;

import "google/protobuf/timestamp.proto";

option go_package = "github.com/AlanIsaacV/pocket-pilot/backend/internal/gen/proto/pocket_pilot/v1;pocketpilotv1";

// SyncService exposes cross-cutting sync coordination RPCs.
service SyncService {
  // Returns the server's latest cursor per entity type for the authenticated
  // user. The client compares each cursor with its local last_synced_at and
  // skips the per-entity delta pull when server_cursor <= local_last_synced_at.
  rpc GetSyncStatus(GetSyncStatusRequest) returns (GetSyncStatusResponse);
}

message GetSyncStatusRequest {}

message GetSyncStatusResponse {
  // Map keyed by entity_type (matches the frontend SyncHandler.entityType
  // string: "account", "transaction", "category", "goal", "tag", "budget",
  // "transaction_template", "user_preference", "yield_config").
  // Every known entity appears. Entities with no stored cursor report
  // 1970-01-01T00:00:00Z so the client can safely compare without null checks.
  map<string, google.protobuf.Timestamp> cursors = 1;

  // Server wall-clock at the moment of the query. Informational only.
  google.protobuf.Timestamp synced_at = 2;
}
```

- [ ] **Step 2: Add the proto file to `scripts/gen_proto.sh`**

Modify `scripts/gen_proto.sh` at both the Go and Dart `protoc` invocations: append `pocket_pilot/v1/sync_service.proto` to the file list of each invocation. For example, the Go block becomes:

```bash
protoc \
    --proto_path="${PROTO_DIR}" \
    --go_out="${GO_OUT}" \
    --go_opt=paths=source_relative \
    --go-grpc_out="${GO_OUT}" \
    --go-grpc_opt=paths=source_relative \
    pocket_pilot/v1/common.proto \
    pocket_pilot/v1/account_service.proto \
    pocket_pilot/v1/category_service.proto \
    pocket_pilot/v1/transaction_template_service.proto \
    pocket_pilot/v1/yield_config_service.proto \
    pocket_pilot/v1/transaction_service.proto \
    pocket_pilot/v1/tags_service.proto \
    pocket_pilot/v1/goal_service.proto \
    pocket_pilot/v1/user_preferences_service.proto \
    pocket_pilot/v1/budget_service.proto \
    pocket_pilot/v1/ai_assistant_service.proto \
    pocket_pilot/v1/auth_service.proto \
    pocket_pilot/v1/sync_service.proto
```

Apply the identical append (`pocket_pilot/v1/sync_service.proto` on the last line) to the Dart `protoc` invocation.

- [ ] **Step 3: Regenerate Go and Dart stubs**

Run:
```bash
./scripts/gen_proto.sh
```

Expected: new files created at:
- `backend/internal/gen/proto/pocket_pilot/v1/pocket_pilot/v1/sync_service.pb.go`
- `backend/internal/gen/proto/pocket_pilot/v1/pocket_pilot/v1/sync_service_grpc.pb.go`
- `frontend/lib/src/generated/pocket_pilot/v1/sync_service.pb.dart`
- `frontend/lib/src/generated/pocket_pilot/v1/sync_service.pbgrpc.dart`

- [ ] **Step 4: Verify backend still builds**

Run: `cd backend && go build ./...`
Expected: no output.

- [ ] **Step 5: Commit**

```bash
git add proto/pocket_pilot/v1/sync_service.proto scripts/gen_proto.sh \
        backend/internal/gen/proto/pocket_pilot/v1/pocket_pilot/v1/sync_service*.pb.go \
        frontend/lib/src/generated/pocket_pilot/v1/sync_service*
git commit -m "feat(proto): add SyncService.GetSyncStatus RPC"
```

---

## Task 7: Backend `sync.Handler` (GetSyncStatus)

**Files:**
- Create: `backend/internal/sync/handler.go`

- [ ] **Step 1: Write the handler**

```go
package sync

import (
	"context"
	"time"

	"google.golang.org/protobuf/types/known/timestamppb"

	pb "github.com/AlanIsaacV/pocket-pilot/internal/gen/proto/pocket_pilot/v1/pocket_pilot/v1"
	"github.com/AlanIsaacV/pocket-pilot/internal/middleware"
)

// Handler implements pb.SyncServiceServer.
type Handler struct {
	pb.UnimplementedSyncServiceServer
	store *CursorStore
}

func NewHandler(store *CursorStore) *Handler {
	return &Handler{store: store}
}

func (h *Handler) GetSyncStatus(
	ctx context.Context,
	_ *pb.GetSyncStatusRequest,
) (*pb.GetSyncStatusResponse, error) {
	userID, err := middleware.UserIDFromCtx(ctx)
	if err != nil {
		return nil, err
	}

	cursors, err := h.store.GetAll(ctx, userID)
	if err != nil {
		return nil, err
	}

	out := make(map[string]*timestamppb.Timestamp, len(cursors))
	for entity, at := range cursors {
		out[string(entity)] = timestamppb.New(at)
	}
	return &pb.GetSyncStatusResponse{
		Cursors:  out,
		SyncedAt: timestamppb.New(time.Now().UTC()),
	}, nil
}
```

- [ ] **Step 2: Verify it builds**

Run: `cd backend && go build ./internal/sync/...`
Expected: no output.

- [ ] **Step 3: Commit**

```bash
git add backend/internal/sync/handler.go
git commit -m "feat(backend): add sync.Handler for GetSyncStatus"
```

---

## Task 8: Integrate `CursorStore` in `account` repository

**Files:**
- Modify: `backend/internal/account/repository.go`
- Create: `backend/internal/account/cursor_integration_test.go`

This task establishes the canonical pattern reused by Tasks 9–16.

- [ ] **Step 1: Add `cursor` field + constructor argument**

Replace the struct + constructor block (`backend/internal/account/repository.go:30-36`) with:

```go
type Repository struct {
	pool   *pgxpool.Pool
	cursor *sync.CursorStore
}

func NewRepository(pool *pgxpool.Pool, cursor *sync.CursorStore) *Repository {
	return &Repository{pool: pool, cursor: cursor}
}
```

Add to the import block at the top of the file:

```go
import (
	// ... existing imports ...
	"github.com/AlanIsaacV/pocket-pilot/internal/sync"
)
```

- [ ] **Step 2: Rewrite `Upsert` to be transactional and bump the cursor**

Replace `Upsert` (currently at `backend/internal/account/repository.go:132-174`) with:

```go
// Upsert inserts a new account or updates an existing one applying Last Write Wins.
// The cursor is bumped only when the client's write is accepted; rejected LWW
// attempts do not move the cursor.
func (r *Repository) Upsert(ctx context.Context, a *Account) (*Account, bool, error) {
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return nil, false, err
	}
	defer tx.Rollback(ctx)

	row := tx.QueryRow(ctx, `
		INSERT INTO accounts (id, user_id, name, type, currency_code, credit_limit_cents, statement_day, payment_due_day, interest_rate_apr, term_months, created_at, updated_at, deleted_at)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13)
		ON CONFLICT (id) DO UPDATE SET
			name              = EXCLUDED.name,
			type              = EXCLUDED.type,
			currency_code     = EXCLUDED.currency_code,
			credit_limit_cents = EXCLUDED.credit_limit_cents,
			statement_day     = EXCLUDED.statement_day,
			payment_due_day   = EXCLUDED.payment_due_day,
			interest_rate_apr = EXCLUDED.interest_rate_apr,
			term_months       = EXCLUDED.term_months,
			updated_at        = EXCLUDED.updated_at,
			deleted_at        = EXCLUDED.deleted_at
		WHERE accounts.updated_at < EXCLUDED.updated_at
		RETURNING id, user_id, name, type, currency_code, credit_limit_cents,
			statement_day, payment_due_day, interest_rate_apr,
			term_months, created_at, updated_at, deleted_at`,
		a.ID, a.UserID, a.Name, a.Type,
		a.CurrencyCode,
		a.CreditLimitCents, a.StatementDay, a.PaymentDueDay,
		a.InterestRateApr, a.TermMonths,
		a.CreatedAt, a.UpdatedAt, a.DeletedAt,
	)

	result, err := r.scan(row)
	if err == nil {
		if err := r.cursor.Bump(ctx, tx, a.UserID, sync.EntityAccount, result.UpdatedAt); err != nil {
			return nil, false, err
		}
		if err := tx.Commit(ctx); err != nil {
			return nil, false, err
		}
		return result, false, nil
	}
	if err != pgx.ErrNoRows {
		return nil, false, err
	}

	// LWW rejected the client's version — return the server's without bumping.
	current, err := r.GetByID(ctx, a.ID, a.UserID)
	if err != nil {
		return nil, false, err
	}
	return current, true, nil
}
```

- [ ] **Step 3: Rewrite `SoftDelete` to be transactional and bump the cursor**

Replace `SoftDelete` (currently at `backend/internal/account/repository.go:179-186`) with:

```go
// SoftDelete sets deleted_at on an account, applying LWW by comparing timestamps.
// The cursor is bumped only when the UPDATE actually modified a row.
func (r *Repository) SoftDelete(ctx context.Context, id, userID uuid.UUID, deletedAt time.Time) error {
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)

	tag, err := tx.Exec(ctx, `
		UPDATE accounts SET deleted_at = $3, updated_at = $3
		WHERE id = $1 AND user_id = $2
		  AND (deleted_at IS NULL OR updated_at < $3)
	`, id, userID, deletedAt)
	if err != nil {
		return err
	}
	if tag.RowsAffected() > 0 {
		if err := r.cursor.Bump(ctx, tx, userID, sync.EntityAccount, deletedAt); err != nil {
			return err
		}
	}
	return tx.Commit(ctx)
}
```

- [ ] **Step 4: Verify backend builds (caller will break; that is expected)**

Run: `cd backend && go build ./internal/account/...`
Expected: package `account` builds. `cmd/server/main.go` will break because `account.NewRepository` now takes two args — fixed in Task 17.

- [ ] **Step 5: Write the failing integration test**

Create `backend/internal/account/cursor_integration_test.go`:

```go
package account_test

import (
	"context"
	"testing"
	"time"

	"github.com/google/uuid"

	"github.com/AlanIsaacV/pocket-pilot/internal/account"
	"github.com/AlanIsaacV/pocket-pilot/internal/sync"
	"github.com/AlanIsaacV/pocket-pilot/internal/testdb"
)

func TestAccountRepo_Upsert_BumpsCursor(t *testing.T) {
	ctx := context.Background()
	pool := testdb.OpenPool(t)
	user := testdb.NewUser(t, pool)
	cursor := sync.NewCursorStore(pool)
	repo := account.NewRepository(pool, cursor)

	t.Cleanup(func() {
		_, _ = pool.Exec(ctx, `DELETE FROM user_sync_cursors WHERE user_id = $1`, user)
		_, _ = pool.Exec(ctx, `DELETE FROM accounts WHERE user_id = $1`, user)
	})

	now := time.Now().UTC().Truncate(time.Microsecond)
	acc := &account.Account{
		ID:           uuid.New(),
		UserID:       user,
		Name:         "Test",
		Type:         "bank",
		CurrencyCode: "MXN",
		CreatedAt:    now,
		UpdatedAt:    now,
	}
	if _, _, err := repo.Upsert(ctx, acc); err != nil {
		t.Fatalf("Upsert: %v", err)
	}

	got, err := cursor.GetAll(ctx, user)
	if err != nil {
		t.Fatalf("GetAll: %v", err)
	}
	if !got[sync.EntityAccount].Equal(now) {
		t.Fatalf("cursor: want %v got %v", now, got[sync.EntityAccount])
	}
}

func TestAccountRepo_SoftDelete_BumpsCursor(t *testing.T) {
	ctx := context.Background()
	pool := testdb.OpenPool(t)
	user := testdb.NewUser(t, pool)
	cursor := sync.NewCursorStore(pool)
	repo := account.NewRepository(pool, cursor)

	t.Cleanup(func() {
		_, _ = pool.Exec(ctx, `DELETE FROM user_sync_cursors WHERE user_id = $1`, user)
		_, _ = pool.Exec(ctx, `DELETE FROM accounts WHERE user_id = $1`, user)
	})

	created := time.Now().UTC().Add(-time.Hour).Truncate(time.Microsecond)
	acc := &account.Account{
		ID: uuid.New(), UserID: user, Name: "A", Type: "bank",
		CurrencyCode: "MXN", CreatedAt: created, UpdatedAt: created,
	}
	if _, _, err := repo.Upsert(ctx, acc); err != nil {
		t.Fatalf("Upsert: %v", err)
	}

	deletedAt := time.Now().UTC().Truncate(time.Microsecond)
	if err := repo.SoftDelete(ctx, acc.ID, user, deletedAt); err != nil {
		t.Fatalf("SoftDelete: %v", err)
	}
	got, _ := cursor.GetAll(ctx, user)
	if !got[sync.EntityAccount].Equal(deletedAt) {
		t.Fatalf("cursor: want %v got %v", deletedAt, got[sync.EntityAccount])
	}
}

func TestAccountRepo_Upsert_LWWRejection_DoesNotBump(t *testing.T) {
	ctx := context.Background()
	pool := testdb.OpenPool(t)
	user := testdb.NewUser(t, pool)
	cursor := sync.NewCursorStore(pool)
	repo := account.NewRepository(pool, cursor)

	t.Cleanup(func() {
		_, _ = pool.Exec(ctx, `DELETE FROM user_sync_cursors WHERE user_id = $1`, user)
		_, _ = pool.Exec(ctx, `DELETE FROM accounts WHERE user_id = $1`, user)
	})

	newer := time.Now().UTC().Truncate(time.Microsecond)
	older := newer.Add(-time.Hour)

	id := uuid.New()
	// Insert newer version first.
	_, _, err := repo.Upsert(ctx, &account.Account{
		ID: id, UserID: user, Name: "new", Type: "bank",
		CurrencyCode: "MXN", CreatedAt: newer, UpdatedAt: newer,
	})
	if err != nil {
		t.Fatalf("Upsert newer: %v", err)
	}

	// Older client version must be rejected and must NOT regress the cursor.
	_, resolved, err := repo.Upsert(ctx, &account.Account{
		ID: id, UserID: user, Name: "old", Type: "bank",
		CurrencyCode: "MXN", CreatedAt: older, UpdatedAt: older,
	})
	if err != nil {
		t.Fatalf("Upsert older: %v", err)
	}
	if !resolved {
		t.Fatalf("expected conflict_resolved=true")
	}
	got, _ := cursor.GetAll(ctx, user)
	if !got[sync.EntityAccount].Equal(newer) {
		t.Fatalf("cursor regressed: want %v got %v", newer, got[sync.EntityAccount])
	}
}
```

- [ ] **Step 6: Run the tests**

Run:
```bash
cd backend
TEST_DATABASE_URL="postgres://${POSTGRES_USER:-pocket}:${POSTGRES_PASSWORD:-pocket}@localhost:5432/${POSTGRES_DB:-pocket_pilot}?sslmode=disable" \
  go test ./internal/account/... -run 'TestAccountRepo_' -v
```

Expected: all three tests PASS.

- [ ] **Step 7: Commit**

```bash
git add backend/internal/account/repository.go backend/internal/account/cursor_integration_test.go
git commit -m "feat(backend/account): bump sync cursor on Upsert and SoftDelete"
```

---

## Task 9: Integrate `CursorStore` in `category` repository

**Files:**
- Modify: `backend/internal/category/repository.go`
- Create: `backend/internal/category/cursor_integration_test.go`

- [ ] **Step 1: Update struct, constructor, and imports**

Add `"github.com/AlanIsaacV/pocket-pilot/internal/sync"` to the imports. Replace the struct + constructor with:

```go
type Repository struct {
	pool   *pgxpool.Pool
	cursor *sync.CursorStore
}

func NewRepository(pool *pgxpool.Pool, cursor *sync.CursorStore) *Repository {
	return &Repository{pool: pool, cursor: cursor}
}
```

- [ ] **Step 2: Rewrite `Upsert` (`category/repository.go:117`) following Task 8 Step 2 pattern**

Replace `r.pool.QueryRow(ctx, ...)` with a `tx := r.pool.Begin(ctx)` + `tx.QueryRow(ctx, ...)` + `r.cursor.Bump(ctx, tx, c.UserID, sync.EntityCategory, result.UpdatedAt)` + `tx.Commit(ctx)` on the happy path. Same LWW rejection handling as account Upsert — no cursor bump when the server's version wins.

- [ ] **Step 3: Rewrite `SoftDelete` (`category/repository.go:152`) following Task 8 Step 3 pattern**

Wrap in a tx, capture `tag.RowsAffected()`, bump `sync.EntityCategory` only when `tag.RowsAffected() > 0`, commit.

- [ ] **Step 4: Write the integration test**

Create `backend/internal/category/cursor_integration_test.go` mirroring `account/cursor_integration_test.go` but substituting `category.NewRepository`, `sync.EntityCategory`, and a minimal `category.Category{}` with the fields required for insert. Include all three test cases (Upsert bump, SoftDelete bump, LWW-rejection no-bump).

Required minimal category fields: inspect `backend/internal/category/repository.go` for the Upsert signature and columns — populate at least `ID`, `UserID`, `Name`, `Type`, `Color`, `Icon`, `CreatedAt`, `UpdatedAt`.

- [ ] **Step 5: Build and run**

Run:
```bash
cd backend && go build ./internal/category/...
TEST_DATABASE_URL="postgres://${POSTGRES_USER:-pocket}:${POSTGRES_PASSWORD:-pocket}@localhost:5432/${POSTGRES_DB:-pocket_pilot}?sslmode=disable" \
  go test ./internal/category/... -run 'TestCategoryRepo_' -v
```

Expected: three tests PASS.

- [ ] **Step 6: Commit**

```bash
git add backend/internal/category/repository.go backend/internal/category/cursor_integration_test.go
git commit -m "feat(backend/category): bump sync cursor on Upsert and SoftDelete"
```

---

## Task 10: Integrate `CursorStore` in `tag` repository

**Files:**
- Modify: `backend/internal/tag/repository.go`
- Create: `backend/internal/tag/cursor_integration_test.go`

Apply Task 9's pattern. Use `sync.EntityTag`. Minimal tag fields for insert: inspect `tag/repository.go:96` (`Upsert`) for required columns (typically `ID`, `UserID`, `Name`, `Color`, `CreatedAt`, `UpdatedAt`).

- [ ] **Step 1: Add `sync` import + update struct + constructor**

Same two-line struct and constructor pattern as Task 8 Step 1, substituting `sync.EntityTag` ownership in call sites.

- [ ] **Step 2: Transactionalize `Upsert` (line 96) and bump on success**

Identical mechanical transformation as Task 8 Step 2, using `sync.EntityTag` and tag's column list.

- [ ] **Step 3: Transactionalize `SoftDelete` (line 125) and bump when `RowsAffected > 0`**

Identical mechanical transformation as Task 8 Step 3.

- [ ] **Step 4: Write integration tests**

Mirror `account/cursor_integration_test.go` with `tag.NewRepository`, `sync.EntityTag`, and tag-shaped fixture rows. Include Upsert bump, SoftDelete bump, LWW-rejection no-bump.

- [ ] **Step 5: Build and run**

```bash
cd backend && go build ./internal/tag/...
TEST_DATABASE_URL="postgres://..." go test ./internal/tag/... -run 'TestTagRepo_' -v
```

- [ ] **Step 6: Commit**

```bash
git add backend/internal/tag/repository.go backend/internal/tag/cursor_integration_test.go
git commit -m "feat(backend/tag): bump sync cursor on Upsert and SoftDelete"
```

---

## Task 11: Integrate `CursorStore` in `transaction` repository

**Files:**
- Modify: `backend/internal/transaction/repository.go`
- Create: `backend/internal/transaction/cursor_integration_test.go`

Note: `SoftDelete` already uses a tx (cascades transfer legs). For this repo the SoftDelete change is only adding `cursor.Bump` before `tx.Commit`.

- [ ] **Step 1: Add `sync` import + update struct + constructor**

Same two-line struct + constructor as Task 8.

- [ ] **Step 2: Transactionalize `Upsert` (line 142) and bump `sync.EntityTransaction` on success**

Same pattern as Task 8 Step 2.

- [ ] **Step 3: Modify `SoftDelete` (line 191) — only add the bump**

Inside the existing `tx, err := r.pool.Begin(ctx)` block, after the primary and cascade UPDATEs but before `tx.Commit(ctx)`, add:

```go
// Bump the cursor if at least one row was affected. Since we already
// soft-deleted the primary row above, if linkedID was non-nil we also
// affected the linked leg — either way the cursor should advance to deletedAt.
if err := r.cursor.Bump(ctx, tx, userID, sync.EntityTransaction, deletedAt); err != nil {
    return err
}
```

Note: if the primary row was a no-op (LWW rejected via the `AND (deleted_at IS NULL OR updated_at < $3)` guard), `tx.QueryRow(...).Scan(&linkedID)` returns `pgx.ErrNoRows`. The current code already tolerates this. In that case the bump is harmless: the existing cursor LWW guard (`WHERE cursor_at < EXCLUDED.cursor_at`) will prevent regression if `deletedAt` is actually older. If `deletedAt` is newer, bumping to it is correct.

- [ ] **Step 4: Write the integration test**

Mirror the account test. Fields: `ID`, `UserID`, `AccountID` (insert a prerequisite account first using the account repo), `Type` = "expense", `AmountCents`, `CurrencyCode`, `Status`, `Date`, `CreatedAt`, `UpdatedAt`. `CategoryID` and other optionals can be null. Include Upsert bump, SoftDelete bump, LWW-rejection no-bump.

For the prerequisite account insert, the test should build an `account.NewRepository(pool, cursor)` and call `Upsert` on it. Reset the cursor back to zero between account insert and transaction insert so only the transaction-caused bump is asserted:

```go
// Scrub cursors created by the prerequisite account upsert so the
// assertion below only sees the transaction bump.
_, _ = pool.Exec(ctx, `DELETE FROM user_sync_cursors WHERE user_id = $1`, user)
```

- [ ] **Step 5: Build and run**

- [ ] **Step 6: Commit**

```bash
git add backend/internal/transaction/repository.go backend/internal/transaction/cursor_integration_test.go
git commit -m "feat(backend/transaction): bump sync cursor on Upsert and SoftDelete"
```

---

## Task 12: Integrate `CursorStore` in `transactiontemplate` repository

**Files:**
- Modify: `backend/internal/transactiontemplate/repository.go`
- Create: `backend/internal/transactiontemplate/cursor_integration_test.go`

Same pattern as Task 8. Use `sync.EntityTransactionTemplate`. Upsert at line 89, SoftDelete at line 135.

- [ ] **Steps 1–6:** follow Task 8 verbatim, substituting the template's column list and `sync.EntityTransactionTemplate`.

```bash
git add backend/internal/transactiontemplate/repository.go backend/internal/transactiontemplate/cursor_integration_test.go
git commit -m "feat(backend/transactiontemplate): bump sync cursor on Upsert and SoftDelete"
```

---

## Task 13: Integrate `CursorStore` in `goal` repository

**Files:**
- Modify: `backend/internal/goal/repository.go`
- Create: `backend/internal/goal/cursor_integration_test.go`

Same pattern as Task 8. Use `sync.EntityGoal`. Upsert at line 99, SoftDelete at line 151.

```bash
git add backend/internal/goal/repository.go backend/internal/goal/cursor_integration_test.go
git commit -m "feat(backend/goal): bump sync cursor on Upsert and SoftDelete"
```

---

## Task 14: Integrate `CursorStore` in `budget` repository

**Files:**
- Modify: `backend/internal/budget/repository.go`
- Create: `backend/internal/budget/cursor_integration_test.go`

Same pattern as Task 8. Use `sync.EntityBudget`. Upsert at line 99, SoftDelete at line 151.

```bash
git add backend/internal/budget/repository.go backend/internal/budget/cursor_integration_test.go
git commit -m "feat(backend/budget): bump sync cursor on Upsert and SoftDelete"
```

---

## Task 15: Integrate `CursorStore` in `yieldconfig` repository

**Files:**
- Modify: `backend/internal/yieldconfig/repository.go`
- Create: `backend/internal/yieldconfig/cursor_integration_test.go`

Same pattern as Task 8. Use `sync.EntityYieldConfig`. Upsert at line 121, SoftDelete at line 188.

```bash
git add backend/internal/yieldconfig/repository.go backend/internal/yieldconfig/cursor_integration_test.go
git commit -m "feat(backend/yieldconfig): bump sync cursor on Upsert and SoftDelete"
```

---

## Task 16: Integrate `CursorStore` in `userpreference` repository

**Files:**
- Modify: `backend/internal/userpreference/repository.go`
- Create: `backend/internal/userpreference/cursor_integration_test.go`

Note the different `SoftDelete` signature: `SoftDelete(ctx, userID, prefKey string, deletedAt time.Time)`. The bump call is identical — pass `userID` and `sync.EntityUserPreference`.

- [ ] **Step 1: Add `sync` import + update struct + constructor**

Same as Task 8.

- [ ] **Step 2: Transactionalize `Upsert` (line 96) and bump on success**

Same shape as Task 8 Step 2. Bump with `result.UpdatedAt` and `sync.EntityUserPreference`. `result.UserID` comes from the returned row.

- [ ] **Step 3: Transactionalize `SoftDelete` (line 124) and bump when `RowsAffected > 0`**

```go
func (r *Repository) SoftDelete(ctx context.Context, userID uuid.UUID, prefKey string, deletedAt time.Time) error {
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)

	tag, err := tx.Exec(ctx, /* existing UPDATE SQL with prefKey+userID WHERE */, /* args */)
	if err != nil {
		return err
	}
	if tag.RowsAffected() > 0 {
		if err := r.cursor.Bump(ctx, tx, userID, sync.EntityUserPreference, deletedAt); err != nil {
			return err
		}
	}
	return tx.Commit(ctx)
}
```

- [ ] **Step 4: Write integration tests**

Mirror account tests. `UserPreference` required fields: inspect `userpreference/repository.go:96` for the exact column list. Typically `UserID`, `PrefKey`, `PrefValue`, `CreatedAt`, `UpdatedAt`.

- [ ] **Step 5: Build and run**

- [ ] **Step 6: Commit**

```bash
git add backend/internal/userpreference/repository.go backend/internal/userpreference/cursor_integration_test.go
git commit -m "feat(backend/userpreference): bump sync cursor on Upsert and SoftDelete"
```

---

## Task 17: Wire `CursorStore` and `SyncService` handler into `main.go`

**Files:**
- Modify: `backend/cmd/server/main.go`

- [ ] **Step 1: Add the `sync` import**

Add `"github.com/AlanIsaacV/pocket-pilot/internal/sync"` to the import block at `backend/cmd/server/main.go:3-31`.

- [ ] **Step 2: Build one `CursorStore` and pass it to every repo**

Replace the block at `backend/cmd/server/main.go:50-59` with:

```go
	// Shared sync cursor store used by every repository below.
	cursorStore := sync.NewCursorStore(pool)

	// Wire up repositories and handlers
	accountHandler := account.NewHandler(account.NewRepository(pool, cursorStore))
	categoryHandler := category.NewHandler(category.NewRepository(pool, cursorStore))
	transactionHandler := transaction.NewHandler(transaction.NewRepository(pool, cursorStore))
	transactionTemplateHandler := transactiontemplate.NewHandler(transactiontemplate.NewRepository(pool, cursorStore))
	yieldConfigHandler := yieldconfig.NewHandler(yieldconfig.NewRepository(pool, cursorStore))
	goalHandler := goal.NewHandler(goal.NewRepository(pool, cursorStore))
	budgetHandler := budget.NewHandler(budget.NewRepository(pool, cursorStore))
	tagHandler := tag.NewHandler(tag.NewRepository(pool, cursorStore))
	userPreferenceHandler := userpreference.NewHandler(userpreference.NewRepository(pool, cursorStore))

	// SyncService handler (preflight GetSyncStatus).
	syncHandler := sync.NewHandler(cursorStore)
```

- [ ] **Step 3: Register the new gRPC service**

After the existing `pb.RegisterAuthServiceServer(srv, authHandler)` line (around `main.go:91`), add:

```go
	pb.RegisterSyncServiceServer(srv, syncHandler)
```

- [ ] **Step 4: Build the whole backend**

Run: `cd backend && go build ./...`
Expected: no output.

- [ ] **Step 5: Smoke-test the server boot**

Run: `cd backend && go run ./cmd/server` (in one terminal). Expected log line: `"connected to PostgreSQL"` and `"gRPC server listening"`. Kill with Ctrl-C.

- [ ] **Step 6: Commit**

```bash
git add backend/cmd/server/main.go
git commit -m "feat(backend): wire CursorStore into all repos and register SyncService"
```

---

## Task 18: Frontend `SyncStatusRemoteService`

**Files:**
- Create: `frontend/lib/src/core/sync/sync_status_remote_service.dart`

- [ ] **Step 1: Write the service**

```dart
import 'package:grpc/grpc.dart';
import 'package:pocket_pilot/src/core/grpc/grpc_client.dart';
import 'package:pocket_pilot/src/generated/pocket_pilot/v1/sync_service.pbgrpc.dart';

/// Thin wrapper around the SyncService.GetSyncStatus RPC.
///
/// Returns the server's per-entity cursors (keys are the same strings
/// returned by SyncHandler.entityType). Missing entities are filled
/// server-side with 1970-01-01T00:00:00Z so callers never see null.
class SyncStatusRemoteService {
  late final SyncServiceClient _client;

  SyncStatusRemoteService() {
    _client = SyncServiceClient(
      GrpcClient.channel,
      interceptors: GrpcClient.interceptors,
    );
  }

  Future<Map<String, DateTime>> getSyncStatus() async {
    try {
      final response = await _client.getSyncStatus(GetSyncStatusRequest());
      return {
        for (final entry in response.cursors.entries)
          entry.key: entry.value.toDateTime().toUtc(),
      };
    } on GrpcError catch (e) {
      throw Exception('gRPC getSyncStatus error: ${e.message}');
    }
  }
}
```

- [ ] **Step 2: Verify the Dart analyzer is happy**

Run: `cd frontend && flutter analyze lib/src/core/sync/sync_status_remote_service.dart`
Expected: `No issues found!` (or no errors).

- [ ] **Step 3: Commit**

```bash
git add frontend/lib/src/core/sync/sync_status_remote_service.dart
git commit -m "feat(front-sync): add SyncStatusRemoteService wrapper"
```

---

## Task 19: `SyncService._pullPhase` preflight + skip + fallback

**Files:**
- Modify: `frontend/lib/src/core/sync/sync_service.dart`

- [ ] **Step 1: Add the import and the new constructor parameter**

Add:

```dart
import 'package:pocket_pilot/src/core/sync/sync_status_remote_service.dart';
```

In the `SyncService` class, add a field and constructor parameter:

```dart
  final SyncStatusRemoteService _statusService;

  /// Number of entities whose pull was skipped in the most recent cycle
  /// because the server's cursor was not newer than the local one.
  /// Exposed for the Sync Status screen.
  int lastCycleSkippedCount = 0;

  SyncService({
    required SyncOutbox outbox,
    required SyncMetadataStore metadataStore,
    required SyncStatusRemoteService statusService,
    required List<SyncHandler> handlers,
  })  : _outbox = outbox,
        _metadataStore = metadataStore,
        _statusService = statusService,
        _handlers = {for (final h in handlers) h.entityType: h};
```

- [ ] **Step 2: Restructure `_runSyncLoop` to do the preflight once per outer pass**

Replace the body of `_runSyncLoop` (currently lines 45-65) with:

```dart
  Future<void> _runSyncLoop() async {
    status.value = SyncStatus.syncing;
    bool hadError = false;
    try {
      await _outbox.resetAllRetries();
      final sorted = _handlers.values.toList()
        ..sort((a, b) => a.syncOrder.compareTo(b.syncOrder));
      while (_syncRequested) {
        _syncRequested = false;

        // Preflight: ask the server for per-entity cursors so we can skip
        // pulls where nothing changed. If the call fails (network, 5xx),
        // fall back to pulling every entity.
        Map<String, DateTime>? serverCursors;
        try {
          serverCursors = await _statusService.getSyncStatus();
        } catch (_) {
          serverCursors = null;
        }

        int skipped = 0;
        for (final handler in sorted) {
          final localCursor =
              await _metadataStore.getLastSyncedAt(handler.entityType);
          final serverCursor = serverCursors?[handler.entityType];

          final shouldSkip = serverCursors != null &&
              localCursor != null &&
              serverCursor != null &&
              !serverCursor.isAfter(localCursor);

          if (shouldSkip) {
            skipped++;
          } else {
            await _pullEntity(handler);
          }
          await _pushEntity(handler);
        }
        lastCycleSkippedCount = skipped;
      }
    } catch (_) {
      hadError = true;
    } finally {
      status.value = hadError ? SyncStatus.error : SyncStatus.idle;
      _activeSyncFuture = null;
    }
  }
```

- [ ] **Step 3: Verify the analyzer is happy**

Run: `cd frontend && flutter analyze lib/src/core/sync/sync_service.dart`
Expected: `No issues found!`

- [ ] **Step 4: Commit**

```bash
git add frontend/lib/src/core/sync/sync_service.dart
git commit -m "feat(front-sync): preflight GetSyncStatus to skip unchanged entities"
```

---

## Task 20: Wire `SyncStatusRemoteService` in `main.dart`

**Files:**
- Modify: `frontend/lib/main.dart`

- [ ] **Step 1: Add the import**

Add at the top of `frontend/lib/main.dart`:

```dart
import 'package:pocket_pilot/src/core/sync/sync_status_remote_service.dart';
```

- [ ] **Step 2: Construct and inject the service**

Before the `SyncService(...)` constructor call at `frontend/lib/main.dart:183-197`, add:

```dart
  final syncStatusRemoteService = SyncStatusRemoteService();
```

Replace the `SyncService` constructor call with:

```dart
  final syncService = SyncService(
    outbox: syncOutbox,
    metadataStore: syncMetadataStore,
    statusService: syncStatusRemoteService,
    handlers: [
      accountSyncHandler,
      categorySyncHandler,
      tagSyncHandler,
      transactionTemplateSyncHandler,
      yieldConfigSyncHandler,
      transactionSyncHandler,
      userPreferenceSyncHandler,
      goalSyncHandler,
      budgetSyncHandler,
    ],
  );
```

- [ ] **Step 3: Verify the analyzer is happy**

Run: `cd frontend && flutter analyze lib/main.dart`
Expected: `No issues found!`

- [ ] **Step 4: Smoke test (cold sync)**

Run: `cd frontend && flutter run -d <your-device>` against a backend built from Task 17. Log in, trigger a manual sync from Settings → Sincronización. Watch the backend logs: first sync should issue a `/SyncService/GetSyncStatus` call followed by the nine per-entity `List*` calls (first sync: no local cursors). Trigger a second sync immediately. Backend logs should show `/SyncService/GetSyncStatus` followed by **zero** `List*` calls.

- [ ] **Step 5: Commit**

```bash
git add frontend/lib/main.dart
git commit -m "feat(front-sync): inject SyncStatusRemoteService into SyncService"
```

---

## Task 21: Surface `lastCycleSkippedCount` on the Sync Status screen

**Files:**
- Modify: `frontend/lib/src/ui/screens/settings/sync_status_screen.dart`

- [ ] **Step 1: Read the current `_buildDetailsCard` section**

Run: `grep -n "_buildDetailsCard\|Cambios pendientes" frontend/lib/src/ui/screens/settings/sync_status_screen.dart`

Identify the row rendering the pending-count detail (around lines 135-145 per exploration notes).

- [ ] **Step 2: Add a skipped-entities row**

Immediately after the pending-count detail row inside `_buildDetailsCard`, append a new row reading `syncService.lastCycleSkippedCount`. Match the existing row widget style (label on the left, value on the right). Example shape (adapt to match the file's actual widget idiom):

```dart
_DetailRow(
  label: 'Entidades saltadas (último ciclo)',
  value: '${widget.syncService.lastCycleSkippedCount}/9',
),
```

If there is no `_DetailRow` helper, duplicate whatever container+Text pair renders the pending-count line and substitute the label + value.

- [ ] **Step 3: Verify the analyzer is happy**

Run: `cd frontend && flutter analyze lib/src/ui/screens/settings/sync_status_screen.dart`
Expected: `No issues found!`

- [ ] **Step 4: Manual verification**

Launch the app, run one sync cycle (cold + warm). Open Settings → Sincronización. Expected: a row reading "Entidades saltadas (último ciclo): N/9" where N=0 after first sync and N=9 after an immediately-repeated sync.

- [ ] **Step 5: Commit**

```bash
git add frontend/lib/src/ui/screens/settings/sync_status_screen.dart
git commit -m "feat(front-sync): show last-cycle skipped-entity count on sync screen"
```

---

## Self-Review

**1. Spec coverage**

| Spec section | Task(s) |
|---|---|
| §1 PostgreSQL schema | Task 1 |
| §2 Sync package (CursorStore, entity constants) | Tasks 2, 3 |
| §3 Proto contract | Task 6 |
| §4 Handler | Task 7 |
| §5 Repository integration (9 repos) | Tasks 8–16 |
| §6 Tests | Tasks 5, 8-16 (each includes integration test), plus testdb helper in Task 4 |
| §7 Frontend data layer (`SyncStatusRemoteService`) | Task 18 |
| §8 Frontend `SyncService` integration | Tasks 19, 20 |
| §9 Observability (`lastCycleSkippedCount` on Sync Status) | Task 21 |
| `main.go` wiring | Task 17 |
| No backfill | Task 1 (migration contains no backfill INSERT) |
| Fallback when preflight fails | Task 19 (try/catch → `serverCursors = null` → all pulls run) |
| LWW guard: rejected writes do not bump cursor | Task 8 Step 5 test case `TestAccountRepo_Upsert_LWWRejection_DoesNotBump` |

**2. Placeholder scan** — clear. The per-repo tasks (9–16) reuse Task 8's canonical pattern via explicit file+line references and repeat the mechanical transformation description so the engineer can read each task standalone.

**3. Type consistency** — `CursorStore` constructor signature (`NewCursorStore(pool)`) appears consistently across Tasks 3, 5, 8–16, 17. `CursorStore.Bump(ctx, tx, userID, entityType, updatedAt)` signature appears consistently across all call sites. Frontend `SyncStatusRemoteService.getSyncStatus()` returns `Future<Map<String, DateTime>>` consistently across Tasks 18, 19. Repository constructor signature change `NewRepository(pool)` → `NewRepository(pool, cursor)` is applied consistently in Tasks 8–16 and consumed in Task 17.

---

## Execution Handoff

**Plan complete and saved to `docs/superpowers/plans/2026-04-16-sync-preflight-cursors.md`. Two execution options:**

**1. Subagent-Driven (recommended)** - I dispatch a fresh subagent per task, review between tasks, fast iteration

**2. Inline Execution** - Execute tasks in this session using executing-plans, batch execution with checkpoints

**Which approach?**
