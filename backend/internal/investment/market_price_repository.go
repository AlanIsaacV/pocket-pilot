package investment

import (
	"context"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/AlanIsaacV/pocket-pilot/internal/sync"
)

// MarketPriceRepository handles reads for all users (no user_id filter since
// the table is global) and writes from the backend cron. There is no
// per-user write path: clients never push market prices.
type MarketPriceRepository struct {
	pool   *pgxpool.Pool
	cursor *sync.CursorStore
}

func NewMarketPriceRepository(pool *pgxpool.Pool, cursor *sync.CursorStore) *MarketPriceRepository {
	return &MarketPriceRepository{pool: pool, cursor: cursor}
}

const marketPriceScanColumns = `symbol, exchange, currency_code, price, price_date, source, fetched_at, updated_at`

func scanMarketPrice(row pgx.Row) (*MarketPrice, error) {
	mp := &MarketPrice{}
	err := row.Scan(
		&mp.Symbol,
		&mp.Exchange,
		&mp.CurrencyCode,
		&mp.Price,
		&mp.PriceDate,
		&mp.Source,
		&mp.FetchedAt,
		&mp.UpdatedAt,
	)
	if err != nil {
		return nil, err
	}
	return mp, nil
}

// List returns delta or full page of market prices. The table is global, so
// no userID filter is applied.
func (r *MarketPriceRepository) List(ctx context.Context, updatedSince *time.Time, limit, offset int) ([]*MarketPrice, time.Time, error) {
	syncedAt := time.Now().UTC()

	var (
		rows pgx.Rows
		err  error
	)

	if updatedSince != nil {
		rows, err = r.pool.Query(
			ctx,
			`SELECT `+marketPriceScanColumns+`
			 FROM market_prices
			 WHERE updated_at > $1
			 ORDER BY updated_at ASC`,
			updatedSince,
		)
	} else {
		rows, err = r.pool.Query(
			ctx,
			`SELECT `+marketPriceScanColumns+`
			 FROM market_prices
			 ORDER BY updated_at DESC
			 LIMIT $1 OFFSET $2`,
			limit,
			offset,
		)
	}
	if err != nil {
		return nil, syncedAt, err
	}
	defer rows.Close()

	var items []*MarketPrice
	for rows.Next() {
		mp, err := scanMarketPrice(rows)
		if err != nil {
			return nil, syncedAt, err
		}
		items = append(items, mp)
	}
	return items, syncedAt, rows.Err()
}

// Upsert writes a fetched price and bumps the market_price cursor for every
// user who owns a holding on this (symbol, exchange). Used by the Phase 4
// cron; no user-facing handler exposes this.
func (r *MarketPriceRepository) Upsert(ctx context.Context, mp *MarketPrice) error {
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)

	_, err = tx.Exec(
		ctx,
		`
		INSERT INTO market_prices (
			symbol, exchange, currency_code, price, price_date, source,
			fetched_at, updated_at
		)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
		ON CONFLICT (symbol, exchange) DO UPDATE SET
			currency_code = EXCLUDED.currency_code,
			price         = EXCLUDED.price,
			price_date    = EXCLUDED.price_date,
			source        = EXCLUDED.source,
			fetched_at    = EXCLUDED.fetched_at,
			updated_at    = EXCLUDED.updated_at
		`,
		normalizeUpper(mp.Symbol),
		normalizeUpper(mp.Exchange),
		mp.CurrencyCode,
		mp.Price,
		mp.PriceDate,
		normalizeLower(mp.Source),
		mp.FetchedAt,
		mp.UpdatedAt,
	)
	if err != nil {
		return err
	}

	// Bump the cursor only for users that hold this symbol+exchange so
	// irrelevant clients don't refetch.
	rows, err := tx.Query(
		ctx,
		`SELECT DISTINCT user_id
		 FROM investment_holdings
		 WHERE symbol = $1 AND exchange = $2 AND deleted_at IS NULL`,
		normalizeUpper(mp.Symbol),
		normalizeUpper(mp.Exchange),
	)
	if err != nil {
		return err
	}
	defer rows.Close()

	var userIDs []uuid.UUID
	for rows.Next() {
		var uid uuid.UUID
		if err := rows.Scan(&uid); err != nil {
			return err
		}
		userIDs = append(userIDs, uid)
	}
	if err := rows.Err(); err != nil {
		return err
	}

	for _, uid := range userIDs {
		if err := r.cursor.Bump(ctx, tx, uid, sync.EntityMarketPrice, mp.UpdatedAt); err != nil {
			return err
		}
	}

	return tx.Commit(ctx)
}
