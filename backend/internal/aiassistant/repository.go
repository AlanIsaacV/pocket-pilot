package aiassistant

import (
	"context"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
)

// FeatureChat y FeatureNotificationParser son los únicos features hoy. Si se
// agregan más, declararlos aquí y mantener el ENUM de la DB en sync.
const (
	FeatureChat               = "chat"
	FeatureNotificationParser = "notification_parser"
)

type Repository struct {
	pool *pgxpool.Pool
}

func NewRepository(pool *pgxpool.Pool) *Repository {
	return &Repository{pool: pool}
}

// RecordUsage inserts a new usage entry after a successful LLM call. El
// `feature` segmenta la cuota por funcionalidad (chat, notification_parser, ...)
// para que rate limits independientes puedan coexistir sobre la misma tabla.
func (r *Repository) RecordUsage(ctx context.Context, userID uuid.UUID, feature string, prompt, completion int) error {
	total := prompt + completion
	_, err := r.pool.Exec(ctx, `
		INSERT INTO ai_usage (id, user_id, feature, prompt_tokens, completion_tokens, total_tokens, created_at, updated_at)
		VALUES ($1, $2, $3, $4, $5, $6, NOW(), NOW())
	`, uuid.New(), userID, feature, prompt, completion, total)
	return err
}

// CountRequestsToday returns the number of AI requests the user has made today
// for the given feature.
func (r *Repository) CountRequestsToday(ctx context.Context, userID uuid.UUID, feature string) (int, error) {
	var count int
	err := r.pool.QueryRow(ctx, `
		SELECT COUNT(*) FROM ai_usage
		WHERE user_id = $1 AND feature = $2 AND created_at >= current_date
	`, userID, feature).Scan(&count)
	return count, err
}

// SumTokensThisMonth returns the total tokens consumed by the user this month
// for the given feature.
func (r *Repository) SumTokensThisMonth(ctx context.Context, userID uuid.UUID, feature string) (int, error) {
	var total int
	err := r.pool.QueryRow(ctx, `
		SELECT COALESCE(SUM(total_tokens), 0) FROM ai_usage
		WHERE user_id = $1 AND feature = $2 AND created_at >= date_trunc('month', now())
	`, userID, feature).Scan(&total)
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

// GetUsageStats fetches both daily requests and monthly tokens in two queries
// scoped to the given feature.
func (r *Repository) GetUsageStats(ctx context.Context, userID uuid.UUID, feature string) (*UsageStats, error) {
	daily, err := r.CountRequestsToday(ctx, userID, feature)
	if err != nil {
		return nil, err
	}

	monthly, err := r.SumTokensThisMonth(ctx, userID, feature)
	if err != nil {
		return nil, err
	}

	return &UsageStats{
		DailyRequests: daily,
		MonthlyTokens: monthly,
		AsOf:          time.Now().UTC(),
	}, nil
}
