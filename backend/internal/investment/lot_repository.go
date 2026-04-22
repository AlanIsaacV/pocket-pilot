package investment

import (
	"context"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/AlanIsaacV/pocket-pilot/internal/sync"
)

type LotRepository struct {
	pool   *pgxpool.Pool
	cursor *sync.CursorStore
}

func NewLotRepository(pool *pgxpool.Pool, cursor *sync.CursorStore) *LotRepository {
	return &LotRepository{pool: pool, cursor: cursor}
}

const lotScanColumns = `id, user_id, holding_id, account_id, kind, quantity, price, fee_cents, fx_rate, occurred_at, validity, notes, created_at, updated_at, deleted_at`

func scanLot(row pgx.Row) (*Lot, error) {
	l := &Lot{}
	err := row.Scan(
		&l.ID,
		&l.UserID,
		&l.HoldingID,
		&l.AccountID,
		&l.Kind,
		&l.Quantity,
		&l.Price,
		&l.FeeCents,
		&l.FxRate,
		&l.OccurredAt,
		&l.Validity,
		&l.Notes,
		&l.CreatedAt,
		&l.UpdatedAt,
		&l.DeletedAt,
	)
	if err != nil {
		return nil, err
	}
	return l, nil
}

func (r *LotRepository) GetByID(ctx context.Context, id, userID uuid.UUID) (*Lot, error) {
	row := r.pool.QueryRow(
		ctx,
		`SELECT `+lotScanColumns+` FROM investment_lots WHERE id = $1 AND user_id = $2`,
		id,
		userID,
	)
	return scanLot(row)
}

func (r *LotRepository) List(ctx context.Context, userID uuid.UUID, updatedSince *time.Time, limit, offset int) ([]*Lot, time.Time, error) {
	syncedAt := time.Now().UTC()

	var (
		rows pgx.Rows
		err  error
	)

	if updatedSince != nil {
		rows, err = r.pool.Query(
			ctx,
			`SELECT `+lotScanColumns+`
			 FROM investment_lots
			 WHERE user_id = $1 AND updated_at > $2
			 ORDER BY updated_at ASC`,
			userID,
			updatedSince,
		)
	} else {
		rows, err = r.pool.Query(
			ctx,
			`SELECT `+lotScanColumns+`
			 FROM investment_lots
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

	var items []*Lot
	for rows.Next() {
		l, err := scanLot(rows)
		if err != nil {
			return nil, syncedAt, err
		}
		items = append(items, l)
	}
	return items, syncedAt, rows.Err()
}

func (r *LotRepository) Upsert(ctx context.Context, l *Lot) (*Lot, bool, error) {
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return nil, false, err
	}
	defer tx.Rollback(ctx)

	row := tx.QueryRow(
		ctx,
		`
		INSERT INTO investment_lots (
			id, user_id, holding_id, account_id, kind, quantity, price, fee_cents,
			fx_rate, occurred_at, validity, notes, created_at, updated_at
		)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14)
		ON CONFLICT (id) DO UPDATE SET
			holding_id  = EXCLUDED.holding_id,
			account_id  = EXCLUDED.account_id,
			kind        = EXCLUDED.kind,
			quantity    = EXCLUDED.quantity,
			price       = EXCLUDED.price,
			fee_cents   = EXCLUDED.fee_cents,
			fx_rate     = EXCLUDED.fx_rate,
			occurred_at = EXCLUDED.occurred_at,
			validity    = EXCLUDED.validity,
			notes       = EXCLUDED.notes,
			updated_at  = EXCLUDED.updated_at
		WHERE investment_lots.updated_at < EXCLUDED.updated_at
		RETURNING `+lotScanColumns,
		l.ID,
		l.UserID,
		l.HoldingID,
		l.AccountID,
		normalizeLower(l.Kind),
		l.Quantity,
		l.Price,
		l.FeeCents,
		l.FxRate,
		l.OccurredAt,
		normalizeLower(l.Validity),
		l.Notes,
		l.CreatedAt,
		l.UpdatedAt,
	)

	result, err := scanLot(row)
	if err == nil {
		if err := r.cursor.Bump(ctx, tx, l.UserID, sync.EntityInvestmentLot, result.UpdatedAt); err != nil {
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

	current, err := r.GetByID(ctx, l.ID, l.UserID)
	if err != nil {
		return nil, false, err
	}
	return current, true, nil
}

func (r *LotRepository) SoftDelete(ctx context.Context, id, userID uuid.UUID, deletedAt time.Time) error {
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)

	tag, err := tx.Exec(
		ctx,
		`UPDATE investment_lots SET deleted_at = $3, updated_at = $3
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
		if err := r.cursor.Bump(ctx, tx, userID, sync.EntityInvestmentLot, deletedAt); err != nil {
			return err
		}
	}
	return tx.Commit(ctx)
}
