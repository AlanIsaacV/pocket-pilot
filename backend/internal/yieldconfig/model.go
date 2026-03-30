package yieldconfig

import (
	"strings"
	"time"

	"github.com/google/uuid"
)

// YieldConfig mirrors the yield_configs table.
type YieldConfig struct {
	ID              uuid.UUID
	UserID          uuid.UUID
	AccountID       uuid.UUID
	Name            string
	AmountCents     int64
	ApyRate         float64
	PayoutFrequency string
	NextDate        time.Time
	MaturityDate    *time.Time
	TermDays        *int32
	AutoRenew       bool
	Status          string
	CreatedAt       time.Time
	UpdatedAt       time.Time
	DeletedAt       *time.Time
}

func dateOnly(t time.Time) time.Time {
	utc := t.UTC()
	return time.Date(utc.Year(), utc.Month(), utc.Day(), 0, 0, 0, 0, time.UTC)
}

func normalizeLower(value string) string {
	return strings.ToLower(strings.TrimSpace(value))
}
