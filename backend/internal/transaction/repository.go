package transaction

import (
	"context"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// Transaction mirrors the `transactions` table.
type Transaction struct {
	ID           uuid.UUID
	UserID       uuid.UUID
	AccountID    uuid.UUID
	CategoryID   uuid.UUID
	Type         string // "income" | "expense" | "transfer"
	AmountCents  int64
	CurrencyCode string
	Status       string
	Tags         []string
	Description  string
	Date         time.Time  // only the date component is meaningful (PostgreSQL DATE)
	CreatedAt    time.Time
	UpdatedAt    time.Time
	DeletedAt    *time.Time
}

type Repository struct {
	pool *pgxpool.Pool
}

func NewRepository(pool *pgxpool.Pool) *Repository {
	return &Repository{pool: pool}
}

const scanColumns = `id, user_id, account_id, category_id, type, amount_cents, currency_code, status, tags, description, date, created_at, updated_at, deleted_at`

func (r *Repository) scan(row pgx.Row) (*Transaction, error) {
	t := &Transaction{}
	err := row.Scan(
		&t.ID, &t.UserID, &t.AccountID, &t.CategoryID,
		&t.Type, &t.AmountCents, &t.CurrencyCode, &t.Status,
		&t.Tags, &t.Description, &t.Date,
		&t.CreatedAt, &t.UpdatedAt, &t.DeletedAt,
	)
	if err != nil {
		return nil, err
	}
	return t, nil
}

// GetByID fetches a single transaction regardless of deleted_at status.
// Used to return the server's current version after a LWW conflict.
func (r *Repository) GetByID(ctx context.Context, id, userID uuid.UUID) (*Transaction, error) {
	row := r.pool.QueryRow(ctx,
		`SELECT `+scanColumns+` FROM transactions WHERE id = $1 AND user_id = $2`,
		id, userID,
	)
	return r.scan(row)
}

// List returns transactions for a user.
//
// If updatedSince is non-nil → delta sync: returns all records (active AND deleted)
// with updated_at > updatedSince, no LIMIT applied.
//
// If updatedSince is nil → full sync: returns only active records with pagination.
func (r *Repository) List(ctx context.Context, userID uuid.UUID, updatedSince *time.Time, limit, offset int) ([]*Transaction, time.Time, error) {
	syncedAt := time.Now().UTC()

	var (
		rows pgx.Rows
		err  error
	)

	if updatedSince != nil {
		rows, err = r.pool.Query(ctx,
			`SELECT `+scanColumns+`
			 FROM transactions
			 WHERE user_id = $1 AND updated_at > $2
			 ORDER BY updated_at ASC`,
			userID, updatedSince,
		)
	} else {
		rows, err = r.pool.Query(ctx,
			`SELECT `+scanColumns+`
			 FROM transactions
			 WHERE user_id = $1 AND deleted_at IS NULL
			 ORDER BY date DESC, created_at DESC
			 LIMIT $2 OFFSET $3`,
			userID, limit, offset,
		)
	}
	if err != nil {
		return nil, syncedAt, err
	}
	defer rows.Close()

	var txs []*Transaction
	for rows.Next() {
		t := &Transaction{}
		if err := rows.Scan(
			&t.ID, &t.UserID, &t.AccountID, &t.CategoryID,
			&t.Type, &t.AmountCents, &t.CurrencyCode, &t.Status,
			&t.Tags, &t.Description, &t.Date,
			&t.CreatedAt, &t.UpdatedAt, &t.DeletedAt,
		); err != nil {
			return nil, syncedAt, err
		}
		txs = append(txs, t)
	}
	return txs, syncedAt, rows.Err()
}

// Upsert inserts or updates a transaction applying Last Write Wins.
//
// Returns (transaction, conflictResolved, error):
//   - conflictResolved=false: incoming version was accepted.
//   - conflictResolved=true:  server had a newer version; returned transaction is the server's.
func (r *Repository) Upsert(ctx context.Context, t *Transaction) (*Transaction, bool, error) {
	row := r.pool.QueryRow(ctx, `
		INSERT INTO transactions (id, user_id, account_id, category_id, type, amount_cents, currency_code, status, tags, description, date, created_at, updated_at)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13)
		ON CONFLICT (id) DO UPDATE SET
			account_id    = EXCLUDED.account_id,
			category_id   = EXCLUDED.category_id,
			type          = EXCLUDED.type,
			amount_cents  = EXCLUDED.amount_cents,
			currency_code = EXCLUDED.currency_code,
			status        = EXCLUDED.status,
			tags          = EXCLUDED.tags,
			description   = EXCLUDED.description,
			date          = EXCLUDED.date,
			updated_at    = EXCLUDED.updated_at
		WHERE transactions.updated_at < EXCLUDED.updated_at
		RETURNING `+scanColumns,
		t.ID, t.UserID, t.AccountID, t.CategoryID,
		t.Type, t.AmountCents, t.CurrencyCode, t.Status,
		t.Tags, t.Description, t.Date,
		t.CreatedAt, t.UpdatedAt,
	)

	result, err := r.scan(row)
	if err == nil {
		return result, false, nil
	}
	if err != pgx.ErrNoRows {
		return nil, false, err
	}

	// ErrNoRows: server has a newer version. Return it with conflict_resolved=true.
	current, err := r.GetByID(ctx, t.ID, t.UserID)
	if err != nil {
		return nil, false, err
	}
	return current, true, nil
}

// SoftDelete sets deleted_at on a transaction, applying LWW by comparing timestamps.
func (r *Repository) SoftDelete(ctx context.Context, id, userID uuid.UUID, deletedAt time.Time) error {
	_, err := r.pool.Exec(ctx, `
		UPDATE transactions SET deleted_at = $3, updated_at = $3
		WHERE id = $1 AND user_id = $2
		  AND (deleted_at IS NULL OR updated_at < $3)
	`, id, userID, deletedAt)
	return err
}
