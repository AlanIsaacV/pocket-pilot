package transaction_test

import (
	"context"
	"testing"
	"time"

	"github.com/google/uuid"

	"github.com/AlanIsaacV/pocket-pilot/internal/account"
	"github.com/AlanIsaacV/pocket-pilot/internal/sync"
	"github.com/AlanIsaacV/pocket-pilot/internal/testdb"
	"github.com/AlanIsaacV/pocket-pilot/internal/transaction"
)

func TestTransactionRepo_Upsert_BumpsCursor(t *testing.T) {
	ctx := context.Background()
	pool := testdb.OpenPool(t)
	user := testdb.NewUser(t, pool)
	cursor := sync.NewCursorStore(pool)
	accRepo := account.NewRepository(pool, cursor)
	txRepo := transaction.NewRepository(pool, cursor)

	t.Cleanup(func() {
		_, _ = pool.Exec(ctx, `DELETE FROM transactions WHERE user_id = $1`, user)
		_, _ = pool.Exec(ctx, `DELETE FROM user_sync_cursors WHERE user_id = $1`, user)
		_, _ = pool.Exec(ctx, `DELETE FROM accounts WHERE user_id = $1`, user)
	})

	// Prerequisite account.
	createdAcc := time.Now().UTC().Add(-2 * time.Hour).Truncate(time.Microsecond)
	acc := &account.Account{
		ID: uuid.New(), UserID: user, Name: "A", Type: "bank",
		CurrencyCode: "MXN", CreatedAt: createdAcc, UpdatedAt: createdAcc,
	}
	if _, _, err := accRepo.Upsert(ctx, acc); err != nil {
		t.Fatalf("prereq Upsert account: %v", err)
	}
	// Scrub cursors so only the transaction bump is asserted below.
	if _, err := pool.Exec(ctx, `DELETE FROM user_sync_cursors WHERE user_id = $1`, user); err != nil {
		t.Fatalf("scrub cursors: %v", err)
	}

	now := time.Now().UTC().Truncate(time.Microsecond)
	txn := &transaction.Transaction{
		ID: uuid.New(), UserID: user, AccountID: acc.ID,
		Type: "expense", AmountCents: 1000, InstallmentsCount: 1,
		CurrencyCode: "MXN", Status: "posted",
		Date: now, CreatedAt: now, UpdatedAt: now,
	}
	if _, _, err := txRepo.Upsert(ctx, txn); err != nil {
		t.Fatalf("Upsert: %v", err)
	}
	got, _ := cursor.GetAll(ctx, user)
	if !got[sync.EntityTransaction].Equal(now) {
		t.Fatalf("cursor: want %v got %v", now, got[sync.EntityTransaction])
	}
}

func TestTransactionRepo_SoftDelete_BumpsCursor(t *testing.T) {
	ctx := context.Background()
	pool := testdb.OpenPool(t)
	user := testdb.NewUser(t, pool)
	cursor := sync.NewCursorStore(pool)
	accRepo := account.NewRepository(pool, cursor)
	txRepo := transaction.NewRepository(pool, cursor)

	t.Cleanup(func() {
		_, _ = pool.Exec(ctx, `DELETE FROM transactions WHERE user_id = $1`, user)
		_, _ = pool.Exec(ctx, `DELETE FROM user_sync_cursors WHERE user_id = $1`, user)
		_, _ = pool.Exec(ctx, `DELETE FROM accounts WHERE user_id = $1`, user)
	})

	createdAcc := time.Now().UTC().Add(-2 * time.Hour).Truncate(time.Microsecond)
	acc := &account.Account{
		ID: uuid.New(), UserID: user, Name: "A", Type: "bank",
		CurrencyCode: "MXN", CreatedAt: createdAcc, UpdatedAt: createdAcc,
	}
	if _, _, err := accRepo.Upsert(ctx, acc); err != nil {
		t.Fatalf("prereq Upsert account: %v", err)
	}

	created := time.Now().UTC().Add(-time.Hour).Truncate(time.Microsecond)
	txn := &transaction.Transaction{
		ID: uuid.New(), UserID: user, AccountID: acc.ID,
		Type: "expense", AmountCents: 1000, InstallmentsCount: 1,
		CurrencyCode: "MXN", Status: "posted",
		Date: created, CreatedAt: created, UpdatedAt: created,
	}
	if _, _, err := txRepo.Upsert(ctx, txn); err != nil {
		t.Fatalf("Upsert: %v", err)
	}

	deletedAt := time.Now().UTC().Truncate(time.Microsecond)
	if err := txRepo.SoftDelete(ctx, txn.ID, user, deletedAt); err != nil {
		t.Fatalf("SoftDelete: %v", err)
	}
	got, _ := cursor.GetAll(ctx, user)
	if !got[sync.EntityTransaction].Equal(deletedAt) {
		t.Fatalf("cursor: want %v got %v", deletedAt, got[sync.EntityTransaction])
	}
}

func TestTransactionRepo_Upsert_LWWRejection_DoesNotBump(t *testing.T) {
	ctx := context.Background()
	pool := testdb.OpenPool(t)
	user := testdb.NewUser(t, pool)
	cursor := sync.NewCursorStore(pool)
	accRepo := account.NewRepository(pool, cursor)
	txRepo := transaction.NewRepository(pool, cursor)

	t.Cleanup(func() {
		_, _ = pool.Exec(ctx, `DELETE FROM transactions WHERE user_id = $1`, user)
		_, _ = pool.Exec(ctx, `DELETE FROM user_sync_cursors WHERE user_id = $1`, user)
		_, _ = pool.Exec(ctx, `DELETE FROM accounts WHERE user_id = $1`, user)
	})

	createdAcc := time.Now().UTC().Add(-2 * time.Hour).Truncate(time.Microsecond)
	acc := &account.Account{
		ID: uuid.New(), UserID: user, Name: "A", Type: "bank",
		CurrencyCode: "MXN", CreatedAt: createdAcc, UpdatedAt: createdAcc,
	}
	if _, _, err := accRepo.Upsert(ctx, acc); err != nil {
		t.Fatalf("prereq: %v", err)
	}
	if _, err := pool.Exec(ctx, `DELETE FROM user_sync_cursors WHERE user_id = $1`, user); err != nil {
		t.Fatalf("scrub: %v", err)
	}

	newer := time.Now().UTC().Truncate(time.Microsecond)
	older := newer.Add(-time.Hour)
	id := uuid.New()

	if _, _, err := txRepo.Upsert(ctx, &transaction.Transaction{
		ID: id, UserID: user, AccountID: acc.ID,
		Type: "expense", AmountCents: 1000, InstallmentsCount: 1,
		CurrencyCode: "MXN", Status: "posted",
		Date: newer, CreatedAt: newer, UpdatedAt: newer,
	}); err != nil {
		t.Fatalf("Upsert newer: %v", err)
	}

	_, resolved, err := txRepo.Upsert(ctx, &transaction.Transaction{
		ID: id, UserID: user, AccountID: acc.ID,
		Type: "expense", AmountCents: 500, InstallmentsCount: 1,
		CurrencyCode: "MXN", Status: "posted",
		Date: older, CreatedAt: older, UpdatedAt: older,
	})
	if err != nil {
		t.Fatalf("Upsert older: %v", err)
	}
	if !resolved {
		t.Fatalf("expected conflict_resolved=true")
	}
	got, _ := cursor.GetAll(ctx, user)
	if !got[sync.EntityTransaction].Equal(newer) {
		t.Fatalf("cursor regressed: want %v got %v", newer, got[sync.EntityTransaction])
	}
}
