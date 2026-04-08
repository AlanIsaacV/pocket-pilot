package transactiontemplate

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

const scanColumns = `id, user_id, name, account_id, to_account_id, category_id, type, amount_cents, currency_code, tags, description, frequency, next_date, end_date, created_at, updated_at, deleted_at, is_auto_charge, is_active`

func (r *Repository) scan(row pgx.Row) (*Template, error) {
	t := &Template{}
	err := row.Scan(
		&t.ID, &t.UserID, &t.Name, &t.AccountID,
		&t.ToAccountID, &t.CategoryID, &t.Type, &t.AmountCents,
		&t.CurrencyCode, &t.Tags, &t.Description,
		&t.Frequency, &t.NextDate, &t.EndDate,
		&t.CreatedAt, &t.UpdatedAt, &t.DeletedAt,
		&t.IsAutoCharge, &t.IsActive,
	)
	if err != nil {
		return nil, err
	}
	return t, nil
}

func (r *Repository) GetByID(ctx context.Context, id, userID uuid.UUID) (*Template, error) {
	row := r.pool.QueryRow(ctx,
		`SELECT `+scanColumns+` FROM transaction_templates WHERE id = $1 AND user_id = $2`,
		id, userID,
	)
	return r.scan(row)
}

func (r *Repository) List(ctx context.Context, userID uuid.UUID, updatedSince *time.Time, limit, offset int) ([]*Template, time.Time, error) {
	syncedAt := time.Now().UTC()

	var (
		rows pgx.Rows
		err  error
	)

	if updatedSince != nil {
		rows, err = r.pool.Query(ctx,
			`SELECT `+scanColumns+`
			 FROM transaction_templates
			 WHERE user_id = $1 AND updated_at > $2
			 ORDER BY updated_at ASC`,
			userID, updatedSince,
		)
	} else {
		rows, err = r.pool.Query(ctx,
			`SELECT `+scanColumns+`
			 FROM transaction_templates
			 WHERE user_id = $1 AND deleted_at IS NULL
			 ORDER BY created_at DESC
			 LIMIT $2 OFFSET $3`,
			userID, limit, offset,
		)
	}
	if err != nil {
		return nil, syncedAt, err
	}
	defer rows.Close()

	var templates []*Template
	for rows.Next() {
		t, err := r.scan(rows)
		if err != nil {
			return nil, syncedAt, err
		}
		templates = append(templates, t)
	}

	return templates, syncedAt, rows.Err()
}

func (r *Repository) Upsert(ctx context.Context, t *Template) (*Template, bool, error) {
	row := r.pool.QueryRow(ctx, `
		INSERT INTO transaction_templates (id, user_id, name, account_id, to_account_id, category_id, type, amount_cents, currency_code, tags, description, frequency, next_date, end_date, created_at, updated_at, is_auto_charge, is_active)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17, $18)
		ON CONFLICT (id) DO UPDATE SET
			name           = EXCLUDED.name,
			account_id     = EXCLUDED.account_id,
			to_account_id  = EXCLUDED.to_account_id,
			category_id    = EXCLUDED.category_id,
			type           = EXCLUDED.type,
			amount_cents   = EXCLUDED.amount_cents,
			currency_code  = EXCLUDED.currency_code,
			tags           = EXCLUDED.tags,
			description    = EXCLUDED.description,
			frequency      = EXCLUDED.frequency,
			next_date      = EXCLUDED.next_date,
			end_date       = EXCLUDED.end_date,
			is_auto_charge = EXCLUDED.is_auto_charge,
			is_active      = EXCLUDED.is_active,
			updated_at     = EXCLUDED.updated_at
		WHERE transaction_templates.updated_at < EXCLUDED.updated_at
		RETURNING `+scanColumns,
		t.ID, t.UserID, t.Name, t.AccountID,
		t.ToAccountID, t.CategoryID, t.Type, t.AmountCents,
		t.CurrencyCode, t.Tags, t.Description,
		t.Frequency, t.NextDate, t.EndDate,
		t.CreatedAt, t.UpdatedAt,
		t.IsAutoCharge, t.IsActive,
	)

	result, err := r.scan(row)
	if err == nil {
		return result, false, nil
	}
	if err != pgx.ErrNoRows {
		return nil, false, err
	}

	current, err := r.GetByID(ctx, t.ID, t.UserID)
	if err != nil {
		return nil, false, err
	}
	return current, true, nil
}

func (r *Repository) SoftDelete(ctx context.Context, id, userID uuid.UUID, deletedAt time.Time) error {
	_, err := r.pool.Exec(ctx, `
		UPDATE transaction_templates SET deleted_at = $3, updated_at = $3
		WHERE id = $1 AND user_id = $2
		  AND (deleted_at IS NULL OR updated_at < $3)
	`, id, userID, deletedAt)
	return err
}
