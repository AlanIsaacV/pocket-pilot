package marketprice

import (
	"context"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"github.com/AlanIsaacV/pocket-pilot/internal/investment"
)

// Short backoffs keep the table tests effectively instant; the production
// defaults are exercised via the integration suite.
var testBackoffs = []time.Duration{time.Millisecond, time.Millisecond, time.Millisecond}

func mustReadFixture(t *testing.T, path string) []byte {
	t.Helper()
	b, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("read fixture %s: %v", path, err)
	}
	return b
}

func newTestProvider(t *testing.T, serverURL string) *YahooProvider {
	t.Helper()
	return NewYahooProvider(
		&http.Client{Timeout: 2 * time.Second},
		WithBaseURL(serverURL),
		WithBackoffs(testBackoffs),
		WithRateLimitSleep(time.Millisecond),
	)
}

// chartHandler dispatches a request against the v8 chart path (/SYMBOL) by
// looking up the symbol in the bodies map. A missing symbol yields a 404
// with a Yahoo-shaped "Not Found" body, mirroring production behavior.
func chartHandler(bodies map[string][]byte) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		sym := strings.TrimPrefix(r.URL.Path, "/")
		b, ok := bodies[sym]
		if !ok {
			w.Header().Set("Content-Type", "application/json")
			w.WriteHeader(http.StatusNotFound)
			_, _ = w.Write([]byte(`{"chart":{"result":null,"error":{"code":"Not Found","description":"unknown"}}}`))
			return
		}
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write(b)
	}
}

func TestYahooProvider_Happy(t *testing.T) {
	bodies := map[string][]byte{
		"AAPL": mustReadFixture(t, "testdata/yahoo_happy.json"),
		"MSFT": mustReadFixture(t, "testdata/yahoo_msft.json"),
	}
	srv := httptest.NewServer(chartHandler(bodies))
	defer srv.Close()

	p := newTestProvider(t, srv.URL)
	quotes, errs, err := p.Fetch(context.Background(), []investment.SymbolExchange{
		{Symbol: "AAPL", Exchange: "NASDAQ"},
		{Symbol: "MSFT", Exchange: "NASDAQ"},
	})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(errs) != 0 {
		t.Fatalf("expected no symbol errors, got %#v", errs)
	}
	if len(quotes) != 2 {
		t.Fatalf("expected 2 quotes, got %d", len(quotes))
	}
	for _, q := range quotes {
		if q.Source != "yahoo" {
			t.Errorf("expected source=yahoo, got %s", q.Source)
		}
		if q.CurrencyCode != "USD" {
			t.Errorf("expected USD, got %s (symbol=%s)", q.CurrencyCode, q.Symbol)
		}
		if q.Price <= 0 {
			t.Errorf("expected positive price, got %f (symbol=%s)", q.Price, q.Symbol)
		}
		if q.PriceDate.IsZero() {
			t.Errorf("expected non-zero price date for %s", q.Symbol)
		}
	}
}

func TestYahooProvider_UnknownSymbol(t *testing.T) {
	bodies := map[string][]byte{
		"AAPL": mustReadFixture(t, "testdata/yahoo_happy.json"),
	}
	var calls atomic.Int32
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		calls.Add(1)
		chartHandler(bodies)(w, r)
	}))
	defer srv.Close()

	p := newTestProvider(t, srv.URL)
	quotes, errs, err := p.Fetch(context.Background(), []investment.SymbolExchange{
		{Symbol: "AAPL", Exchange: "NASDAQ"},
		{Symbol: "FAKE", Exchange: "NASDAQ"},
	})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(quotes) != 1 {
		t.Fatalf("expected 1 quote, got %d", len(quotes))
	}
	if len(errs) != 1 || errs[0].Symbol != "FAKE" || errs[0].Reason != "not_found" {
		t.Fatalf("expected FAKE not_found, got %#v", errs)
	}
	// Exactly one call per symbol: the 404 must short-circuit retries.
	if got := int(calls.Load()); got != 2 {
		t.Fatalf("expected 2 HTTP calls (one per symbol, no 404 retries), got %d", got)
	}
}

func TestYahooProvider_NotFoundBodyWith200(t *testing.T) {
	// Yahoo occasionally answers 200 OK with an empty result block. Treat
	// that as not_found rather than a parse error.
	bodies := map[string][]byte{
		"AAPL": mustReadFixture(t, "testdata/yahoo_not_found.json"),
	}
	srv := httptest.NewServer(chartHandler(bodies))
	defer srv.Close()

	p := newTestProvider(t, srv.URL)
	quotes, errs, err := p.Fetch(context.Background(), []investment.SymbolExchange{
		{Symbol: "AAPL", Exchange: "NASDAQ"},
	})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(quotes) != 0 {
		t.Fatalf("expected 0 quotes, got %d", len(quotes))
	}
	if len(errs) != 1 || errs[0].Reason != "not_found" {
		t.Fatalf("expected not_found, got %#v", errs)
	}
}

func TestYahooProvider_MalformedJSON(t *testing.T) {
	body := mustReadFixture(t, "testdata/yahoo_malformed.json")
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		_, _ = w.Write(body)
	}))
	defer srv.Close()

	p := newTestProvider(t, srv.URL)
	_, _, err := p.Fetch(context.Background(), []investment.SymbolExchange{
		{Symbol: "AAPL", Exchange: "NASDAQ"},
	})
	if err == nil {
		t.Fatalf("expected parse error, got nil")
	}
}

