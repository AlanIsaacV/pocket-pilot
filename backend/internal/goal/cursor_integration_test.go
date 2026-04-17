package goal_test

import (
	"context"
	"testing"
	"time"

	"github.com/google/uuid"

	"github.com/AlanIsaacV/pocket-pilot/internal/goal"
	"github.com/AlanIsaacV/pocket-pilot/internal/sync"
	"github.com/AlanIsaacV/pocket-pilot/internal/testdb"
)

func newTestGoal(user uuid.UUID, t time.Time) *goal.Goal {
	return &goal.Goal{
		ID:                uuid.New(),
		UserID:            user,
		Name:              "Test",
		TargetAmountCents: 100000,
		TargetDate:        t.Add(90 * 24 * time.Hour),
		CurrencyCode:      "MXN",
		CreatedAt:         t,
		UpdatedAt:         t,
	}
}

func TestGoalRepo_Upsert_BumpsCursor(t *testing.T) {
	ctx := context.Background()
	pool := testdb.OpenPool(t)
	user := testdb.NewUser(t, pool)
	cursor := sync.NewCursorStore(pool)
	repo := goal.NewRepository(pool, cursor)

	t.Cleanup(func() {
		_, _ = pool.Exec(ctx, `DELETE FROM user_sync_cursors WHERE user_id = $1`, user)
		_, _ = pool.Exec(ctx, `DELETE FROM goals WHERE user_id = $1`, user)
	})

	now := time.Now().UTC().Truncate(time.Microsecond)
	if _, _, err := repo.Upsert(ctx, newTestGoal(user, now)); err != nil {
		t.Fatalf("Upsert: %v", err)
	}
	got, _ := cursor.GetAll(ctx, user)
	if !got[sync.EntityGoal].Equal(now) {
		t.Fatalf("cursor: want %v got %v", now, got[sync.EntityGoal])
	}
}

func TestGoalRepo_SoftDelete_BumpsCursor(t *testing.T) {
	ctx := context.Background()
	pool := testdb.OpenPool(t)
	user := testdb.NewUser(t, pool)
	cursor := sync.NewCursorStore(pool)
	repo := goal.NewRepository(pool, cursor)

	t.Cleanup(func() {
		_, _ = pool.Exec(ctx, `DELETE FROM user_sync_cursors WHERE user_id = $1`, user)
		_, _ = pool.Exec(ctx, `DELETE FROM goals WHERE user_id = $1`, user)
	})

	created := time.Now().UTC().Add(-time.Hour).Truncate(time.Microsecond)
	g := newTestGoal(user, created)
	if _, _, err := repo.Upsert(ctx, g); err != nil {
		t.Fatalf("Upsert: %v", err)
	}
	deletedAt := time.Now().UTC().Truncate(time.Microsecond)
	if err := repo.SoftDelete(ctx, g.ID, user, deletedAt); err != nil {
		t.Fatalf("SoftDelete: %v", err)
	}
	got, _ := cursor.GetAll(ctx, user)
	if !got[sync.EntityGoal].Equal(deletedAt) {
		t.Fatalf("cursor: want %v got %v", deletedAt, got[sync.EntityGoal])
	}
}

func TestGoalRepo_Upsert_LWWRejection_DoesNotBump(t *testing.T) {
	ctx := context.Background()
	pool := testdb.OpenPool(t)
	user := testdb.NewUser(t, pool)
	cursor := sync.NewCursorStore(pool)
	repo := goal.NewRepository(pool, cursor)

	t.Cleanup(func() {
		_, _ = pool.Exec(ctx, `DELETE FROM user_sync_cursors WHERE user_id = $1`, user)
		_, _ = pool.Exec(ctx, `DELETE FROM goals WHERE user_id = $1`, user)
	})

	newer := time.Now().UTC().Truncate(time.Microsecond)
	older := newer.Add(-time.Hour)
	id := uuid.New()

	if _, _, err := repo.Upsert(ctx, &goal.Goal{
		ID: id, UserID: user, Name: "new",
		TargetAmountCents: 100000, TargetDate: newer.Add(24 * time.Hour),
		CurrencyCode: "MXN", CreatedAt: newer, UpdatedAt: newer,
	}); err != nil {
		t.Fatalf("Upsert newer: %v", err)
	}

	_, resolved, err := repo.Upsert(ctx, &goal.Goal{
		ID: id, UserID: user, Name: "old",
		TargetAmountCents: 50000, TargetDate: older.Add(24 * time.Hour),
		CurrencyCode: "MXN", CreatedAt: older, UpdatedAt: older,
	})
	if err != nil {
		t.Fatalf("Upsert older: %v", err)
	}
	if !resolved {
		t.Fatalf("expected conflict_resolved=true")
	}
	got, _ := cursor.GetAll(ctx, user)
	if !got[sync.EntityGoal].Equal(newer) {
		t.Fatalf("cursor regressed: want %v got %v", newer, got[sync.EntityGoal])
	}
}
