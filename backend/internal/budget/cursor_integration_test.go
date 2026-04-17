package budget_test

import (
	"context"
	"testing"
	"time"

	"github.com/google/uuid"

	"github.com/AlanIsaacV/pocket-pilot/internal/budget"
	"github.com/AlanIsaacV/pocket-pilot/internal/category"
	"github.com/AlanIsaacV/pocket-pilot/internal/sync"
	"github.com/AlanIsaacV/pocket-pilot/internal/testdb"
)

func setupBudgetPrereqs(t *testing.T) (context.Context, *sync.CursorStore, *budget.Repository, uuid.UUID, uuid.UUID) {
	t.Helper()
	ctx := context.Background()
	pool := testdb.OpenPool(t)
	user := testdb.NewUser(t, pool)
	cursor := sync.NewCursorStore(pool)
	catRepo := category.NewRepository(pool, cursor)
	budRepo := budget.NewRepository(pool, cursor)

	t.Cleanup(func() {
		_, _ = pool.Exec(ctx, `DELETE FROM budgets WHERE user_id = $1`, user)
		_, _ = pool.Exec(ctx, `DELETE FROM user_sync_cursors WHERE user_id = $1`, user)
		_, _ = pool.Exec(ctx, `DELETE FROM categories WHERE user_id = $1`, user)
	})

	createdCat := time.Now().UTC().Add(-2 * time.Hour).Truncate(time.Microsecond)
	cat := &category.Category{
		ID: uuid.New(), UserID: user, Name: "C",
		Icon: "label", Color: "999999", Type: "expense",
		CreatedAt: createdCat, UpdatedAt: createdCat,
	}
	if _, _, err := catRepo.Upsert(ctx, cat); err != nil {
		t.Fatalf("prereq category: %v", err)
	}
	if _, err := pool.Exec(ctx, `DELETE FROM user_sync_cursors WHERE user_id = $1`, user); err != nil {
		t.Fatalf("scrub: %v", err)
	}
	return ctx, cursor, budRepo, user, cat.ID
}

func TestBudgetRepo_Upsert_BumpsCursor(t *testing.T) {
	ctx, cursor, repo, user, catID := setupBudgetPrereqs(t)
	now := time.Now().UTC().Truncate(time.Microsecond)
	if _, _, err := repo.Upsert(ctx, &budget.Budget{
		ID: uuid.New(), UserID: user, CategoryID: catID,
		LimitAmountCents: 100000, CurrencyCode: "MXN", Period: "MONTHLY",
		CreatedAt: now, UpdatedAt: now,
	}); err != nil {
		t.Fatalf("Upsert: %v", err)
	}
	got, _ := cursor.GetAll(ctx, user)
	if !got[sync.EntityBudget].Equal(now) {
		t.Fatalf("cursor: want %v got %v", now, got[sync.EntityBudget])
	}
}

func TestBudgetRepo_SoftDelete_BumpsCursor(t *testing.T) {
	ctx, cursor, repo, user, catID := setupBudgetPrereqs(t)
	created := time.Now().UTC().Add(-time.Hour).Truncate(time.Microsecond)
	b := &budget.Budget{
		ID: uuid.New(), UserID: user, CategoryID: catID,
		LimitAmountCents: 100000, CurrencyCode: "MXN", Period: "MONTHLY",
		CreatedAt: created, UpdatedAt: created,
	}
	if _, _, err := repo.Upsert(ctx, b); err != nil {
		t.Fatalf("Upsert: %v", err)
	}
	deletedAt := time.Now().UTC().Truncate(time.Microsecond)
	if err := repo.SoftDelete(ctx, b.ID, user, deletedAt); err != nil {
		t.Fatalf("SoftDelete: %v", err)
	}
	got, _ := cursor.GetAll(ctx, user)
	if !got[sync.EntityBudget].Equal(deletedAt) {
		t.Fatalf("cursor: want %v got %v", deletedAt, got[sync.EntityBudget])
	}
}

func TestBudgetRepo_Upsert_LWWRejection_DoesNotBump(t *testing.T) {
	ctx, cursor, repo, user, catID := setupBudgetPrereqs(t)
	newer := time.Now().UTC().Truncate(time.Microsecond)
	older := newer.Add(-time.Hour)
	id := uuid.New()

	if _, _, err := repo.Upsert(ctx, &budget.Budget{
		ID: id, UserID: user, CategoryID: catID,
		LimitAmountCents: 100000, CurrencyCode: "MXN", Period: "MONTHLY",
		CreatedAt: newer, UpdatedAt: newer,
	}); err != nil {
		t.Fatalf("Upsert newer: %v", err)
	}

	_, resolved, err := repo.Upsert(ctx, &budget.Budget{
		ID: id, UserID: user, CategoryID: catID,
		LimitAmountCents: 50000, CurrencyCode: "MXN", Period: "MONTHLY",
		CreatedAt: older, UpdatedAt: older,
	})
	if err != nil {
		t.Fatalf("Upsert older: %v", err)
	}
	if !resolved {
		t.Fatalf("expected conflict_resolved=true")
	}
	got, _ := cursor.GetAll(ctx, user)
	if !got[sync.EntityBudget].Equal(newer) {
		t.Fatalf("cursor regressed: want %v got %v", newer, got[sync.EntityBudget])
	}
}
