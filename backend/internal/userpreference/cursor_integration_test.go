package userpreference_test

import (
	"context"
	"testing"
	"time"

	"github.com/AlanIsaacV/pocket-pilot/internal/sync"
	"github.com/AlanIsaacV/pocket-pilot/internal/testdb"
	"github.com/AlanIsaacV/pocket-pilot/internal/userpreference"
)

func TestUserPreferenceRepo_Upsert_BumpsCursor(t *testing.T) {
	ctx := context.Background()
	pool := testdb.OpenPool(t)
	user := testdb.NewUser(t, pool)
	cursor := sync.NewCursorStore(pool)
	repo := userpreference.NewRepository(pool, cursor)

	t.Cleanup(func() {
		_, _ = pool.Exec(ctx, `DELETE FROM user_sync_cursors WHERE user_id = $1`, user)
		_, _ = pool.Exec(ctx, `DELETE FROM user_preferences WHERE user_id = $1`, user)
	})

	now := time.Now().UTC().Truncate(time.Microsecond)
	if _, _, err := repo.Upsert(ctx, &userpreference.UserPreference{
		UserID: user, PrefKey: "theme.mode", PrefValue: "dark",
		CreatedAt: now, UpdatedAt: now,
	}); err != nil {
		t.Fatalf("Upsert: %v", err)
	}
	got, _ := cursor.GetAll(ctx, user)
	if !got[sync.EntityUserPreference].Equal(now) {
		t.Fatalf("cursor: want %v got %v", now, got[sync.EntityUserPreference])
	}
}

func TestUserPreferenceRepo_SoftDelete_BumpsCursor(t *testing.T) {
	ctx := context.Background()
	pool := testdb.OpenPool(t)
	user := testdb.NewUser(t, pool)
	cursor := sync.NewCursorStore(pool)
	repo := userpreference.NewRepository(pool, cursor)

	t.Cleanup(func() {
		_, _ = pool.Exec(ctx, `DELETE FROM user_sync_cursors WHERE user_id = $1`, user)
		_, _ = pool.Exec(ctx, `DELETE FROM user_preferences WHERE user_id = $1`, user)
	})

	created := time.Now().UTC().Add(-time.Hour).Truncate(time.Microsecond)
	if _, _, err := repo.Upsert(ctx, &userpreference.UserPreference{
		UserID: user, PrefKey: "theme.mode", PrefValue: "dark",
		CreatedAt: created, UpdatedAt: created,
	}); err != nil {
		t.Fatalf("Upsert: %v", err)
	}

	deletedAt := time.Now().UTC().Truncate(time.Microsecond)
	if err := repo.SoftDelete(ctx, user, "theme.mode", deletedAt); err != nil {
		t.Fatalf("SoftDelete: %v", err)
	}
	got, _ := cursor.GetAll(ctx, user)
	if !got[sync.EntityUserPreference].Equal(deletedAt) {
		t.Fatalf("cursor: want %v got %v", deletedAt, got[sync.EntityUserPreference])
	}
}

func TestUserPreferenceRepo_Upsert_LWWRejection_DoesNotBump(t *testing.T) {
	ctx := context.Background()
	pool := testdb.OpenPool(t)
	user := testdb.NewUser(t, pool)
	cursor := sync.NewCursorStore(pool)
	repo := userpreference.NewRepository(pool, cursor)

	t.Cleanup(func() {
		_, _ = pool.Exec(ctx, `DELETE FROM user_sync_cursors WHERE user_id = $1`, user)
		_, _ = pool.Exec(ctx, `DELETE FROM user_preferences WHERE user_id = $1`, user)
	})

	newer := time.Now().UTC().Truncate(time.Microsecond)
	older := newer.Add(-time.Hour)

	if _, _, err := repo.Upsert(ctx, &userpreference.UserPreference{
		UserID: user, PrefKey: "theme.mode", PrefValue: "dark",
		CreatedAt: newer, UpdatedAt: newer,
	}); err != nil {
		t.Fatalf("Upsert newer: %v", err)
	}

	_, resolved, err := repo.Upsert(ctx, &userpreference.UserPreference{
		UserID: user, PrefKey: "theme.mode", PrefValue: "light",
		CreatedAt: older, UpdatedAt: older,
	})
	if err != nil {
		t.Fatalf("Upsert older: %v", err)
	}
	if !resolved {
		t.Fatalf("expected conflict_resolved=true")
	}
	got, _ := cursor.GetAll(ctx, user)
	if !got[sync.EntityUserPreference].Equal(newer) {
		t.Fatalf("cursor regressed: want %v got %v", newer, got[sync.EntityUserPreference])
	}
}
