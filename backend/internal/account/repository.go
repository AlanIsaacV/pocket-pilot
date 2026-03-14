package account

import (
	"context"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// Account is the internal domain model. It lives in this package and is
// independent of the proto-generated types — the handler converts between them.
type Account struct {
	ID             uuid.UUID
	UserID         uuid.UUID
	Name           string
	Type           string // "checking", "savings", "credit_card", "cash", "investment"
	InitialBalance int64  // in minor units (e.g., cents)
	CreatedAt      time.Time
	UpdatedAt      time.Time
}

type Repository struct {
	pool *pgxpool.Pool
}

func NewRepository(pool *pgxpool.Pool) *Repository {
	return &Repository{pool: pool}
}

func (r *Repository) Create(ctx context.Context, userID uuid.UUID, name, typ string, balance int64) (*Account, error) {
	a := &Account{}
	err := r.pool.QueryRow(ctx, `
		INSERT INTO accounts (user_id, name, type, initial_balance)
		VALUES ($1, $2, $3, $4)
		RETURNING id, user_id, name, type, initial_balance, created_at, updated_at
	`, userID, name, typ, balance).Scan(
		&a.ID, &a.UserID, &a.Name, &a.Type, &a.InitialBalance, &a.CreatedAt, &a.UpdatedAt,
	)
	return a, err
}

func (r *Repository) GetByID(ctx context.Context, id, userID uuid.UUID) (*Account, error) {
	a := &Account{}
	err := r.pool.QueryRow(ctx, `
		SELECT id, user_id, name, type, initial_balance, created_at, updated_at
		FROM accounts
		WHERE id = $1 AND user_id = $2 AND deleted_at IS NULL
	`, id, userID).Scan(
		&a.ID, &a.UserID, &a.Name, &a.Type, &a.InitialBalance, &a.CreatedAt, &a.UpdatedAt,
	)
	return a, err
}

func (r *Repository) List(ctx context.Context, userID uuid.UUID, limit, offset int) ([]*Account, int, error) {
	var total int
	if err := r.pool.QueryRow(ctx,
		`SELECT COUNT(*) FROM accounts WHERE user_id = $1 AND deleted_at IS NULL`,
		userID,
	).Scan(&total); err != nil {
		return nil, 0, err
	}

	rows, err := r.pool.Query(ctx, `
		SELECT id, user_id, name, type, initial_balance, created_at, updated_at
		FROM accounts
		WHERE user_id = $1 AND deleted_at IS NULL
		ORDER BY created_at DESC
		LIMIT $2 OFFSET $3
	`, userID, limit, offset)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()

	var accounts []*Account
	for rows.Next() {
		a := &Account{}
		if err := rows.Scan(&a.ID, &a.UserID, &a.Name, &a.Type, &a.InitialBalance, &a.CreatedAt, &a.UpdatedAt); err != nil {
			return nil, 0, err
		}
		accounts = append(accounts, a)
	}
	return accounts, total, rows.Err()
}

func (r *Repository) Update(ctx context.Context, id, userID uuid.UUID, name, typ string, balance int64) (*Account, error) {
	a := &Account{}
	// CASE WHEN pattern: only apply the field if a non-zero value was provided.
	// This lets the client do partial updates without a separate "fetch first" query.
	err := r.pool.QueryRow(ctx, `
		UPDATE accounts SET
			name            = CASE WHEN $3 != '' THEN $3 ELSE name END,
			type            = CASE WHEN $4 != '' THEN $4 ELSE type END,
			initial_balance = CASE WHEN $5 != 0  THEN $5 ELSE initial_balance END
		WHERE id = $1 AND user_id = $2 AND deleted_at IS NULL
		RETURNING id, user_id, name, type, initial_balance, created_at, updated_at
	`, id, userID, name, typ, balance).Scan(
		&a.ID, &a.UserID, &a.Name, &a.Type, &a.InitialBalance, &a.CreatedAt, &a.UpdatedAt,
	)
	return a, err
}

func (r *Repository) Delete(ctx context.Context, id, userID uuid.UUID) error {
	result, err := r.pool.Exec(ctx, `
		UPDATE accounts SET deleted_at = NOW()
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
