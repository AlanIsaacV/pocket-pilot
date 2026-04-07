package auth

import (
	"time"

	"github.com/google/uuid"
)

type User struct {
	ID        uuid.UUID
	Email     string
	CreatedAt time.Time
	UpdatedAt time.Time
}

type UserIdentity struct {
	ID         uuid.UUID
	UserID     uuid.UUID
	Provider   string
	ProviderID string
	CreatedAt  time.Time
}

type RefreshTokenRecord struct {
	ID        uuid.UUID
	UserID    uuid.UUID
	TokenHash string
	ExpiresAt time.Time
	IsRevoked bool
	CreatedAt time.Time
}
