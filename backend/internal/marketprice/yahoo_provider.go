package marketprice

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"net/url"
	"strings"
	"time"

	"github.com/AlanIsaacV/pocket-pilot/internal/investment"
)

const (
	yahooDefaultBaseURL = "https://query1.finance.yahoo.com/v8/finance/chart"
	yahooDefaultUA      = "Mozilla/5.0 (pocket-pilot marketprice cron)"
)

// yahooDefaultBackoffs is the default exponential backoff ladder between
// retries of the same symbol. Must have at least one entry (the sleep after
// the first failure). Tuning choice documented in the investments doc.
var yahooDefaultBackoffs = []time.Duration{500 * time.Millisecond, 2 * time.Second, 8 * time.Second}

// yahooDefault429Backoff is the sleep used specifically on HTTP 429 before
// retrying, per the investments doc ("long backoff on 429").
const yahooDefault429Backoff = 60 * time.Second

// YahooProvider implements MarketPriceProvider against the unauthenticated
// query1.finance.yahoo.com/v8/finance/chart endpoint. The older
// /v7/finance/quote batch endpoint now gates anonymous traffic behind a
// crumb+cookie flow (returns 401), so we trade batching for a stateless
// per-symbol call.
type YahooProvider struct {
	client         *http.Client
	baseURL        string
	userAgent      string
	backoffs       []time.Duration
	rateLimitSleep time.Duration
}

// Opt configures optional fields of YahooProvider at construction.
type Opt func(*YahooProvider)

// WithBaseURL overrides the chart endpoint. Used by tests to point at
// httptest.NewServer.
func WithBaseURL(u string) Opt { return func(p *YahooProvider) { p.baseURL = u } }

// WithUserAgent overrides the User-Agent header.
func WithUserAgent(ua string) Opt { return func(p *YahooProvider) { p.userAgent = ua } }

// WithBackoffs overrides the retry ladder. Tests use short values so the
// suite stays fast.
func WithBackoffs(durations []time.Duration) Opt {
	return func(p *YahooProvider) { p.backoffs = durations }
}

// WithRateLimitSleep overrides the sleep that follows an HTTP 429 before
// the next retry attempt.
func WithRateLimitSleep(d time.Duration) Opt {
	return func(p *YahooProvider) { p.rateLimitSleep = d }
}

// NewYahooProvider returns a provider ready to fetch quotes. The caller
// supplies an *http.Client whose timeout governs per-request deadlines
// (the package itself never sets a timeout).
func NewYahooProvider(client *http.Client, opts ...Opt) *YahooProvider {
	p := &YahooProvider{
		client:         client,
		baseURL:        yahooDefaultBaseURL,
		userAgent:      yahooDefaultUA,
		backoffs:       yahooDefaultBackoffs,
		rateLimitSleep: yahooDefault429Backoff,
	}
	for _, o := range opts {
		o(p)
	}
	return p
}

// Name identifies the provider for logs and the market_prices.source column.
func (p *YahooProvider) Name() string { return "yahoo" }

// Fetch issues one HTTP GET per symbol against v8/finance/chart and
// aggregates results. A 404 (or a 200 with an empty result) on an
// individual symbol is reported via SymbolError so a single bad ticker
// doesn't poison the whole tick. A non-nil error means a transport-level
// failure that should fail the tick.
func (p *YahooProvider) Fetch(ctx context.Context, symbols []investment.SymbolExchange) ([]Quote, []SymbolError, error) {
	if len(symbols) == 0 {
		return nil, nil, nil
	}

	var (
		quotes []Quote
		errs   []SymbolError
	)
	fetchedAt := time.Now().UTC()

	for _, pair := range symbols {
		if err := ctx.Err(); err != nil {
			return quotes, errs, err
		}
		q, symErr, err := p.fetchOne(ctx, pair, fetchedAt)
		if err != nil {
			return quotes, errs, err
		}
		if symErr != nil {
			errs = append(errs, *symErr)
			continue
		}
		if q != nil {
			quotes = append(quotes, *q)
		}
	}

	slog.LogAttrs(ctx, slog.LevelInfo, "marketprice: yahoo fetch",
		slog.Int("requested", len(symbols)),
		slog.Int("received", len(quotes)),
		slog.Int("missing", len(errs)),
	)

	return quotes, errs, nil
}

