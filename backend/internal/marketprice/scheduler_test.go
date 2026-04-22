package marketprice_test

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/AlanIsaacV/pocket-pilot/internal/investment"
	"github.com/AlanIsaacV/pocket-pilot/internal/marketprice"
	"github.com/AlanIsaacV/pocket-pilot/internal/sync"
	"github.com/AlanIsaacV/pocket-pilot/internal/testdb"
)

// fakeProvider implements marketprice.MarketPriceProvider for tests. It
// captures the call args so tests can assert the scheduler forwarded the
// full symbol list.
type fakeProvider struct {
	calls  [][]investment.SymbolExchange
	quotes []marketprice.Quote
	errs   []marketprice.SymbolError
	err    error
}

func (f *fakeProvider) Fetch(_ context.Context, s []investment.SymbolExchange) ([]marketprice.Quote, []marketprice.SymbolError, error) {
	f.calls = append(f.calls, append([]investment.SymbolExchange(nil), s...))
	return f.quotes, f.errs, f.err
}

func (f *fakeProvider) Name() string { return "fake" }

func TestScheduler_Tick_NoHoldings(t *testing.T) {
	pool := testdb.OpenPool(t)
	ctx := context.Background()

	cursor := sync.NewCursorStore(pool)
	priceRepo := investment.NewMarketPriceRepository(pool, cursor)
	holdingRepo := investment.NewHoldingRepository(pool, cursor)

	prov := &fakeProvider{}
	s := marketprice.NewScheduler(prov, priceRepo, holdingRepo, false)

	// Ensure there are no active holdings polluting this assertion: create
	// a user with nothing.
	testdb.NewUser(t, pool)

	updated, failed, _, err := s.Tick(ctx)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if updated != 0 || failed != 0 {
		t.Fatalf("expected zero counts when no provider call happens, got updated=%d failed=%d", updated, failed)
	}
}

func TestScheduler_Refresh_WritesAndCounts(t *testing.T) {
	pool := testdb.OpenPool(t)
	ctx := context.Background()

	cursor := sync.NewCursorStore(pool)
	priceRepo := investment.NewMarketPriceRepository(pool, cursor)
	holdingRepo := investment.NewHoldingRepository(pool, cursor)

	user := testdb.NewUser(t, pool)
	aaplID := insertActiveHolding(t, ctx, pool, user, "AAPL", "NASDAQ", "USD")
	msftID := insertActiveHolding(t, ctx, pool, user, "MSFT", "NASDAQ", "USD")
	t.Cleanup(func() {
		_, _ = pool.Exec(ctx, `DELETE FROM market_prices WHERE symbol IN ('AAPL', 'MSFT')`)
		_, _ = pool.Exec(ctx, `DELETE FROM investment_holdings WHERE id = ANY($1)`, []uuid.UUID{aaplID, msftID})
	})

	prov := &fakeProvider{
		quotes: []marketprice.Quote{
			{
				Symbol:       "AAPL",
				Exchange:     "NASDAQ",
				CurrencyCode: "USD",
				Price:        100.50,
				PriceDate:    time.Date(2026, 4, 20, 0, 0, 0, 0, time.UTC),
				FetchedAt:    time.Date(2026, 4, 20, 22, 0, 0, 0, time.UTC),
				Source:       "fake",
			},
			{
				Symbol:       "MSFT",
				Exchange:     "NASDAQ",
				CurrencyCode: "USD",
				Price:        200.75,
				PriceDate:    time.Date(2026, 4, 20, 0, 0, 0, 0, time.UTC),
				FetchedAt:    time.Date(2026, 4, 20, 22, 0, 0, 0, time.UTC),
				Source:       "fake",
			},
		},
	}

	s := marketprice.NewScheduler(prov, priceRepo, holdingRepo, false)
	updated, failed, _, err := s.Tick(ctx)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if updated != 2 || failed != 0 {
		t.Fatalf("expected 2 updated / 0 failed, got updated=%d failed=%d", updated, failed)
	}

	var count int
	if err := pool.QueryRow(ctx, `SELECT count(*) FROM market_prices WHERE symbol IN ('AAPL','MSFT')`).Scan(&count); err != nil {
		t.Fatalf("count: %v", err)
	}
	if count != 2 {
		t.Fatalf("expected 2 market_price rows, got %d", count)
	}

	if len(prov.calls) != 1 {
		t.Fatalf("expected one provider call, got %d", len(prov.calls))
	}
	forwarded := map[string]bool{}
	for _, p := range prov.calls[0] {
		forwarded[p.Symbol] = true
	}
	for _, want := range []string{"AAPL", "MSFT"} {
		if !forwarded[want] {
			t.Errorf("expected %s to be forwarded, got %#v", want, prov.calls[0])
		}
	}
}

func TestScheduler_Refresh_ProviderError(t *testing.T) {
	pool := testdb.OpenPool(t)
	ctx := context.Background()

	cursor := sync.NewCursorStore(pool)
	priceRepo := investment.NewMarketPriceRepository(pool, cursor)
	holdingRepo := investment.NewHoldingRepository(pool, cursor)

	prov := &fakeProvider{err: errors.New("yahoo down")}
	s := marketprice.NewScheduler(prov, priceRepo, holdingRepo, false)

	_, _, _, err := s.Refresh(ctx, []investment.SymbolExchange{{Symbol: "AAPL", Exchange: "NASDAQ"}})
	if err == nil {
		t.Fatalf("expected error to bubble up")
	}
}

func insertActiveHolding(t *testing.T, ctx context.Context, pool *pgxpool.Pool, userID uuid.UUID, symbol, exchange, ccy string) uuid.UUID {
	t.Helper()
	id := uuid.New()
	now := time.Now().UTC()
	_, err := pool.Exec(ctx,
		`INSERT INTO investment_holdings (
            id, user_id, symbol, exchange, display_name, currency_code, asset_type, status,
            manual_price, notes, created_at, updated_at
        ) VALUES ($1, $2, $3, $4, $5, $6, 'stock', 'active', NULL, NULL, $7, $7)`,
		id, userID, symbol, exchange, symbol, ccy, now,
	)
	if err != nil {
		t.Fatalf("insert holding: %v", err)
	}
	return id
}
