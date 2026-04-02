package budget

import (
	"strings"
	"time"

	"github.com/google/uuid"
)

// Budget mirrors the budgets table.
type Budget struct {
	ID               uuid.UUID
	UserID           uuid.UUID
	CategoryID       uuid.UUID
	LimitAmountCents int64
	CurrencyCode     string
	Period           string
	CreatedAt        time.Time
	UpdatedAt        time.Time
	DeletedAt        *time.Time
}

func normalizePeriod(value string) string {
	return strings.ToUpper(strings.TrimSpace(value))
}
