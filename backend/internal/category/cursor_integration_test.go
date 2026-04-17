package category_test

import (
	"context"
	"testing"
	"time"

	"github.com/google/uuid"

	"github.com/AlanIsaacV/pocket-pilot/internal/category"
	"github.com/AlanIsaacV/pocket-pilot/internal/sync"
	"github.com/AlanIsaacV/pocket-pilot/internal/testdb"
)

func newTestCategory(user uuid.UUID, t time.Time) *category.Category {
	return &category.Category{
		ID:            uuid.New(),
		UserID:        user,
		Name:          "Test",
		Icon:          "label",
		Color:         "999999",
		Type:          "expense",
		DefaultNature: "",
		CreatedAt:     t,
		UpdatedAt:     t,
	}
}

func TestCategoryRepo_Upsert_BumpsCursor(t *testing.T) {
	ctx := context.Background()
	pool := testdb.OpenPool(t)
	user := testdb.NewUser(t, pool)
	cursor := sync.NewCursorStore(pool)
	repo := category.NewRepository(pool, cursor)

	t.Cleanup(func() {
		_, _ = pool.Exec(ctx, `DELETE FROM user_sync_cursors WHERE user_id = $1`, user)
		_, _ = pool.Exec(ctx, `DELETE FROM categories WHERE user_id = $1`, user)
	})

	now := time.Now().UTC().Truncate(time.Microsecond)
	if _, _, err := repo.Upsert(ctx, newTestCategory(user, now)); err != nil {
		t.Fatalf("Upsert: %v", err)
	}
	got, _ := cursor.GetAll(ctx, user)
	if !got[sync.EntityCategory].Equal(now) {
		t.Fatalf("cursor: want %v got %v", now, got[sync.EntityCategory])
	}
}

func TestCategoryRepo_SoftDelete_BumpsCursor(t *testing.T) {
	ctx := context.Background()
	pool := testdb.OpenPool(t)
	user := testdb.NewUser(t, pool)
	cursor := sync.NewCursorStore(pool)
	repo := category.NewRepository(pool, cursor)

	t.Cleanup(func() {
		_, _ = pool.Exec(ctx, `DELETE FROM user_sync_cursors WHERE user_id = $1`, user)
		_, _ = pool.Exec(ctx, `DELETE FROM categories WHERE user_id = $1`, user)
	})

	created := time.Now().UTC().Add(-time.Hour).Truncate(time.Microsecond)
	c := newTestCategory(user, created)
	if _, _, err := repo.Upsert(ctx, c); err != nil {
		t.Fatalf("Upsert: %v", err)
	}

	deletedAt := time.Now().UTC().Truncate(time.Microsecond)
	if err := repo.SoftDelete(ctx, c.ID, user, deletedAt); err != nil {
		t.Fatalf("SoftDelete: %v", err)
	}
	got, _ := cursor.GetAll(ctx, user)
	if !got[sync.EntityCategory].Equal(deletedAt) {
		t.Fatalf("cursor: want %v got %v", deletedAt, got[sync.EntityCategory])
	}
}

func TestCategoryRepo_Upsert_LWWRejection_DoesNotBump(t *testing.T) {
	ctx := context.Background()
	pool := testdb.OpenPool(t)
	user := testdb.NewUser(t, pool)
	cursor := sync.NewCursorStore(pool)
	repo := category.NewRepository(pool, cursor)

	t.Cleanup(func() {
		_, _ = pool.Exec(ctx, `DELETE FROM user_sync_cursors WHERE user_id = $1`, user)
		_, _ = pool.Exec(ctx, `DELETE FROM categories WHERE user_id = $1`, user)
	})

	newer := time.Now().UTC().Truncate(time.Microsecond)
	older := newer.Add(-time.Hour)

	id := uuid.New()
	if _, _, err := repo.Upsert(ctx, &category.Category{
		ID: id, UserID: user, Name: "new", Icon: "label", Color: "999999",
		Type: "expense", CreatedAt: newer, UpdatedAt: newer,
	}); err != nil {
		t.Fatalf("Upsert newer: %v", err)
	}

	_, resolved, err := repo.Upsert(ctx, &category.Category{
		ID: id, UserID: user, Name: "old", Icon: "label", Color: "999999",
		Type: "expense", CreatedAt: older, UpdatedAt: older,
	})
	if err != nil {
		t.Fatalf("Upsert older: %v", err)
	}
	if !resolved {
		t.Fatalf("expected conflict_resolved=true")
	}
	got, _ := cursor.GetAll(ctx, user)
	if !got[sync.EntityCategory].Equal(newer) {
		t.Fatalf("cursor regressed: want %v got %v", newer, got[sync.EntityCategory])
	}
}