func (p *YahooProvider) fetchOne(ctx context.Context, pair investment.SymbolExchange, fetchedAt time.Time) (*Quote, *SymbolError, error) {
	yahooSymbol := toYahooSymbol(pair)
	reqURL := strings.TrimRight(p.baseURL, "/") + "/" + url.PathEscape(yahooSymbol)

	body, status, err := p.doWithRetries(ctx, reqURL)
	if err != nil {
		if status == http.StatusNotFound {
			return nil, &SymbolError{Symbol: pair.Symbol, Exchange: pair.Exchange, Reason: "not_found"}, nil
		}
		return nil, nil, err
	}

	var parsed yahooChartResponse
	if err := json.Unmarshal(body, &parsed); err != nil {
		return nil, nil, fmt.Errorf("yahoo: parse json (symbol=%s, status=%d): %w", yahooSymbol, status, err)
	}

	if parsed.Chart.Error != nil || len(parsed.Chart.Result) == 0 {
		return nil, &SymbolError{Symbol: pair.Symbol, Exchange: pair.Exchange, Reason: "not_found"}, nil
	}

	meta := parsed.Chart.Result[0].Meta
	if meta.RegularMarketPrice == 0 {
		return nil, nil, nil
	}

	return &Quote{
		Symbol:       pair.Symbol,
		Exchange:     pair.Exchange,
		CurrencyCode: meta.Currency,
		Price:        meta.RegularMarketPrice,
		PriceDate:    priceDateFromUnix(meta.RegularMarketTime),
		FetchedAt:    fetchedAt,
		Source:       p.Name(),
	}, nil, nil
}

// doWithRetries performs the HTTP GET with the configured retry ladder.
// Returns body, last status code, and error. A non-nil error means retries
// were exhausted or the context was cancelled. 4xx statuses other than 429
// short-circuit the ladder: retrying a 404 or 401 won't change the answer.
func (p *YahooProvider) doWithRetries(ctx context.Context, reqURL string) ([]byte, int, error) {
	start := time.Now()
	var lastStatus int
	var lastErr error

	attempts := len(p.backoffs) + 1
	for i := range attempts {
		if i > 0 {
			sleep := p.backoffs[i-1]
			if lastStatus == http.StatusTooManyRequests {
				sleep = p.rateLimitSleep
			}
			select {
			case <-ctx.Done():
				return nil, lastStatus, ctx.Err()
			case <-time.After(sleep):
			}
		}

		req, err := http.NewRequestWithContext(ctx, http.MethodGet, reqURL, nil)
		if err != nil {
			return nil, 0, err
		}
		req.Header.Set("User-Agent", p.userAgent)
		req.Header.Set("Accept", "application/json")

		resp, err := p.client.Do(req)
		if err != nil {
			lastErr = err
			lastStatus = 0
			continue
		}
		body, readErr := io.ReadAll(resp.Body)
		_ = resp.Body.Close()
		lastStatus = resp.StatusCode

		if readErr != nil {
			lastErr = readErr
			continue
		}

		if resp.StatusCode == http.StatusOK {
			slog.LogAttrs(ctx, slog.LevelDebug, "marketprice: yahoo http ok",
				slog.Int("attempt", i+1),
				slog.Int64("latency_ms", time.Since(start).Milliseconds()),
			)
			return body, resp.StatusCode, nil
		}

		if resp.StatusCode >= 400 && resp.StatusCode < 500 && resp.StatusCode != http.StatusTooManyRequests {
			return body, resp.StatusCode, fmt.Errorf("yahoo: http %d", resp.StatusCode)
		}

		lastErr = fmt.Errorf("yahoo: http %d", resp.StatusCode)
	}

	if lastErr == nil {
		lastErr = errors.New("yahoo: retries exhausted")
	}
	slog.LogAttrs(ctx, slog.LevelWarn, "marketprice: yahoo retries exhausted",
		slog.Int("attempts", attempts),
		slog.Int("last_status", lastStatus),
		slog.String("error", lastErr.Error()),
	)
	return nil, lastStatus, lastErr
}

// yahooChartResponse mirrors the v8/finance/chart response shape. Only the
// fields we actually consume are declared.
type yahooChartResponse struct {
	Chart struct {
		Result []struct {
			Meta yahooChartMeta `json:"meta"`
		} `json:"result"`
		Error *struct {
			Code        string `json:"code"`
			Description string `json:"description"`
		} `json:"error"`
	} `json:"chart"`
}

type yahooChartMeta struct {
	Symbol             string  `json:"symbol"`
	Currency           string  `json:"currency"`
	RegularMarketPrice float64 `json:"regularMarketPrice"`
	RegularMarketTime  int64   `json:"regularMarketTime"`
}

// toYahooSymbol maps our (symbol, exchange) to the Yahoo convention.
// BMV symbols need the ".MX" suffix; US exchanges use the bare ticker.
// Everything is uppercased to match how Yahoo returns it.
func toYahooSymbol(pair investment.SymbolExchange) string {
	sym := strings.ToUpper(strings.TrimSpace(pair.Symbol))
	switch strings.ToUpper(strings.TrimSpace(pair.Exchange)) {
	case "BMV":
		return sym + ".MX"
	default:
		return sym
	}
}

func priceDateFromUnix(secs int64) time.Time {
	if secs <= 0 {
		return time.Now().UTC().Truncate(24 * time.Hour)
	}
	t := time.Unix(secs, 0).UTC()
	return time.Date(t.Year(), t.Month(), t.Day(), 0, 0, 0, 0, time.UTC)
}
