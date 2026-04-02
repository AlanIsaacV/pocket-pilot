package goal

import (
	"context"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

type Repository struct {
	pool *pgxpool.Pool
}

func NewRepository(pool *pgxpool.Pool) *Repository {
	return &Repository{pool: pool}
}

const scanColumns = `id, user_id, name, target_amount_cents, saved_amount_cents, target_date, created_at, updated_at, deleted_at`

func (r *Repository) scan(row pgx.Row) (*Goal, error) {
	g := &Goal{}
	err := row.Scan(
		&g.ID,
		&g.UserID,
		&g.Name,
		&g.TargetAmountCents,
		&g.SavedAmountCents,
		&g.TargetDate,
		&g.CreatedAt,
		&g.UpdatedAt,
		&g.DeletedAt,
	)
	if err != nil {
		return nil, err
	}
	return g, nil
}

func (r *Repository) GetByID(ctx context.Context, id, userID uuid.UUID) (*Goal, error) {
	row := r.pool.QueryRow(
		ctx,
		`SELECT `+scanColumns+` FROM goals WHERE id = $1 AND user_id = $2`,
		id,
		userID,
	)
	return r.scan(row)
}

func (r *Repository) List(ctx context.Context, userID uuid.UUID, updatedSince *time.Time, limit, offset int) ([]*Goal, time.Time, error) {
	syncedAt := time.Now().UTC()

	var (
		rows pgx.Rows
		err  error
	)

	if updatedSince != nil {
		rows, err = r.pool.Query(
			ctx,
			`SELECT `+scanColumns+`
			 FROM goals
			 WHERE user_id = $1 AND updated_at > $2
			 ORDER BY updated_at ASC, id ASC`,
			userID,
			updatedSince,
		)
	} else {
		rows, err = r.pool.Query(
			ctx,
			`SELECT `+scanColumns+`
			 FROM goals
			 WHERE user_id = $1 AND deleted_at IS NULL
			 ORDER BY created_at DESC, id DESC
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

	var goals []*Goal
	for rows.Next() {
		g, err := r.scan(rows)
		if err != nil {
			return nil, syncedAt, err
		}
		goals = append(goals, g)
	}

	return goals, syncedAt, rows.Err()
}

func (r *Repository) Upsert(ctx context.Context, g *Goal) (*Goal, bool, error) {
	row := r.pool.QueryRow(
		ctx,
		`
		INSERT INTO goals (
			id,
			user_id,
			name,
			target_amount_cents,
			saved_amount_cents,
			target_date,
			created_at,
			updated_at,
			deleted_at
		)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
		ON CONFLICT (id) DO UPDATE SET
			name                = EXCLUDED.name,
			target_amount_cents = EXCLUDED.target_amount_cents,
			saved_amount_cents  = EXCLUDED.saved_amount_cents,
			target_date         = EXCLUDED.target_date,
			updated_at          = EXCLUDED.updated_at,
			deleted_at          = EXCLUDED.deleted_at
		WHERE goals.updated_at < EXCLUDED.updated_at
		RETURNING `+scanColumns,
		g.ID,
		g.UserID,
		g.Name,
		g.TargetAmountCents,
		g.SavedAmountCents,
		g.TargetDate,
		g.CreatedAt,
		g.UpdatedAt,
		g.DeletedAt,
	)

	result, err := r.scan(row)
	if err == nil {
		return result, false, nil
	}
	if err != pgx.ErrNoRows {
		return nil, false, err
	}

	current, err := r.GetByID(ctx, g.ID, g.UserID)
	if err != nil {
		return nil, false, err
	}

	return current, true, nil
}

func (r *Repository) SoftDelete(ctx context.Context, id, userID uuid.UUID, deletedAt time.Time) error {
	_, err := r.pool.Exec(
		ctx,
		`UPDATE goals SET deleted_at = $3, updated_at = $3
		 WHERE id = $1 AND user_id = $2
		   AND (deleted_at IS NULL OR updated_at < $3)`,
		id,
		userID,
		deletedAt,
	)
	return err
}