func TestYahooProvider_RateLimitThenOK(t *testing.T) {
	body := mustReadFixture(t, "testdata/yahoo_happy.json")
	var calls atomic.Int32
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		n := calls.Add(1)
		if n == 1 {
			w.WriteHeader(http.StatusTooManyRequests)
			return
		}
		_, _ = w.Write(body)
	}))
	defer srv.Close()

	p := newTestProvider(t, srv.URL)
	quotes, _, err := p.Fetch(context.Background(), []investment.SymbolExchange{
		{Symbol: "AAPL", Exchange: "NASDAQ"},
	})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(quotes) != 1 {
		t.Fatalf("expected 1 quote after retry, got %d", len(quotes))
	}
	if calls.Load() < 2 {
		t.Fatalf("expected at least 2 HTTP calls, got %d", calls.Load())
	}
}

func TestYahooProvider_5xxExhausted(t *testing.T) {
	var calls atomic.Int32
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		calls.Add(1)
		w.WriteHeader(http.StatusInternalServerError)
	}))
	defer srv.Close()

	p := newTestProvider(t, srv.URL)
	_, _, err := p.Fetch(context.Background(), []investment.SymbolExchange{
		{Symbol: "AAPL", Exchange: "NASDAQ"},
	})
	if err == nil {
		t.Fatalf("expected error after retries exhausted")
	}
	// initial + len(testBackoffs) retries = 4 calls
	if got := int(calls.Load()); got != len(testBackoffs)+1 {
		t.Fatalf("expected %d calls, got %d", len(testBackoffs)+1, got)
	}
}

func TestYahooProvider_401ShortCircuits(t *testing.T) {
	// If Yahoo flips v8 behind auth (as happened to v7), we should bail on
	// the first 401 instead of hammering the retry ladder.
	var calls atomic.Int32
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		calls.Add(1)
		w.WriteHeader(http.StatusUnauthorized)
	}))
	defer srv.Close()

	p := newTestProvider(t, srv.URL)
	_, _, err := p.Fetch(context.Background(), []investment.SymbolExchange{
		{Symbol: "AAPL", Exchange: "NASDAQ"},
	})
	if err == nil {
		t.Fatalf("expected error on 401")
	}
	if got := int(calls.Load()); got != 1 {
		t.Fatalf("expected 1 HTTP call (no retries on 401), got %d", got)
	}
}

func TestYahooProvider_BMVSuffix(t *testing.T) {
	body := mustReadFixture(t, "testdata/yahoo_bmv.json")
	var received string
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		received = strings.TrimPrefix(r.URL.Path, "/")
		_, _ = w.Write(body)
	}))
	defer srv.Close()

	p := newTestProvider(t, srv.URL)
	quotes, _, err := p.Fetch(context.Background(), []investment.SymbolExchange{
		{Symbol: "VAS", Exchange: "BMV"},
	})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if received != "VAS.MX" {
		t.Fatalf("expected path symbol=VAS.MX, got %q", received)
	}
	if len(quotes) != 1 || quotes[0].Exchange != "BMV" {
		t.Fatalf("expected one quote mapped back to BMV, got %#v", quotes)
	}
	if quotes[0].CurrencyCode != "MXN" {
		t.Fatalf("expected MXN currency, got %s", quotes[0].CurrencyCode)
	}
}

func TestYahooProvider_OneCallPerSymbol(t *testing.T) {
	body := mustReadFixture(t, "testdata/yahoo_happy.json")
	var calls atomic.Int32
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		calls.Add(1)
		_, _ = w.Write(body)
	}))
	defer srv.Close()

	p := NewYahooProvider(
		&http.Client{Timeout: 2 * time.Second},
		WithBaseURL(srv.URL),
		WithBackoffs(testBackoffs),
	)

	_, _, err := p.Fetch(context.Background(), []investment.SymbolExchange{
		{Symbol: "AAPL", Exchange: "NASDAQ"},
		{Symbol: "MSFT", Exchange: "NASDAQ"},
		{Symbol: "GOOG", Exchange: "NASDAQ"},
	})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if got := int(calls.Load()); got != 3 {
		t.Fatalf("expected 3 HTTP calls (one per symbol), got %d", got)
	}
}

func TestTimeUntilNextFire(t *testing.T) {
	cases := []struct {
		name     string
		now      time.Time
		fireHour int
		wantHrs  float64
	}{
		{
			name:     "before fire hour",
			now:      time.Date(2026, 4, 21, 20, 30, 0, 0, time.UTC),
			fireHour: 22,
			wantHrs:  1.5,
		},
		{
			name:     "exactly at fire hour rolls over",
			now:      time.Date(2026, 4, 21, 22, 0, 0, 0, time.UTC),
			fireHour: 22,
			wantHrs:  24,
		},
		{
			name:     "after fire hour",
			now:      time.Date(2026, 4, 21, 23, 0, 0, 0, time.UTC),
			fireHour: 22,
			wantHrs:  23,
		},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got := timeUntilNextFire(tc.now, tc.fireHour)
			want := time.Duration(tc.wantHrs * float64(time.Hour))
			if got != want {
				t.Fatalf("got %s, want %s", got, want)
			}
		})
	}
}
