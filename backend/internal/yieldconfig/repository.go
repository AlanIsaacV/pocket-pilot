package yieldconfig

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

const scanColumns = `id, user_id, account_id, name, amount_cents, apy_rate, payout_frequency, next_date, maturity_date, term_days, auto_renew, status, created_at, updated_at, deleted_at`

func (r *Repository) scan(row pgx.Row) (*YieldConfig, error) {
	cfg := &YieldConfig{}
	err := row.Scan(
		&cfg.ID,
		&cfg.UserID,
		&cfg.AccountID,
		&cfg.Name,
		&cfg.AmountCents,
		&cfg.ApyRate,
		&cfg.PayoutFrequency,
		&cfg.NextDate,
		&cfg.MaturityDate,
		&cfg.TermDays,
		&cfg.AutoRenew,
		&cfg.Status,
		&cfg.CreatedAt,
		&cfg.UpdatedAt,
		&cfg.DeletedAt,
	)
	if err != nil {
		return nil, err
	}
	return cfg, nil
}

func (r *Repository) GetByID(ctx context.Context, id, userID uuid.UUID) (*YieldConfig, error) {
	row := r.pool.QueryRow(
		ctx,
		`SELECT `+scanColumns+` FROM yield_configs WHERE id = $1 AND user_id = $2`,
		id,
		userID,
	)
	return r.scan(row)
}

func (r *Repository) List(ctx context.Context, userID uuid.UUID, updatedSince *time.Time, limit, offset int) ([]*YieldConfig, time.Time, error) {
	syncedAt := time.Now().UTC()

	var (
		rows pgx.Rows
		err  error
	)

	if updatedSince != nil {
		rows, err = r.pool.Query(
			ctx,
			`SELECT `+scanColumns+`
			 FROM yield_configs
			 WHERE user_id = $1 AND updated_at > $2
			 ORDER BY updated_at ASC`,
			userID,
			updatedSince,
		)
	} else {
		rows, err = r.pool.Query(
			ctx,
			`SELECT `+scanColumns+`
			 FROM yield_configs
			 WHERE user_id = $1 AND deleted_at IS NULL
			 ORDER BY created_at DESC
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

	var items []*YieldConfig
	for rows.Next() {
		cfg := &YieldConfig{}
		if err := rows.Scan(
			&cfg.ID,
			&cfg.UserID,
			&cfg.AccountID,
			&cfg.Name,
			&cfg.AmountCents,
			&cfg.ApyRate,
			&cfg.PayoutFrequency,
			&cfg.NextDate,
			&cfg.MaturityDate,
			&cfg.TermDays,
			&cfg.AutoRenew,
			&cfg.Status,
			&cfg.CreatedAt,
			&cfg.UpdatedAt,
			&cfg.DeletedAt,
		); err != nil {
			return nil, syncedAt, err
		}
		items = append(items, cfg)
	}

	return items, syncedAt, rows.Err()
}

func (r *Repository) Upsert(ctx context.Context, cfg *YieldConfig) (*YieldConfig, bool, error) {
	row := r.pool.QueryRow(
		ctx,
		`
		INSERT INTO yield_configs (
			id,
			user_id,
			account_id,
			name,
			amount_cents,
			apy_rate,
			payout_frequency,
			next_date,
			maturity_date,
			term_days,
			auto_renew,
			status,
			created_at,
			updated_at
		)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14)
		ON CONFLICT (id) DO UPDATE SET
			account_id       = EXCLUDED.account_id,
			name             = EXCLUDED.name,
			amount_cents     = EXCLUDED.amount_cents,
			apy_rate         = EXCLUDED.apy_rate,
			payout_frequency = EXCLUDED.payout_frequency,
			next_date        = EXCLUDED.next_date,
			maturity_date    = EXCLUDED.maturity_date,
			term_days        = EXCLUDED.term_days,
			auto_renew       = EXCLUDED.auto_renew,
			status           = EXCLUDED.status,
			updated_at       = EXCLUDED.updated_at
		WHERE yield_configs.updated_at < EXCLUDED.updated_at
		RETURNING `+scanColumns,
		cfg.ID,
		cfg.UserID,
		cfg.AccountID,
		cfg.Name,
		cfg.AmountCents,
		cfg.ApyRate,
		cfg.PayoutFrequency,
		cfg.NextDate,
		cfg.MaturityDate,
		cfg.TermDays,
		cfg.AutoRenew,
		cfg.Status,
		cfg.CreatedAt,
		cfg.UpdatedAt,
	)

	result, err := r.scan(row)
	if err == nil {
		return result, false, nil
	}
	if err != pgx.ErrNoRows {
		return nil, false, err
	}

	current, err := r.GetByID(ctx, cfg.ID, cfg.UserID)
	if err != nil {
		return nil, false, err
	}

	return current, true, nil
}

func (r *Repository) SoftDelete(ctx context.Context, id, userID uuid.UUID, deletedAt time.Time) error {
	_, err := r.pool.Exec(
		ctx,
		`UPDATE yield_configs SET deleted_at = $3, updated_at = $3
		 WHERE id = $1 AND user_id = $2
		   AND (deleted_at IS NULL OR updated_at < $3)`,
		id,
		userID,
		deletedAt,
	)
	return err
}
