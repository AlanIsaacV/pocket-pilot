// Package marketprice implements end-of-day price ingestion for the
// investments feature. The package owns three concerns: (1) the
// MarketPriceProvider interface that abstracts the upstream quote API,
// (2) a Scheduler that fires once a day and fans a fetch+upsert cycle out
// across active holdings, and (3) an admin gRPC handler for manual kicks.
// All writes go through investment.MarketPriceRepository.Upsert, which is
// already in place and handles cursor bookkeeping.
package marketprice

import (
	"context"
	"time"

	"github.com/AlanIsaacV/pocket-pilot/internal/investment"
)

// MarketPriceProvider abstracts the upstream quote API. Implementations are
// expected to be safe for concurrent use by a single Scheduler and to
// respect their own rate limits via retries and batching.
type MarketPriceProvider interface {
	// Fetch returns quotes for each symbol that resolved successfully and
	// SymbolError entries for the ones that did not (missing from the
	// feed, rejected, etc.). A non-nil error indicates an unrecoverable
	// transport failure for the whole call; partial success must be
	// reported via the two slices.
	Fetch(ctx context.Context, symbols []investment.SymbolExchange) ([]Quote, []SymbolError, error)

	// Name identifies the provider for logs and the "source" column of
	// market_prices. Lowercase, one word (e.g. "yahoo").
	Name() string
}

// Quote is the provider-agnostic shape the Scheduler writes into
// investment.MarketPrice. All prices are in the quote currency reported by
// the provider.
type Quote struct {
	Symbol       string
	Exchange     string
	CurrencyCode string
	Price        float64
	PriceDate    time.Time
	FetchedAt    time.Time
	Source       string
}

// SymbolError describes a single (symbol, exchange) pair that the provider
// could not resolve. Reason is a short machine-readable tag to ease
// grepping in logs and surfacing counts in the admin RPC response.
type SymbolError struct {
	Symbol   string
	Exchange string
	Reason   string
}
