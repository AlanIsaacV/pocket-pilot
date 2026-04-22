package marketprice_test

import (
	"context"
	"testing"
	"time"

	pb "github.com/AlanIsaacV/pocket-pilot/internal/gen/proto/pocket_pilot/v1/pocket_pilot/v1"
	"github.com/AlanIsaacV/pocket-pilot/internal/investment"
	"github.com/AlanIsaacV/pocket-pilot/internal/marketprice"
	"github.com/AlanIsaacV/pocket-pilot/internal/sync"
	"github.com/AlanIsaacV/pocket-pilot/internal/testdb"
)

func TestAdminHandler_ExplicitSymbols(t *testing.T) {
	pool := testdb.OpenPool(t)
	ctx := context.Background()

	cursor := sync.NewCursorStore(pool)
	priceRepo := investment.NewMarketPriceRepository(pool, cursor)
	holdingRepo := investment.NewHoldingRepository(pool, cursor)

	// Seed a holding so the Upsert's cursor bump has someone to bump
	// against — otherwise the SELECT DISTINCT user_id returns zero rows
	// and the upsert still succeeds but silently.
	user := testdb.NewUser(t, pool)
	id := insertActiveHolding(t, ctx, pool, user, "AAPL", "NASDAQ", "USD")
	t.Cleanup(func() {
		_, _ = pool.Exec(ctx, `DELETE FROM market_prices WHERE symbol = 'AAPL'`)
		_, _ = pool.Exec(ctx, `DELETE FROM investment_holdings WHERE id = $1`, id)
	})

	prov := &fakeProvider{
		quotes: []marketprice.Quote{{
			Symbol: "AAPL", Exchange: "NASDAQ", CurrencyCode: "USD",
			Price: 180, PriceDate: time.Date(2026, 4, 20, 0, 0, 0, 0, time.UTC),
			FetchedAt: time.Now().UTC(), Source: "fake",
		}},
	}
	s := marketprice.NewScheduler(prov, priceRepo, holdingRepo, false)
	h := marketprice.NewAdminHandler(s, holdingRepo)

	resp, err := h.AdminRefreshMarketPrices(ctx, &pb.AdminRefreshMarketPricesRequest{
		Symbols: []*pb.SymbolExchange{{Symbol: "AAPL", Exchange: "NASDAQ"}},
	})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if resp.Updated != 1 {
		t.Fatalf("expected updated=1, got %d", resp.Updated)
	}
	if resp.Failed != 0 {
		t.Fatalf("expected failed=0, got %d", resp.Failed)
	}
	if len(prov.calls) != 1 || len(prov.calls[0]) != 1 {
		t.Fatalf("expected provider called once with 1 symbol, got %#v", prov.calls)
	}
}

func TestAdminHandler_EmptySymbolsRefreshesAll(t *testing.T) {
	pool := testdb.OpenPool(t)
	ctx := context.Background()

	cursor := sync.NewCursorStore(pool)
	priceRepo := investment.NewMarketPriceRepository(pool, cursor)
	holdingRepo := investment.NewHoldingRepository(pool, cursor)

	user := testdb.NewUser(t, pool)
	a := insertActiveHolding(t, ctx, pool, user, "AAPL", "NASDAQ", "USD")
	b := insertActiveHolding(t, ctx, pool, user, "MSFT", "NASDAQ", "USD")
	t.Cleanup(func() {
		_, _ = pool.Exec(ctx, `DELETE FROM market_prices WHERE symbol IN ('AAPL', 'MSFT')`)
		_, _ = pool.Exec(ctx, `DELETE FROM investment_holdings WHERE id IN ($1, $2)`, a, b)
	})

	prov := &fakeProvider{}
	s := marketprice.NewScheduler(prov, priceRepo, holdingRepo, false)
	h := marketprice.NewAdminHandler(s, holdingRepo)

	resp, err := h.AdminRefreshMarketPrices(ctx, &pb.AdminRefreshMarketPricesRequest{})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if resp.Updated != 0 {
		t.Fatalf("fake provider returned 0 quotes; expected 0 updated, got %d", resp.Updated)
	}
	if len(prov.calls) != 1 {
		t.Fatalf("expected one provider call, got %d", len(prov.calls))
	}
	// Both seeded symbols must appear among the forwarded pairs.
	got := map[string]bool{}
	for _, p := range prov.calls[0] {
		got[p.Symbol] = true
	}
	for _, want := range []string{"AAPL", "MSFT"} {
		if !got[want] {
			t.Errorf("expected provider to receive %s, got %#v", want, prov.calls[0])
		}
	}
}
