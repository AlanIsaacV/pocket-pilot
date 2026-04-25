package investment

import (
	"context"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/AlanIsaacV/pocket-pilot/internal/sync"
)

type SplitRepository struct {
	pool   *pgxpool.Pool
	cursor *sync.CursorStore
}

func NewSplitRepository(pool *pgxpool.Pool, cursor *sync.CursorStore) *SplitRepository {
	return &SplitRepository{pool: pool, cursor: cursor}
}

const splitScanColumns = `id, user_id, holding_id, ratio_num, ratio_den, occurred_at, notes, created_at, updated_at, deleted_at`

func scanSplit(row pgx.Row) (*Split, error) {
	s := &Split{}
	err := row.Scan(
		&s.ID,
		&s.UserID,
		&s.HoldingID,
		&s.RatioNum,
		&s.RatioDen,
		&s.OccurredAt,
		&s.Notes,
		&s.CreatedAt,
		&s.UpdatedAt,
		&s.DeletedAt,
	)
	if err != nil {
		return nil, err
	}
	return s, nil
}

func (r *SplitRepository) GetByID(ctx context.Context, id, userID uuid.UUID) (*Split, error) {
	row := r.pool.QueryRow(
		ctx,
		`SELECT `+splitScanColumns+` FROM investment_splits WHERE id = $1 AND user_id = $2`,
		id,
		userID,
	)
	return scanSplit(row)
}

func (r *SplitRepository) List(ctx context.Context, userID uuid.UUID, updatedSince *time.Time, limit, offset int) ([]*Split, time.Time, error) {
	syncedAt := time.Now().UTC()

	var (
		rows pgx.Rows
		err  error
	)

	if updatedSince != nil {
		rows, err = r.pool.Query(
			ctx,
			`SELECT `+splitScanColumns+`
			 FROM investment_splits
			 WHERE user_id = $1 AND updated_at > $2
			 ORDER BY updated_at ASC`,
			userID,
			updatedSince,
		)
	} else {
		rows, err = r.pool.Query(
			ctx,
			`SELECT `+splitScanColumns+`
			 FROM investment_splits
			 WHERE user_id = $1 AND deleted_at IS NULL
			 ORDER BY occurred_at DESC, created_at DESC
			 LIMIT $2 OFFSET $3`,
			userID,
			limit,
			offset,
		)
	}
	if err != nil {
		return nil, syncedAt, err
	}
	defer rows.Close()

	var items []*Split
	for rows.Next() {
		s, err := scanSplit(rows)
		if err != nil {
			return nil, syncedAt, err
		}
		items = append(items, s)
	}
	return items, syncedAt, rows.Err()
}

func (r *SplitRepository) Upsert(ctx context.Context, s *Split) (*Split, bool, error) {
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return nil, false, err
	}
	defer tx.Rollback(ctx)

	row := tx.QueryRow(
		ctx,
		`
		INSERT INTO investment_splits (
			id, user_id, holding_id, ratio_num, ratio_den, occurred_at, notes,
			created_at, updated_at
		)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
		ON CONFLICT (id) DO UPDATE SET
			holding_id  = EXCLUDED.holding_id,
			ratio_num   = EXCLUDED.ratio_num,
			ratio_den   = EXCLUDED.ratio_den,
			occurred_at = EXCLUDED.occurred_at,
			notes       = EXCLUDED.notes,
			updated_at  = EXCLUDED.updated_at
		WHERE investment_splits.updated_at < EXCLUDED.updated_at
		RETURNING `+splitScanColumns,
		s.ID,
		s.UserID,
		s.HoldingID,
		s.RatioNum,
		s.RatioDen,
		s.OccurredAt,
		s.Notes,
		s.CreatedAt,
		s.UpdatedAt,
	)

	result, err := scanSplit(row)
	if err == nil {
		if err := r.cursor.Bump(ctx, tx, s.UserID, sync.EntityInvestmentSplit, result.UpdatedAt); err != nil {
			return nil, false, err
		}
		if err := tx.Commit(ctx); err != nil {
			return nil, false, err
		}
		return result, false, nil
	}
	if err != pgx.ErrNoRows {
		return nil, false, err
	}

	current, err := r.GetByID(ctx, s.ID, s.UserID)
	if err != nil {
		return nil, false, err
	}
	return current, true, nil
}

func (r *SplitRepository) SoftDelete(ctx context.Context, id, userID uuid.UUID, deletedAt time.Time) error {
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)

	tag, err := tx.Exec(
		ctx,
		`UPDATE investment_splits SET deleted_at = $3, updated_at = $3
		 WHERE id = $1 AND user_id = $2
		   AND (deleted_at IS NULL OR updated_at < $3)`,
		id,
		userID,
		deletedAt,
	)
	if err != nil {
		return err
	}
	if tag.RowsAffected() > 0 {
		if err := r.cursor.Bump(ctx, tx, userID, sync.EntityInvestmentSplit, deletedAt); err != nil {
			return err
		}
	}
	return tx.Commit(ctx)
}
