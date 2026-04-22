package investment

import (
	"context"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/AlanIsaacV/pocket-pilot/internal/sync"
)

type HoldingRepository struct {
	pool   *pgxpool.Pool
	cursor *sync.CursorStore
}

func NewHoldingRepository(pool *pgxpool.Pool, cursor *sync.CursorStore) *HoldingRepository {
	return &HoldingRepository{pool: pool, cursor: cursor}
}

const holdingScanColumns = `id, user_id, symbol, exchange, display_name, currency_code, asset_type, status, manual_price, notes, created_at, updated_at, deleted_at`

func scanHolding(row pgx.Row) (*Holding, error) {
	h := &Holding{}
	err := row.Scan(
		&h.ID,
		&h.UserID,
		&h.Symbol,
		&h.Exchange,
		&h.DisplayName,
		&h.CurrencyCode,
		&h.AssetType,
		&h.Status,
		&h.ManualPrice,
		&h.Notes,
		&h.CreatedAt,
		&h.UpdatedAt,
		&h.DeletedAt,
	)
	if err != nil {
		return nil, err
	}
	return h, nil
}

func (r *HoldingRepository) GetByID(ctx context.Context, id, userID uuid.UUID) (*Holding, error) {
	row := r.pool.QueryRow(
		ctx,
		`SELECT `+holdingScanColumns+` FROM investment_holdings WHERE id = $1 AND user_id = $2`,
		id,
		userID,
	)
	return scanHolding(row)
}

func (r *HoldingRepository) List(ctx context.Context, userID uuid.UUID, updatedSince *time.Time, limit, offset int) ([]*Holding, time.Time, error) {
	syncedAt := time.Now().UTC()

	var (
		rows pgx.Rows
		err  error
	)

	if updatedSince != nil {
		rows, err = r.pool.Query(
			ctx,
			`SELECT `+holdingScanColumns+`
			 FROM investment_holdings
			 WHERE user_id = $1 AND updated_at > $2
			 ORDER BY updated_at ASC`,
			userID,
			updatedSince,
		)
	} else {
		rows, err = r.pool.Query(
			ctx,
			`SELECT `+holdingScanColumns+`
			 FROM investment_holdings
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

	var items []*Holding
	for rows.Next() {
		h, err := scanHolding(rows)
		if err != nil {
			return nil, syncedAt, err
		}
		items = append(items, h)
	}
	return items, syncedAt, rows.Err()
}

func (r *HoldingRepository) Upsert(ctx context.Context, h *Holding) (*Holding, bool, error) {
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return nil, false, err
	}
	defer tx.Rollback(ctx)

	row := tx.QueryRow(
		ctx,
		`
		INSERT INTO investment_holdings (
			id, user_id, symbol, exchange, display_name,
			currency_code, asset_type, status, manual_price, notes,
			created_at, updated_at
		)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12)
		ON CONFLICT (id) DO UPDATE SET
			symbol        = EXCLUDED.symbol,
			exchange      = EXCLUDED.exchange,
			display_name  = EXCLUDED.display_name,
			currency_code = EXCLUDED.currency_code,
			asset_type    = EXCLUDED.asset_type,
			status        = EXCLUDED.status,
			manual_price  = EXCLUDED.manual_price,
			notes         = EXCLUDED.notes,
			updated_at    = EXCLUDED.updated_at
		WHERE investment_holdings.updated_at < EXCLUDED.updated_at
		RETURNING `+holdingScanColumns,
		h.ID,
		h.UserID,
		normalizeUpper(h.Symbol),
		normalizeUpper(h.Exchange),
		h.DisplayName,
		h.CurrencyCode,
		normalizeLower(h.AssetType),
		normalizeLower(h.Status),
		h.ManualPrice,
		h.Notes,
		h.CreatedAt,
		h.UpdatedAt,
	)

	result, err := scanHolding(row)
	if err == nil {
		if err := r.cursor.Bump(ctx, tx, h.UserID, sync.EntityInvestmentHolding, result.UpdatedAt); err != nil {
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

	current, err := r.GetByID(ctx, h.ID, h.UserID)
	if err != nil {
		return nil, false, err
	}
	return current, true, nil
}

func (r *HoldingRepository) SoftDelete(ctx context.Context, id, userID uuid.UUID, deletedAt time.Time) error {
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)

	tag, err := tx.Exec(
		ctx,
		`UPDATE investment_holdings SET deleted_at = $3, updated_at = $3
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
		if err := r.cursor.Bump(ctx, tx, userID, sync.EntityInvestmentHolding, deletedAt); err != nil {
			return err
		}
	}
	return tx.Commit(ctx)
}
