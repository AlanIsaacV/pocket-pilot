package investment_test

import (
	"context"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/AlanIsaacV/pocket-pilot/internal/investment"
	"github.com/AlanIsaacV/pocket-pilot/internal/sync"
	"github.com/AlanIsaacV/pocket-pilot/internal/testdb"
)

func TestSplitRepo_Upsert_BumpsCursor(t *testing.T) {
	ctx := context.Background()
	pool := testdb.OpenPool(t)
	user := testdb.NewUser(t, pool)
	cursor := sync.NewCursorStore(pool)
	repo := investment.NewSplitRepository(pool, cursor)

	holdingID := insertSplitTestHolding(t, ctx, pool, user)

	t.Cleanup(func() {
		_, _ = pool.Exec(ctx, `DELETE FROM investment_splits WHERE user_id = $1`, user)
		_, _ = pool.Exec(ctx, `DELETE FROM investment_holdings WHERE user_id = $1`, user)
		_, _ = pool.Exec(ctx, `DELETE FROM user_sync_cursors WHERE user_id = $1`, user)
	})

	if _, err := pool.Exec(ctx, `DELETE FROM user_sync_cursors WHERE user_id = $1`, user); err != nil {
		t.Fatalf("scrub cursors: %v", err)
	}

	now := time.Now().UTC().Truncate(time.Microsecond)
	occurred := time.Date(2026, 4, 25, 0, 0, 0, 0, time.UTC)
	s := &investment.Split{
		ID:         uuid.New(),
		UserID:     user,
		HoldingID:  holdingID,
		RatioNum:   2,
		RatioDen:   1,
		OccurredAt: occurred,
		CreatedAt:  now,
		UpdatedAt:  now,
	}
	if _, _, err := repo.Upsert(ctx, s); err != nil {
		t.Fatalf("Upsert: %v", err)
	}

	got, _ := cursor.GetAll(ctx, user)
	if !got[sync.EntityInvestmentSplit].Equal(now) {
		t.Fatalf("cursor: want %v got %v", now, got[sync.EntityInvestmentSplit])
	}
}

func TestSplitRepo_SoftDelete_BumpsCursor(t *testing.T) {
	ctx := context.Background()
	pool := testdb.OpenPool(t)
	user := testdb.NewUser(t, pool)
	cursor := sync.NewCursorStore(pool)
	repo := investment.NewSplitRepository(pool, cursor)

	holdingID := insertSplitTestHolding(t, ctx, pool, user)

	t.Cleanup(func() {
		_, _ = pool.Exec(ctx, `DELETE FROM investment_splits WHERE user_id = $1`, user)
		_, _ = pool.Exec(ctx, `DELETE FROM investment_holdings WHERE user_id = $1`, user)
		_, _ = pool.Exec(ctx, `DELETE FROM user_sync_cursors WHERE user_id = $1`, user)
	})

	created := time.Now().UTC().Add(-time.Hour).Truncate(time.Microsecond)
	occurred := time.Date(2026, 4, 25, 0, 0, 0, 0, time.UTC)
	s := &investment.Split{
		ID:         uuid.New(),
		UserID:     user,
		HoldingID:  holdingID,
		RatioNum:   2,
		RatioDen:   1,
		OccurredAt: occurred,
		CreatedAt:  created,
		UpdatedAt:  created,
	}
	if _, _, err := repo.Upsert(ctx, s); err != nil {
		t.Fatalf("Upsert: %v", err)
	}

	deletedAt := time.Now().UTC().Truncate(time.Microsecond)
	if err := repo.SoftDelete(ctx, s.ID, user, deletedAt); err != nil {
		t.Fatalf("SoftDelete: %v", err)
	}

	got, _ := cursor.GetAll(ctx, user)
	if !got[sync.EntityInvestmentSplit].Equal(deletedAt) {
		t.Fatalf("cursor: want %v got %v", deletedAt, got[sync.EntityInvestmentSplit])
	}
}

func TestSplitRepo_Upsert_LWWRejection_DoesNotBump(t *testing.T) {
	ctx := context.Background()
	pool := testdb.OpenPool(t)
	user := testdb.NewUser(t, pool)
	cursor := sync.NewCursorStore(pool)
	repo := investment.NewSplitRepository(pool, cursor)

	holdingID := insertSplitTestHolding(t, ctx, pool, user)

	t.Cleanup(func() {
		_, _ = pool.Exec(ctx, `DELETE FROM investment_splits WHERE user_id = $1`, user)
		_, _ = pool.Exec(ctx, `DELETE FROM investment_holdings WHERE user_id = $1`, user)
		_, _ = pool.Exec(ctx, `DELETE FROM user_sync_cursors WHERE user_id = $1`, user)
	})

	if _, err := pool.Exec(ctx, `DELETE FROM user_sync_cursors WHERE user_id = $1`, user); err != nil {
		t.Fatalf("scrub: %v", err)
	}

	newer := time.Now().UTC().Truncate(time.Microsecond)
	older := newer.Add(-time.Hour)
	occurred := time.Date(2026, 4, 25, 0, 0, 0, 0, time.UTC)
	id := uuid.New()

	if _, _, err := repo.Upsert(ctx, &investment.Split{
		ID: id, UserID: user, HoldingID: holdingID,
		RatioNum: 2, RatioDen: 1, OccurredAt: occurred,
		CreatedAt: newer, UpdatedAt: newer,
	}); err != nil {
		t.Fatalf("Upsert newer: %v", err)
	}

	_, resolved, err := repo.Upsert(ctx, &investment.Split{
		ID: id, UserID: user, HoldingID: holdingID,
		RatioNum: 3, RatioDen: 1, OccurredAt: occurred,
		CreatedAt: older, UpdatedAt: older,
	})
	if err != nil {
		t.Fatalf("Upsert older: %v", err)
	}
	if !resolved {
		t.Fatalf("expected conflict_resolved=true")
	}

	got, _ := cursor.GetAll(ctx, user)
	if !got[sync.EntityInvestmentSplit].Equal(newer) {
		t.Fatalf("cursor regressed: want %v got %v", newer, got[sync.EntityInvestmentSplit])
	}
}

func insertSplitTestHolding(t *testing.T, ctx context.Context, pool *pgxpool.Pool, userID uuid.UUID) uuid.UUID {
	t.Helper()
	id := uuid.New()
	now := time.Now().UTC()
	_, err := pool.Exec(ctx,
		`INSERT INTO investment_holdings (
            id, user_id, symbol, exchange, display_name, currency_code, asset_type, status,
            manual_price, notes, created_at, updated_at
        ) VALUES ($1, $2, 'AAPL', 'NASDAQ', 'Apple Inc.', 'USD', 'stock', 'active', NULL, NULL, $3, $3)`,
		id, userID, now,
	)
	if err != nil {
		t.Fatalf("insert holding: %v", err)
	}
	return id
}
