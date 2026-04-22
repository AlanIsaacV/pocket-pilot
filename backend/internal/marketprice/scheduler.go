package marketprice

import (
	"context"
	"log/slog"
	"time"

	"github.com/AlanIsaacV/pocket-pilot/internal/investment"
)

// Scheduler owns the daily fetch loop. It is constructed once in main.go
// and, when MARKETPRICE_ENABLED is true, runs in its own goroutine for the
// lifetime of the server.
type Scheduler struct {
	provider    MarketPriceProvider
	priceRepo   *investment.MarketPriceRepository
	holdingRepo *investment.HoldingRepository

	runOnBoot bool

	// fireHour is the UTC hour of day the scheduler aligns to. Default is
	// 22 so NYSE (21:00 UTC close) and BMV (20:00 UTC close) are both
	// settled. Tests set a different value.
	fireHour int

	// now is injectable so unit tests can assert the alignment math.
	now func() time.Time

	stop chan struct{}
	done chan struct{}
}

// NewScheduler wires the dependencies. It does not spawn any goroutine —
// call Start for that.
func NewScheduler(
	provider MarketPriceProvider,
	priceRepo *investment.MarketPriceRepository,
	holdingRepo *investment.HoldingRepository,
	runOnBoot bool,
) *Scheduler {
	return &Scheduler{
		provider:    provider,
		priceRepo:   priceRepo,
		holdingRepo: holdingRepo,
		runOnBoot:   runOnBoot,
		fireHour:    22,
		now:         func() time.Time { return time.Now().UTC() },
		stop:        make(chan struct{}),
		done:        make(chan struct{}),
	}
}

// Start begins the scheduler loop. It returns once the goroutine has been
// spawned; use Stop to shut it down cleanly.
func (s *Scheduler) Start(ctx context.Context) {
	go s.run(ctx)
}

// Stop signals the loop to exit and blocks until it acknowledges.
// Idempotent: repeated calls are safe.
func (s *Scheduler) Stop() {
	select {
	case <-s.stop:
		// Already signalled.
	default:
		close(s.stop)
	}
	<-s.done
}

func (s *Scheduler) run(ctx context.Context) {
	defer close(s.done)

	if s.runOnBoot {
		if _, _, _, err := s.Tick(ctx); err != nil {
			slog.LogAttrs(ctx, slog.LevelWarn, "marketprice: boot tick failed",
				slog.String("error", err.Error()),
			)
		}
	}

	first := timeUntilNextFire(s.now(), s.fireHour)
	timer := time.NewTimer(first)
	defer timer.Stop()

	for {
		select {
		case <-s.stop:
			slog.Info("marketprice: scheduler stopping")
			return
		case <-ctx.Done():
			slog.LogAttrs(ctx, slog.LevelInfo, "marketprice: scheduler context cancelled",
				slog.String("error", ctx.Err().Error()),
			)
			return
		case <-timer.C:
			if _, _, _, err := s.Tick(ctx); err != nil {
				slog.LogAttrs(ctx, slog.LevelWarn, "marketprice: tick failed",
					slog.String("error", err.Error()),
				)
			}
			// Reset the timer so the next fire lands at the same UTC
			// hour even if the tick took a while. The investments doc
			// calls for 24h cadence; we recompute each cycle so clock
			// skew or DST-like edge cases don't drift.
			timer.Reset(timeUntilNextFire(s.now(), s.fireHour))
		}
	}
}

// Tick performs a single fetch+upsert cycle across every active
// (symbol, exchange) pair. Exported so tests can drive it directly.
func (s *Scheduler) Tick(ctx context.Context) (int, int, []SymbolError, error) {
	symbols, err := s.holdingRepo.ListActiveSymbolExchanges(ctx)
	if err != nil {
		return 0, 0, nil, err
	}
	if len(symbols) == 0 {
		slog.LogAttrs(ctx, slog.LevelInfo, "marketprice: tick skipped",
			slog.String("reason", "no_active_holdings"),
		)
		return 0, 0, nil, nil
	}
	return s.Refresh(ctx, symbols)
}

// Refresh fans a provider fetch out and upserts each successful quote.
// Errors from individual upserts are logged but do not abort the loop, so
// one bad row does not poison the whole tick.
func (s *Scheduler) Refresh(ctx context.Context, symbols []investment.SymbolExchange) (int, int, []SymbolError, error) {
	start := time.Now()
	slog.LogAttrs(ctx, slog.LevelInfo, "marketprice: tick_start",
		slog.Int("symbols", len(symbols)),
		slog.String("provider", s.provider.Name()),
	)

	quotes, providerErrs, err := s.provider.Fetch(ctx, symbols)
	if err != nil {
		return 0, 0, providerErrs, err
	}

	updated := 0
	failed := len(providerErrs)
	for _, q := range quotes {
		mp := &investment.MarketPrice{
			Symbol:       q.Symbol,
			Exchange:     q.Exchange,
			CurrencyCode: q.CurrencyCode,
			Price:        q.Price,
			PriceDate:    q.PriceDate,
			Source:       q.Source,
			FetchedAt:    q.FetchedAt,
			UpdatedAt:    q.FetchedAt,
		}
		if err := s.priceRepo.Upsert(ctx, mp); err != nil {
			failed++
			providerErrs = append(providerErrs, SymbolError{
				Symbol:   q.Symbol,
				Exchange: q.Exchange,
				Reason:   "upsert_error",
			})
			slog.LogAttrs(ctx, slog.LevelError, "marketprice: upsert failed",
				slog.String("symbol", q.Symbol),
				slog.String("exchange", q.Exchange),
				slog.String("error", err.Error()),
			)
			continue
		}
		updated++
	}

	slog.LogAttrs(ctx, slog.LevelInfo, "marketprice: tick_complete",
		slog.Int("symbols", len(symbols)),
		slog.Int("updated", updated),
		slog.Int("failed", failed),
		slog.Int64("duration_ms", time.Since(start).Milliseconds()),
	)

	return updated, failed, providerErrs, nil
}

// timeUntilNextFire returns the delay from now until the next occurrence
// of fireHour:00 UTC. If the current moment is exactly at that hour, the
// function returns 24h (so a restart at the boundary does not skip the
// next fire).
func timeUntilNextFire(now time.Time, fireHour int) time.Duration {
	now = now.UTC()
	next := time.Date(now.Year(), now.Month(), now.Day(), fireHour, 0, 0, 0, time.UTC)
	if !next.After(now) {
		next = next.Add(24 * time.Hour)
	}
	return next.Sub(now)
}
