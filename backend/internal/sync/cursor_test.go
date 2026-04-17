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
