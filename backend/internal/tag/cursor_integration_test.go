package tag_test

import (
	"context"
	"testing"
	"time"

	"github.com/google/uuid"

	"github.com/AlanIsaacV/pocket-pilot/internal/sync"
	"github.com/AlanIsaacV/pocket-pilot/internal/tag"
	"github.com/AlanIsaacV/pocket-pilot/internal/testdb"
)

func TestTagRepo_Upsert_BumpsCursor(t *testing.T) {
	ctx := context.Background()
	pool := testdb.OpenPool(t)
	user := testdb.NewUser(t, pool)
	cursor := sync.NewCursorStore(pool)
	repo := tag.NewRepository(pool, cursor)

	t.Cleanup(func() {
		_, _ = pool.Exec(ctx, `DELETE FROM user_sync_cursors WHERE user_id = $1`, user)
		_, _ = pool.Exec(ctx, `DELETE FROM tags WHERE user_id = $1`, user)
	})

	now := time.Now().UTC().Truncate(time.Microsecond)
	if _, _, err := repo.Upsert(ctx, &tag.Tag{
		ID: uuid.New(), UserID: user, Name: "test",
		CreatedAt: now, UpdatedAt: now,
	}); err != nil {
		t.Fatalf("Upsert: %v", err)
	}
	got, _ := cursor.GetAll(ctx, user)
	if !got[sync.EntityTag].Equal(now) {
		t.Fatalf("cursor: want %v got %v", now, got[sync.EntityTag])
	}
}

func TestTagRepo_SoftDelete_BumpsCursor(t *testing.T) {
	ctx := context.Background()
	pool := testdb.OpenPool(t)
	user := testdb.NewUser(t, pool)
	cursor := sync.NewCursorStore(pool)
	repo := tag.NewRepository(pool, cursor)

	t.Cleanup(func() {
		_, _ = pool.Exec(ctx, `DELETE FROM user_sync_cursors WHERE user_id = $1`, user)
		_, _ = pool.Exec(ctx, `DELETE FROM tags WHERE user_id = $1`, user)
	})

	created := time.Now().UTC().Add(-time.Hour).Truncate(time.Microsecond)
	id := uuid.New()
	if _, _, err := repo.Upsert(ctx, &tag.Tag{
		ID: id, UserID: user, Name: "test",
		CreatedAt: created, UpdatedAt: created,
	}); err != nil {
		t.Fatalf("Upsert: %v", err)
	}

	deletedAt := time.Now().UTC().Truncate(time.Microsecond)
	if err := repo.SoftDelete(ctx, id, user, deletedAt); err != nil {
		t.Fatalf("SoftDelete: %v", err)
	}
	got, _ := cursor.GetAll(ctx, user)
	if !got[sync.EntityTag].Equal(deletedAt) {
		t.Fatalf("cursor: want %v got %v", deletedAt, got[sync.EntityTag])
	}
}

func TestTagRepo_Upsert_LWWRejection_DoesNotBump(t *testing.T) {
	ctx := context.Background()
	pool := testdb.OpenPool(t)
	user := testdb.NewUser(t, pool)
	cursor := sync.NewCursorStore(pool)
	repo := tag.NewRepository(pool, cursor)

	t.Cleanup(func() {
		_, _ = pool.Exec(ctx, `DELETE FROM user_sync_cursors WHERE user_id = $1`, user)
		_, _ = pool.Exec(ctx, `DELETE FROM tags WHERE user_id = $1`, user)
	})

	newer := time.Now().UTC().Truncate(time.Microsecond)
	older := newer.Add(-time.Hour)
	id := uuid.New()

	if _, _, err := repo.Upsert(ctx, &tag.Tag{
		ID: id, UserID: user, Name: "new",
		CreatedAt: newer, UpdatedAt: newer,
	}); err != nil {
		t.Fatalf("Upsert newer: %v", err)
	}

	_, resolved, err := repo.Upsert(ctx, &tag.Tag{
		ID: id, UserID: user, Name: "old",
		CreatedAt: older, UpdatedAt: older,
	})
	if err != nil {
		t.Fatalf("Upsert older: %v", err)
	}
	if !resolved {
		t.Fatalf("expected conflict_resolved=true")
	}
	got, _ := cursor.GetAll(ctx, user)
	if !got[sync.EntityTag].Equal(newer) {
		t.Fatalf("cursor regressed: want %v got %v", newer, got[sync.EntityTag])
	}
}
