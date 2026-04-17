package sync

import (
	"context"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"
)

// DBTX is the minimal interface satisfied by both *pgxpool.Pool and pgx.Tx.
// Repositories pass their active tx to CursorStore.Bump so the cursor
// update is atomic with the triggering write.
type DBTX interface {
	Exec(ctx context.Context, sql string, args ...any) (pgconn.CommandTag, error)
}

// CursorStore reads and writes rows in user_sync_cursors.
type CursorStore struct {
	pool *pgxpool.Pool
}

func NewCursorStore(pool *pgxpool.Pool) *CursorStore {
	return &CursorStore{pool: pool}
}

// Bump upserts the cursor using LWW semantics: it only advances
// cursor_at if updatedAt is strictly greater than the stored value.
// Callers MUST pass the tx of their triggering write so the bump is atomic.
func (c *CursorStore) Bump(
	ctx context.Context,
	tx DBTX,
	userID uuid.UUID,
	entityType EntityType,
	updatedAt time.Time,
) error {
	_, err := tx.Exec(ctx, `
		INSERT INTO user_sync_cursors (user_id, entity_type, cursor_at)
		VALUES ($1, $2, $3)
		ON CONFLICT (user_id, entity_type) DO UPDATE
		SET cursor_at = EXCLUDED.cursor_at
		WHERE user_sync_cursors.cursor_at < EXCLUDED.cursor_at
	`, userID, string(entityType), updatedAt)
	return err
}

// GetAll returns one cursor per known entity type. Entities with no
// recorded cursor are reported as the Unix epoch so the client always
// sees a complete map.
func (c *CursorStore) GetAll(
	ctx context.Context,
	userID uuid.UUID,
) (map[EntityType]time.Time, error) {
	rows, err := c.pool.Query(ctx, `
		SELECT entity_type, cursor_at
		FROM user_sync_cursors
		WHERE user_id = $1
	`, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	stored := make(map[EntityType]time.Time, len(AllEntityTypes()))
	for rows.Next() {
		var t string
		var at time.Time
		if err := rows.Scan(&t, &at); err != nil {
			return nil, err
		}
		stored[EntityType(t)] = at.UTC()
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}

	epoch := time.Unix(0, 0).UTC()
	out := make(map[EntityType]time.Time, len(AllEntityTypes()))
	for _, e := range AllEntityTypes() {
		if at, ok := stored[e]; ok {
			out[e] = at
		} else {
			out[e] = epoch
		}
	}
	return out, nil
}
