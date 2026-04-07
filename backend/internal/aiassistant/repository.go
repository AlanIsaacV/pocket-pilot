package aiassistant

import (
	"context"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
)

type Repository struct {
	pool *pgxpool.Pool
}

func NewRepository(pool *pgxpool.Pool) *Repository {
	return &Repository{pool: pool}
}

// RecordUsage inserts a new usage entry after a successful LLM call.
func (r *Repository) RecordUsage(ctx context.Context, userID uuid.UUID, prompt, completion int) error {
	total := prompt + completion
	_, err := r.pool.Exec(ctx, `
		INSERT INTO ai_usage (id, user_id, prompt_tokens, completion_tokens, total_tokens, created_at, updated_at)
		VALUES ($1, $2, $3, $4, $5, NOW(), NOW())
	`, uuid.New(), userID, prompt, completion, total)
	return err
}

// CountRequestsToday returns the number of AI requests the user has made today.
func (r *Repository) CountRequestsToday(ctx context.Context, userID uuid.UUID) (int, error) {
	var count int
	err := r.pool.QueryRow(ctx, `
		SELECT COUNT(*) FROM ai_usage
		WHERE user_id = $1 AND created_at >= current_date
	`, userID).Scan(&count)
	return count, err
}

// SumTokensThisMonth returns the total tokens consumed by the user this month.
func (r *Repository) SumTokensThisMonth(ctx context.Context, userID uuid.UUID) (int, error) {
	var total int
	err := r.pool.QueryRow(ctx, `
		SELECT COALESCE(SUM(total_tokens), 0) FROM ai_usage
		WHERE user_id = $1 AND created_at >= date_trunc('month', now())
	`, userID).Scan(&total)
	return total, err
}

// UsageStats holds the current usage for rate limit checks.
type UsageStats struct {
	DailyRequests int
	MonthlyTokens int
	AsOf          time.Time
}

// RecordUnsupportedToolCall inserts a report when the AI calls the unsupported tool.
func (r *Repository) RecordUnsupportedToolCall(ctx context.Context, userID uuid.UUID, userIntent, reason string) error {
	_, err := r.pool.Exec(ctx, `
		INSERT INTO ai_unsupported_tool_reports (id, user_id, user_intent, reason, created_at)
		VALUES ($1, $2, $3, $4, NOW())
	`, uuid.New(), userID, userIntent, reason)
	return err
}

// GetUsageStats fetches both daily requests and monthly tokens in two queries.
func (r *Repository) GetUsageStats(ctx context.Context, userID uuid.UUID) (*UsageStats, error) {
	daily, err := r.CountRequestsToday(ctx, userID)
	if err != nil {
		return nil, err
	}

	monthly, err := r.SumTokensThisMonth(ctx, userID)
	if err != nil {
		return nil, err
	}

	return &UsageStats{
		DailyRequests: daily,
		MonthlyTokens: monthly,
		AsOf:          time.Now().UTC(),
	}, nil
}
