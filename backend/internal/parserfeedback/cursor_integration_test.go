package parserfeedback_test

import (
	"context"
	"testing"
	"time"

	"github.com/google/uuid"

	"github.com/AlanIsaacV/pocket-pilot/internal/parserfeedback"
	"github.com/AlanIsaacV/pocket-pilot/internal/sync"
	"github.com/AlanIsaacV/pocket-pilot/internal/testdb"
)

func newTestFeedback(user uuid.UUID, id uuid.UUID, pendingID string, t time.Time) *parserfeedback.Feedback {
	bank := "bbva_mx"
	pattern := "purchase_tdc"
	method := "local"
	var version int32 = 2
	tru := true
	return &parserfeedback.Feedback{
		ID:                   id,
		UserID:               user,
		PendingTransactionID: pendingID,
		BankID:               &bank,
		PatternID:            &pattern,
		ParserVersion:        &version,
		ExtractionMethod:     &method,
		WasHelpful:           &tru,
		AccountChanged:       false,
		CategoryChanged:      true,
		AmountChanged:        false,
		DescriptionChanged:   false,
		WasDismissed:         false,
		CreatedAt:            t,
		UpdatedAt:            t,
	}
}

func TestParserFeedbackRepo_Upsert_BumpsCursor(t *testing.T) {
	ctx := context.Background()
	pool := testdb.OpenPool(t)
	user := testdb.NewUser(t, pool)
	cursor := sync.NewCursorStore(pool)
	repo := parserfeedback.NewRepository(pool, cursor)

	t.Cleanup(func() {
		_, _ = pool.Exec(ctx, `DELETE FROM user_sync_cursors WHERE user_id = $1`, user)
		_, _ = pool.Exec(ctx, `DELETE FROM parser_feedback WHERE user_id = $1`, user)
	})

	now := time.Now().UTC().Truncate(time.Microsecond)
	if _, _, err := repo.Upsert(ctx, newTestFeedback(user, uuid.New(), "pending-1", now)); err != nil {
		t.Fatalf("Upsert: %v", err)
	}
	got, _ := cursor.GetAll(ctx, user)
	if !got[sync.EntityParserFeedback].Equal(now) {
		t.Fatalf("cursor: want %v got %v", now, got[sync.EntityParserFeedback])
	}
}

func TestParserFeedbackRepo_Upsert_LWWRejection_DoesNotBump(t *testing.T) {
	ctx := context.Background()
	pool := testdb.OpenPool(t)
	user := testdb.NewUser(t, pool)
	cursor := sync.NewCursorStore(pool)
	repo := parserfeedback.NewRepository(pool, cursor)

	t.Cleanup(func() {
		_, _ = pool.Exec(ctx, `DELETE FROM user_sync_cursors WHERE user_id = $1`, user)
		_, _ = pool.Exec(ctx, `DELETE FROM parser_feedback WHERE user_id = $1`, user)
	})

	newer := time.Now().UTC().Truncate(time.Microsecond)
	older := newer.Add(-time.Hour)

	id := uuid.New()
	if _, _, err := repo.Upsert(ctx, newTestFeedback(user, id, "pending-lww", newer)); err != nil {
		t.Fatalf("Upsert newer: %v", err)
	}

	_, resolved, err := repo.Upsert(ctx, newTestFeedback(user, id, "pending-lww", older))
	if err != nil {
		t.Fatalf("Upsert older: %v", err)
	}
	if !resolved {
		t.Fatalf("expected conflict_resolved=true")
	}
	got, _ := cursor.GetAll(ctx, user)
	if !got[sync.EntityParserFeedback].Equal(newer) {
		t.Fatalf("cursor regressed: want %v got %v", newer, got[sync.EntityParserFeedback])
	}
}

func TestParserFeedbackRepo_List_DeltaIncludesUpdatedSince(t *testing.T) {
	ctx := context.Background()
	pool := testdb.OpenPool(t)
	user := testdb.NewUser(t, pool)
	cursor := sync.NewCursorStore(pool)
	repo := parserfeedback.NewRepository(pool, cursor)

	t.Cleanup(func() {
		_, _ = pool.Exec(ctx, `DELETE FROM user_sync_cursors WHERE user_id = $1`, user)
		_, _ = pool.Exec(ctx, `DELETE FROM parser_feedback WHERE user_id = $1`, user)
	})

	t1 := time.Now().UTC().Add(-2 * time.Hour).Truncate(time.Microsecond)
	t2 := time.Now().UTC().Add(-1 * time.Hour).Truncate(time.Microsecond)
	t3 := time.Now().UTC().Truncate(time.Microsecond)

	if _, _, err := repo.Upsert(ctx, newTestFeedback(user, uuid.New(), "p-1", t1)); err != nil {
		t.Fatalf("Upsert 1: %v", err)
	}
	if _, _, err := repo.Upsert(ctx, newTestFeedback(user, uuid.New(), "p-2", t2)); err != nil {
		t.Fatalf("Upsert 2: %v", err)
	}
	if _, _, err := repo.Upsert(ctx, newTestFeedback(user, uuid.New(), "p-3", t3)); err != nil {
		t.Fatalf("Upsert 3: %v", err)
	}

	cutoff := t1.Add(time.Minute)
	items, _, err := repo.List(ctx, user, &cutoff, 100, 0)
	if err != nil {
		t.Fatalf("List delta: %v", err)
	}
	if len(items) != 2 {
		t.Fatalf("delta List should include only rows updated_at > cutoff: want 2 got %d", len(items))
	}
}
