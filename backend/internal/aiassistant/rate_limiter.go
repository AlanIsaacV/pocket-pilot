package aiassistant

import (
	"context"
	"fmt"

	"github.com/google/uuid"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

type RateLimiter struct {
	repo              *Repository
	dailyRequestLimit int
	monthlyTokenLimit int
}

func NewRateLimiter(repo *Repository, dailyRequestLimit, monthlyTokenLimit int) *RateLimiter {
	return &RateLimiter{
		repo:              repo,
		dailyRequestLimit: dailyRequestLimit,
		monthlyTokenLimit: monthlyTokenLimit,
	}
}

// Check returns a gRPC RESOURCE_EXHAUSTED error if the user has exceeded
// either the daily request limit or the monthly token limit.
func (rl *RateLimiter) Check(ctx context.Context, userID uuid.UUID) error {
	stats, err := rl.repo.GetUsageStats(ctx, userID)
	if err != nil {
		return fmt.Errorf("rate limiter: %w", err)
	}

	if stats.DailyRequests >= rl.dailyRequestLimit {
		return status.Errorf(codes.ResourceExhausted,
			"Has alcanzado tu limite diario de %d solicitudes. Intenta manana.",
			rl.dailyRequestLimit)
	}

	if stats.MonthlyTokens >= rl.monthlyTokenLimit {
		return status.Errorf(codes.ResourceExhausted,
			"Has alcanzado tu limite mensual de tokens. El limite se reinicia el proximo mes.")
	}

	return nil
}
