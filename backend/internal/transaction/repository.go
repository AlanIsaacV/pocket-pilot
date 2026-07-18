package transaction

import (
	"context"
	"errors"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/AlanIsaacV/pocket-pilot/internal/sync"
)

// Transaction mirrors the `transactions` table.
type Transaction struct {
	ID                  uuid.UUID
	UserID              uuid.UUID
	AccountID           uuid.UUID
	CategoryID          *uuid.UUID // nullable — transfers have no category
	LinkedTransactionID *uuid.UUID // pairs TRANSFER_OUT ↔ TRANSFER_IN
	TemplateID          *uuid.UUID // optional reference to transaction_templates
	YieldID             *uuid.UUID // optional reference to yield_configs
	HoldingID           *uuid.UUID // optional reference to investment_holdings
	LotID               *uuid.UUID // optional reference to investment_lots
	Type                string     // "income" | "expense" | "transfer_out" | "transfer_in"
	AmountCents         int64
	InstallmentsCount   int32
	CurrencyCode        string
	Status              string
	Source              string // "manual" | "auto_notification" | future provenance values
	Tags                []string
	Description         string
	Nature              string    // "required" | "obligation" | "lifestyle" | "active" | "passive" | "windfall" | "investment" | ""
	Date                time.Time // only the date component is meaningful (PostgreSQL DATE)
	CreatedAt           time.Time
	UpdatedAt           time.Time
	DeletedAt           *time.Time
}

type Repository struct {
	pool   *pgxpool.Pool
	cursor *sync.CursorStore
}

func NewRepository(pool *pgxpool.Pool, cursor *sync.CursorStore) *Repository {
	return &Repository{pool: pool, cursor: cursor}
}

const scanColumns = `id, user_id, account_id, category_id, linked_transaction_id, template_id, yield_id, holding_id, lot_id, type, amount_cents, installments_count, currency_code, status, source, tags, description, nature, date, created_at, updated_at, deleted_at`

var (
	ErrTemplateReferenceNotFound       = errors.New("template reference does not exist for user")
	ErrTemplateReferenceDateNotAllowed = errors.New("template is deleted and cannot be used for this transaction date")
)

func dateOnlyUTC(t time.Time) time.Time {
	year, month, day := t.UTC().Date()
	return time.Date(year, month, day, 0, 0, 0, 0, time.UTC)
}

func (r *Repository) scan(row pgx.Row) (*Transaction, error) {
	t := &Transaction{}
	err := row.Scan(
		&t.ID, &t.UserID, &t.AccountID, &t.CategoryID, &t.LinkedTransactionID,
		&t.TemplateID,
		&t.YieldID,
		&t.HoldingID,
		&t.LotID,
		&t.Type, &t.AmountCents, &t.InstallmentsCount, &t.CurrencyCode, &t.Status, &t.Source,
		&t.Tags, &t.Description, &t.Nature, &t.Date,
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
		t, err := r.scan(rows)
		if err != nil {
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
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return nil, false, err
	}
	defer tx.Rollback(ctx)

	row := tx.QueryRow(ctx, `
		INSERT INTO transactions (id, user_id, account_id, category_id, linked_transaction_id, template_id, yield_id, holding_id, lot_id, type, amount_cents, installments_count, currency_code, status, source, tags, description, nature, date, created_at, updated_at)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17, $18, $19, $20, $21)
		ON CONFLICT (id) DO UPDATE SET
			account_id              = EXCLUDED.account_id,
			category_id             = EXCLUDED.category_id,
			linked_transaction_id   = EXCLUDED.linked_transaction_id,
			template_id             = EXCLUDED.template_id,
			yield_id                = EXCLUDED.yield_id,
			holding_id              = EXCLUDED.holding_id,
			lot_id                  = EXCLUDED.lot_id,
			type                    = EXCLUDED.type,
			amount_cents            = EXCLUDED.amount_cents,
			installments_count      = EXCLUDED.installments_count,
			currency_code           = EXCLUDED.currency_code,
			status                  = EXCLUDED.status,
			source                  = EXCLUDED.source,
			tags                    = EXCLUDED.tags,
			description             = EXCLUDED.description,
			nature                  = EXCLUDED.nature,
			date                    = EXCLUDED.date,
			updated_at              = EXCLUDED.updated_at
		WHERE transactions.updated_at < EXCLUDED.updated_at
		RETURNING `+scanColumns,
		t.ID, t.UserID, t.AccountID, t.CategoryID, t.LinkedTransactionID,
		t.TemplateID,
		t.YieldID,
		t.HoldingID,
		t.LotID,
		t.Type, t.AmountCents, t.InstallmentsCount, t.CurrencyCode, t.Status, t.Source,
		t.Tags, t.Description, t.Nature, t.Date,
		t.CreatedAt, t.UpdatedAt,
	)

	result, err := r.scan(row)
	if err == nil {
		if err := r.cursor.Bump(ctx, tx, t.UserID, sync.EntityTransaction, result.UpdatedAt); err != nil {
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

	// LWW rejected the client's version — return the server's without bumping.
	current, err := r.GetByID(ctx, t.ID, t.UserID)
	if err != nil {
		return nil, false, err
	}
	return current, true, nil
}

// SoftDelete sets deleted_at on a transaction, applying LWW by comparing timestamps.
// When the transaction has a linked_transaction_id (transfer pair), both legs are
// soft-deleted in the same database transaction for consistency.
func (r *Repository) SoftDelete(ctx context.Context, id, userID uuid.UUID, deletedAt time.Time) error {
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)

	// Soft-delete the primary transaction and retrieve its linked ID.
	var linkedID *uuid.UUID
	err = tx.QueryRow(ctx, `
		UPDATE transactions SET deleted_at = $3, updated_at = $3
		WHERE id = $1 AND user_id = $2
		  AND (deleted_at IS NULL OR updated_at < $3)
		RETURNING linked_transaction_id
	`, id, userID, deletedAt).Scan(&linkedID)

	if err != nil && err != pgx.ErrNoRows {
		return err
	}

	// Cascade to the linked transfer leg if present.
	if linkedID != nil {
		_, err = tx.Exec(ctx, `
			UPDATE transactions SET deleted_at = $3, updated_at = $3
			WHERE id = $1 AND user_id = $2
			  AND (deleted_at IS NULL OR updated_at < $3)
		`, *linkedID, userID, deletedAt)
		if err != nil {
			return err
		}
	}

	// Bump cursor within the same tx. The CursorStore's LWW guard prevents
	// regression if deletedAt happened to be older than the stored cursor.
	if err := r.cursor.Bump(ctx, tx, userID, sync.EntityTransaction, deletedAt); err != nil {
		return err
	}

	return tx.Commit(ctx)
}
