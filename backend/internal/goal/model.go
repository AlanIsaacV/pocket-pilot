package goal

import (
	"strings"
	"time"

	"github.com/google/uuid"
)

// Goal mirrors the goals table.
type Goal struct {
	ID                uuid.UUID
	UserID            uuid.UUID
	Name              string
	TargetAmountCents int64
	SavedAmountCents  int64
	TargetDate        time.Time
	CreatedAt         time.Time
	UpdatedAt         time.Time
	DeletedAt         *time.Time
}

func dateOnly(t time.Time) time.Time {
	utc := t.UTC()
	return time.Date(utc.Year(), utc.Month(), utc.Day(), 0, 0, 0, 0, time.UTC)
}

func normalizeName(value string) string {
	return strings.TrimSpace(value)
}
