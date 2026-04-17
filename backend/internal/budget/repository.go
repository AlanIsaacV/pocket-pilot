package budget

import (
	"context"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/AlanIsaacV/pocket-pilot/internal/sync"
)

type Repository struct {
	pool   *pgxpool.Pool
	cursor *sync.CursorStore
}

func NewRepository(pool *pgxpool.Pool, cursor *sync.CursorStore) *Repository {
	return &Repository{pool: pool, cursor: cursor}
}

const scanColumns = `id, user_id, category_id, limit_amount_cents, currency_code, period, created_at, updated_at, deleted_at`

func (r *Repository) scan(row pgx.Row) (*Budget, error) {
	b := &Budget{}
	err := row.Scan(
		&b.ID,
		&b.UserID,
		&b.CategoryID,
		&b.LimitAmountCents,
		&b.CurrencyCode,
		&b.Period,
		&b.CreatedAt,
		&b.UpdatedAt,
		&b.DeletedAt,
	)
	if err != nil {
		return nil, err
	}
	return b, nil
}

func (r *Repository) GetByID(ctx context.Context, id, userID uuid.UUID) (*Budget, error) {
	row := r.pool.QueryRow(
		ctx,
		`SELECT `+scanColumns+` FROM budgets WHERE id = $1 AND user_id = $2`,
		id,
		userID,
	)
	return r.scan(row)
}

func (r *Repository) List(ctx context.Context, userID uuid.UUID, updatedSince *time.Time, limit, offset int) ([]*Budget, time.Time, error) {
	syncedAt := time.Now().UTC()

	var (
		rows pgx.Rows
		err  error
	)

	if updatedSince != nil {
		rows, err = r.pool.Query(
			ctx,
			`SELECT `+scanColumns+`
			 FROM budgets
			 WHERE user_id = $1 AND updated_at > $2
			 ORDER BY updated_at ASC, id ASC`,
			userID,
			updatedSince,
		)
	} else {
		rows, err = r.pool.Query(
			ctx,
			`SELECT `+scanColumns+`
			 FROM budgets
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

	var budgets []*Budget
	for rows.Next() {
		b, err := r.scan(rows)
		if err != nil {
			return nil, syncedAt, err
		}
		budgets = append(budgets, b)
	}

	return budgets, syncedAt, rows.Err()
}

func (r *Repository) Upsert(ctx context.Context, b *Budget) (*Budget, bool, error) {
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return nil, false, err
	}
	defer tx.Rollback(ctx)

	row := tx.QueryRow(
		ctx,
		`
		INSERT INTO budgets (
			id,
			user_id,
			category_id,
			limit_amount_cents,
			currency_code,
			period,
			created_at,
			updated_at,
			deleted_at
		)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
		ON CONFLICT (id) DO UPDATE SET
			category_id        = EXCLUDED.category_id,
			limit_amount_cents = EXCLUDED.limit_amount_cents,
			currency_code      = EXCLUDED.currency_code,
			period             = EXCLUDED.period,
			updated_at         = EXCLUDED.updated_at,
			deleted_at         = EXCLUDED.deleted_at
		WHERE budgets.updated_at < EXCLUDED.updated_at
		RETURNING `+scanColumns,
		b.ID,
		b.UserID,
		b.CategoryID,
		b.LimitAmountCents,
		b.CurrencyCode,
		b.Period,
		b.CreatedAt,
		b.UpdatedAt,
		b.DeletedAt,
	)

	result, err := r.scan(row)
	if err == nil {
		if err := r.cursor.Bump(ctx, tx, b.UserID, sync.EntityBudget, result.UpdatedAt); err != nil {
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

	current, err := r.GetByID(ctx, b.ID, b.UserID)
	if err != nil {
		return nil, false, err
	}

	return current, true, nil
}

func (r *Repository) SoftDelete(ctx context.Context, id, userID uuid.UUID, deletedAt time.Time) error {
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)

	tag, err := tx.Exec(
		ctx,
		`UPDATE budgets SET deleted_at = $3, updated_at = $3
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
		if err := r.cursor.Bump(ctx, tx, userID, sync.EntityBudget, deletedAt); err != nil {
			return err
		}
	}
	return tx.Commit(ctx)
}
