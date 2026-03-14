package transaction

import (
	"context"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

type Transaction struct {
	ID          uuid.UUID
	UserID      uuid.UUID
	AccountID   uuid.UUID
	CategoryID  uuid.UUID
	Amount      int64 // minor units
	Description string
	Date        time.Time // only date component is meaningful (from PostgreSQL DATE)
	CreatedAt   time.Time
	UpdatedAt   time.Time
}

type Repository struct {
	pool *pgxpool.Pool
}

func NewRepository(pool *pgxpool.Pool) *Repository {
	return &Repository{pool: pool}
}

func (r *Repository) Create(ctx context.Context, userID, accountID, categoryID uuid.UUID, amount int64, description string, date time.Time) (*Transaction, error) {
	t := &Transaction{}
	err := r.pool.QueryRow(ctx, `
		INSERT INTO transactions (user_id, account_id, category_id, amount, description, date)
		VALUES ($1, $2, $3, $4, $5, $6)
		RETURNING id, user_id, account_id, category_id, amount, description, date, created_at, updated_at
	`, userID, accountID, categoryID, amount, description, date).Scan(
		&t.ID, &t.UserID, &t.AccountID, &t.CategoryID, &t.Amount, &t.Description, &t.Date, &t.CreatedAt, &t.UpdatedAt,
	)
	return t, err
}

func (r *Repository) GetByID(ctx context.Context, id, userID uuid.UUID) (*Transaction, error) {
	t := &Transaction{}
	err := r.pool.QueryRow(ctx, `
		SELECT id, user_id, account_id, category_id, amount, description, date, created_at, updated_at
		FROM transactions
		WHERE id = $1 AND user_id = $2 AND deleted_at IS NULL
	`, id, userID).Scan(
		&t.ID, &t.UserID, &t.AccountID, &t.CategoryID, &t.Amount, &t.Description, &t.Date, &t.CreatedAt, &t.UpdatedAt,
	)
	return t, err
}

type ListFilter struct {
	AccountID  string // UUID string, empty = no filter
	CategoryID string // UUID string, empty = no filter
	DateFrom   string // YYYY-MM-DD, empty = no filter
	DateTo     string // YYYY-MM-DD, empty = no filter
}

func (r *Repository) List(ctx context.Context, userID uuid.UUID, f ListFilter, limit, offset int) ([]*Transaction, int, error) {
	// Parametrized optional filters using NULL coalescing:
	// If the filter value is empty string, the condition is skipped.
	const baseWhere = `
		user_id = $1 AND deleted_at IS NULL
		AND ($2::uuid IS NULL OR account_id  = $2::uuid)
		AND ($3::uuid IS NULL OR category_id = $3::uuid)
		AND ($4::date IS NULL OR date >= $4::date)
		AND ($5::date IS NULL OR date <= $5::date)
	`
	nullIfEmpty := func(s string) interface{} {
		if s == "" {
			return nil
		}
		return s
	}

	var total int
	if err := r.pool.QueryRow(ctx,
		`SELECT COUNT(*) FROM transactions WHERE `+baseWhere,
		userID, nullIfEmpty(f.AccountID), nullIfEmpty(f.CategoryID),
		nullIfEmpty(f.DateFrom), nullIfEmpty(f.DateTo),
	).Scan(&total); err != nil {
		return nil, 0, err
	}

	rows, err := r.pool.Query(ctx, `
		SELECT id, user_id, account_id, category_id, amount, description, date, created_at, updated_at
		FROM transactions
		WHERE `+baseWhere+`
		ORDER BY date DESC, created_at DESC
		LIMIT $6 OFFSET $7
	`, userID, nullIfEmpty(f.AccountID), nullIfEmpty(f.CategoryID),
		nullIfEmpty(f.DateFrom), nullIfEmpty(f.DateTo), limit, offset)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()

	var txs []*Transaction
	for rows.Next() {
		t := &Transaction{}
		if err := rows.Scan(&t.ID, &t.UserID, &t.AccountID, &t.CategoryID, &t.Amount, &t.Description, &t.Date, &t.CreatedAt, &t.UpdatedAt); err != nil {
			return nil, 0, err
		}
		txs = append(txs, t)
	}
	return txs, total, rows.Err()
}

func (r *Repository) Update(ctx context.Context, id, userID uuid.UUID, accountID, categoryID uuid.UUID, amount int64, description, date string) (*Transaction, error) {
	t := &Transaction{}
	// Zero UUID (all zeros) is used as "not provided" sentinel for UUID fields.
	// For amount, 0 means "not provided". For strings, "" means "not provided".
	zeroUUID := uuid.UUID{}
	err := r.pool.QueryRow(ctx, `
		UPDATE transactions SET
			account_id  = CASE WHEN $3 != $7 THEN $3  ELSE account_id  END,
			category_id = CASE WHEN $4 != $7 THEN $4  ELSE category_id END,
			amount      = CASE WHEN $5 != 0  THEN $5  ELSE amount      END,
			description = CASE WHEN $6 != '' THEN $6  ELSE description END,
			date        = CASE WHEN $8 != '' THEN $8::date ELSE date   END
		WHERE id = $1 AND user_id = $2 AND deleted_at IS NULL
		RETURNING id, user_id, account_id, category_id, amount, description, date, created_at, updated_at
	`, id, userID, accountID, categoryID, amount, description, zeroUUID, date).Scan(
		&t.ID, &t.UserID, &t.AccountID, &t.CategoryID, &t.Amount, &t.Description, &t.Date, &t.CreatedAt, &t.UpdatedAt,
	)
	return t, err
}

func (r *Repository) Delete(ctx context.Context, id, userID uuid.UUID) error {
	result, err := r.pool.Exec(ctx, `
		UPDATE transactions SET deleted_at = NOW()
		WHERE id = $1 AND user_id = $2 AND deleted_at IS NULL
	`, id, userID)
	if err != nil {
		return err
	}
	if result.RowsAffected() == 0 {
		return pgx.ErrNoRows
	}
	return nil
}
