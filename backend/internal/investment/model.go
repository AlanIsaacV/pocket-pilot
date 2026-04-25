package investment

import (
	"strings"
	"time"

	"github.com/google/uuid"
)

// Holding mirrors the investment_holdings table. Holdings are globals: they
// describe the asset (symbol+exchange+currency) and are not tied to any
// particular account. The owning account is recorded on each lot instead.
type Holding struct {
	ID           uuid.UUID
	UserID       uuid.UUID
	Symbol       string
	Exchange     string
	DisplayName  string
	CurrencyCode string
	AssetType    string
	Status       string
	ManualPrice  *float64
	Notes        *string
	CreatedAt    time.Time
	UpdatedAt    time.Time
	DeletedAt    *time.Time
}

// Split mirrors the investment_splits table. Forward splits have
// ratio_num > ratio_den; reverse splits have ratio_num < ratio_den. The math
// walks (lots ∪ splits) chronologically and adjusts the FIFO state in flight
// (qty *= ratio, price /= ratio).
type Split struct {
	ID         uuid.UUID
	UserID     uuid.UUID
	HoldingID  uuid.UUID
	RatioNum   float64
	RatioDen   float64
	OccurredAt time.Time
	Notes      *string
	CreatedAt  time.Time
	UpdatedAt  time.Time
	DeletedAt  *time.Time
}

// Lot mirrors the investment_lots table.
type Lot struct {
	ID         uuid.UUID
	UserID     uuid.UUID
	HoldingID  uuid.UUID
	AccountID  uuid.UUID
	Kind       string
	Quantity   float64
	Price      float64
	FeeCents   int64
	FxRate     *float64
	OccurredAt time.Time
	Validity   string
	Notes      *string
	CreatedAt  time.Time
	UpdatedAt  time.Time
	DeletedAt  *time.Time
}

// SymbolExchange is the natural identifier for an asset quote: the ticker
// together with the exchange it trades on. Exposed here (not in the
// marketprice package) to break the import cycle — investment is a
// leaf package, marketprice depends on it.
type SymbolExchange struct {
	Symbol   string
	Exchange string
}

// MarketPrice mirrors the market_prices table (natural key: symbol+exchange).
type MarketPrice struct {
	Symbol       string
	Exchange     string
	CurrencyCode string
	Price        float64
	PriceDate    time.Time
	Source       string
	FetchedAt    time.Time
	UpdatedAt    time.Time
}

func dateOnly(t time.Time) time.Time {
	utc := t.UTC()
	return time.Date(utc.Year(), utc.Month(), utc.Day(), 0, 0, 0, 0, time.UTC)
}

func normalizeLower(value string) string {
	return strings.ToLower(strings.TrimSpace(value))
}

func normalizeUpper(value string) string {
	return strings.ToUpper(strings.TrimSpace(value))
}
