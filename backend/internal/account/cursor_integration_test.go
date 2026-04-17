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
	_, _, err := repo.Upsert(ctx, &account.Account{
		ID: id, UserID: user, Name: "new", Type: "bank",
		CurrencyCode: "MXN", CreatedAt: newer, UpdatedAt: newer,
	})
	if err != nil {
		t.Fatalf("Upsert newer: %v", err)
	}

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
