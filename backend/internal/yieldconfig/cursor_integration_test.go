package yieldconfig_test

import (
	"context"
	"testing"
	"time"

	"github.com/google/uuid"

	"github.com/AlanIsaacV/pocket-pilot/internal/account"
	"github.com/AlanIsaacV/pocket-pilot/internal/sync"
	"github.com/AlanIsaacV/pocket-pilot/internal/testdb"
	"github.com/AlanIsaacV/pocket-pilot/internal/yieldconfig"
)

func setupYieldPrereqs(t *testing.T) (context.Context, *sync.CursorStore, *yieldconfig.Repository, uuid.UUID, uuid.UUID) {
	t.Helper()
	ctx := context.Background()
	pool := testdb.OpenPool(t)
	user := testdb.NewUser(t, pool)
	cursor := sync.NewCursorStore(pool)
	accRepo := account.NewRepository(pool, cursor)
	yRepo := yieldconfig.NewRepository(pool, cursor)

	t.Cleanup(func() {
		_, _ = pool.Exec(ctx, `DELETE FROM yield_configs WHERE user_id = $1`, user)
		_, _ = pool.Exec(ctx, `DELETE FROM user_sync_cursors WHERE user_id = $1`, user)
		_, _ = pool.Exec(ctx, `DELETE FROM accounts WHERE user_id = $1`, user)
	})

	createdAcc := time.Now().UTC().Add(-2 * time.Hour).Truncate(time.Microsecond)
	acc := &account.Account{
		ID: uuid.New(), UserID: user, Name: "A", Type: "investment",
		CurrencyCode: "MXN", CreatedAt: createdAcc, UpdatedAt: createdAcc,
	}
	if _, _, err := accRepo.Upsert(ctx, acc); err != nil {
		t.Fatalf("prereq account: %v", err)
	}
	if _, err := pool.Exec(ctx, `DELETE FROM user_sync_cursors WHERE user_id = $1`, user); err != nil {
		t.Fatalf("scrub: %v", err)
	}
	return ctx, cursor, yRepo, user, acc.ID
}

func newTestYieldConfig(user, accountID uuid.UUID, t time.Time) *yieldconfig.YieldConfig {
	return &yieldconfig.YieldConfig{
		ID:              uuid.New(),
		UserID:          user,
		AccountID:       accountID,
		Name:            "Test",
		AmountCents:     100000,
		ApyRate:         5.0,
		PayoutFrequency: "monthly",
		NextDate:        t.Add(30 * 24 * time.Hour),
		AutoRenew:       false,
		Status:          "active",
		CreatedAt:       t,
		UpdatedAt:       t,
	}
}

func TestYieldConfigRepo_Upsert_BumpsCursor(t *testing.T) {
	ctx, cursor, repo, user, accID := setupYieldPrereqs(t)
	now := time.Now().UTC().Truncate(time.Microsecond)
	if _, _, err := repo.Upsert(ctx, newTestYieldConfig(user, accID, now)); err != nil {
		t.Fatalf("Upsert: %v", err)
	}
	got, _ := cursor.GetAll(ctx, user)
	if !got[sync.EntityYieldConfig].Equal(now) {
		t.Fatalf("cursor: want %v got %v", now, got[sync.EntityYieldConfig])
	}
}

func TestYieldConfigRepo_SoftDelete_BumpsCursor(t *testing.T) {
	ctx, cursor, repo, user, accID := setupYieldPrereqs(t)
	created := time.Now().UTC().Add(-time.Hour).Truncate(time.Microsecond)
	cfg := newTestYieldConfig(user, accID, created)
	if _, _, err := repo.Upsert(ctx, cfg); err != nil {
		t.Fatalf("Upsert: %v", err)
	}
	deletedAt := time.Now().UTC().Truncate(time.Microsecond)
	if err := repo.SoftDelete(ctx, cfg.ID, user, deletedAt); err != nil {
		t.Fatalf("SoftDelete: %v", err)
	}
	got, _ := cursor.GetAll(ctx, user)
	if !got[sync.EntityYieldConfig].Equal(deletedAt) {
		t.Fatalf("cursor: want %v got %v", deletedAt, got[sync.EntityYieldConfig])
	}
}

func TestYieldConfigRepo_Upsert_LWWRejection_DoesNotBump(t *testing.T) {
	ctx, cursor, repo, user, accID := setupYieldPrereqs(t)
	newer := time.Now().UTC().Truncate(time.Microsecond)
	older := newer.Add(-time.Hour)
	id := uuid.New()

	if _, _, err := repo.Upsert(ctx, &yieldconfig.YieldConfig{
		ID: id, UserID: user, AccountID: accID, Name: "new",
		AmountCents: 100000, ApyRate: 5.0, PayoutFrequency: "monthly",
		NextDate: newer.Add(24 * time.Hour), Status: "active",
		CreatedAt: newer, UpdatedAt: newer,
	}); err != nil {
		t.Fatalf("Upsert newer: %v", err)
	}

	_, resolved, err := repo.Upsert(ctx, &yieldconfig.YieldConfig{
		ID: id, UserID: user, AccountID: accID, Name: "old",
		AmountCents: 50000, ApyRate: 3.0, PayoutFrequency: "monthly",
		NextDate: older.Add(24 * time.Hour), Status: "active",
		CreatedAt: older, UpdatedAt: older,
	})
	if err != nil {
		t.Fatalf("Upsert older: %v", err)
	}
	if !resolved {
		t.Fatalf("expected conflict_resolved=true")
	}
	got, _ := cursor.GetAll(ctx, user)
	if !got[sync.EntityYieldConfig].Equal(newer) {
		t.Fatalf("cursor regressed: want %v got %v", newer, got[sync.EntityYieldConfig])
	}
}
