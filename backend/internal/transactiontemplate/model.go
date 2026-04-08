package transactiontemplate

import (
	"time"

	"github.com/google/uuid"
)

// Template mirrors the transaction_templates table.
type Template struct {
	ID           uuid.UUID
	UserID       uuid.UUID
	Name         string
	AccountID    uuid.UUID
	ToAccountID  *uuid.UUID
	CategoryID   *uuid.UUID
	Type         string
	AmountCents  *int64
	CurrencyCode string
	Tags         []string
	Description  string
	Frequency    *string
	NextDate     *time.Time
	EndDate      *time.Time
	CreatedAt    time.Time
	UpdatedAt    time.Time
	DeletedAt    *time.Time
	IsAutoCharge bool
	IsActive     bool
	Nature       string
}

func dateOnly(t time.Time) time.Time {
	utc := t.UTC()
	return time.Date(utc.Year(), utc.Month(), utc.Day(), 0, 0, 0, 0, time.UTC)
}
