package account

import (
	"context"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// Account is the internal domain model.
// It mirrors the `accounts` table columns; the handler converts to/from proto.
type Account struct {
	ID               uuid.UUID
	UserID           uuid.UUID
	Name             string
	Type             string // matches account_type enum: 'bank', 'cash', 'credit_card', 'loan', 'investment', 'crypto', 'other'
	CurrencyCode     string
	CreditLimitCents *int64
	StatementDay     *int32
	PaymentDueDay    *int32
	InterestRateApr  *float64 // stored as NUMERIC(5,2) in PostgreSQL
	TermMonths       *int32
	CreatedAt        time.Time
	UpdatedAt        time.Time
	DeletedAt        *time.Time
}

type Repository struct {
	pool *pgxpool.Pool
}

func NewRepository(pool *pgxpool.Pool) *Repository {
	return &Repository{pool: pool}
}

func (r *Repository) scan(row pgx.Row) (*Account, error) {
	a := &Account{}
	err := row.Scan(
		&a.ID, &a.UserID, &a.Name, &a.Type, &a.CurrencyCode,
		&a.CreditLimitCents, &a.StatementDay, &a.PaymentDueDay,
		&a.InterestRateApr, &a.TermMonths,
		&a.CreatedAt, &a.UpdatedAt, &a.DeletedAt,
	)
	if err != nil {
		return nil, err
	}
	return a, nil
}

// GetByID fetches a single account regardless of its deleted_at status.
// Used to return the server's current version after a LWW conflict.
func (r *Repository) GetByID(ctx context.Context, id, userID uuid.UUID) (*Account, error) {
	row := r.pool.QueryRow(ctx,
		`SELECT id, user_id, name, type, currency_code, credit_limit_cents,
			statement_day, payment_due_day, interest_rate_apr,
			term_months, created_at, updated_at, deleted_at
		FROM accounts WHERE id = $1 AND user_id = $2`,
		id, userID,
	)
	return r.scan(row)
}

// List returns accounts for a user.
//
// If updatedSince is non-nil → delta sync: returns all records (active AND deleted)
// with updated_at > updatedSince, no LIMIT applied (pagination not required for deltas).
//
// If updatedSince is nil → full sync: returns only active records with pagination.
// The caller should still pass page parameters.
func (r *Repository) List(ctx context.Context, userID uuid.UUID, updatedSince *time.Time, limit, offset int) ([]*Account, time.Time, error) {
	// Capture the server's current time before querying — this becomes synced_at.
	syncedAt := time.Now().UTC()

	var (
		rows pgx.Rows
		err  error
	)

	if updatedSince != nil {
		// Delta sync: return changed records since the cursor (including deletions).
		rows, err = r.pool.Query(ctx,
			`SELECT id, user_id, name, type, currency_code, credit_limit_cents,
				statement_day, payment_due_day, interest_rate_apr,
				term_months, created_at, updated_at, deleted_at
			 FROM accounts
			 WHERE user_id = $1 AND updated_at > $2
			 ORDER BY updated_at ASC`,
			userID, updatedSince,
		)
	} else {
		// Full sync: return all records (active + archived) with pagination.
		rows, err = r.pool.Query(ctx,
			`SELECT id, user_id, name, type, currency_code, credit_limit_cents,
				statement_day, payment_due_day, interest_rate_apr,
				term_months, created_at, updated_at, deleted_at
			 FROM accounts
			 WHERE user_id = $1
			 ORDER BY created_at DESC
			 LIMIT $2 OFFSET $3`,
			userID, limit, offset,
		)
	}
	if err != nil {
		return nil, syncedAt, err
	}
	defer rows.Close()

	var accounts []*Account
	for rows.Next() {
		a := &Account{}
		if err := rows.Scan(
			&a.ID, &a.UserID, &a.Name, &a.Type, &a.CurrencyCode,
			&a.CreditLimitCents, &a.StatementDay, &a.PaymentDueDay,
			&a.InterestRateApr, &a.TermMonths,
			&a.CreatedAt, &a.UpdatedAt, &a.DeletedAt,
		); err != nil {
			return nil, syncedAt, err
		}
		accounts = append(accounts, a)
	}
	return accounts, syncedAt, rows.Err()
}

// Upsert inserts a new account or updates an existing one applying Last Write Wins:
// the update only applies if the incoming updated_at is more recent than the stored one.
//
// Returns (account, conflictResolved, error):
//   - conflictResolved=false: the incoming version was accepted (insert or LWW update).
//   - conflictResolved=true:  the server had a newer version; returned account is the server's.
func (r *Repository) Upsert(ctx context.Context, a *Account) (*Account, bool, error) {
	row := r.pool.QueryRow(ctx, `
		INSERT INTO accounts (id, user_id, name, type, currency_code, credit_limit_cents, statement_day, payment_due_day, interest_rate_apr, term_months, created_at, updated_at, deleted_at)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13)
		ON CONFLICT (id) DO UPDATE SET
			name              = EXCLUDED.name,
			type              = EXCLUDED.type,
			currency_code     = EXCLUDED.currency_code,
			credit_limit_cents = EXCLUDED.credit_limit_cents,
			statement_day     = EXCLUDED.statement_day,
			payment_due_day   = EXCLUDED.payment_due_day,
			interest_rate_apr = EXCLUDED.interest_rate_apr,
			term_months       = EXCLUDED.term_months,
			updated_at        = EXCLUDED.updated_at,
			deleted_at        = EXCLUDED.deleted_at
		WHERE accounts.updated_at < EXCLUDED.updated_at
		RETURNING id, user_id, name, type, currency_code, credit_limit_cents,
			statement_day, payment_due_day, interest_rate_apr,
			term_months, created_at, updated_at, deleted_at`,
		a.ID, a.UserID, a.Name, a.Type,
		a.CurrencyCode,
		a.CreditLimitCents, a.StatementDay, a.PaymentDueDay,
		a.InterestRateApr, a.TermMonths,
		a.CreatedAt, a.UpdatedAt, a.DeletedAt,
	)

	result, err := r.scan(row)
	if err == nil {
		// Insert or update succeeded — client's version was accepted.
		return result, false, nil
	}
	if err != pgx.ErrNoRows {
		return nil, false, err
	}

	// ErrNoRows means the WHERE updated_at < EXCLUDED.updated_at was false:
	// the server has a newer version. Fetch and return it with conflict_resolved=true.
	current, err := r.GetByID(ctx, a.ID, a.UserID)
	if err != nil {
		return nil, false, err
	}
	return current, true, nil
}

// SoftDelete sets deleted_at on an account, applying LWW by comparing timestamps.
// If the server's updated_at is newer than the requested deleted_at, the delete is silently
// ignored (the server's version wins and the client will receive it on the next delta pull).
func (r *Repository) SoftDelete(ctx context.Context, id, userID uuid.UUID, deletedAt time.Time) error {
	_, err := r.pool.Exec(ctx, `
		UPDATE accounts SET deleted_at = $3, updated_at = $3
		WHERE id = $1 AND user_id = $2
		  AND (deleted_at IS NULL OR updated_at < $3)
	`, id, userID, deletedAt)
	return err
}
