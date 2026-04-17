package category

import (
	"context"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/AlanIsaacV/pocket-pilot/internal/sync"
)

// Category mirrors the `categories` table.
type Category struct {
	ID        uuid.UUID
	UserID    uuid.UUID
	Name      string
	Icon      string
	Color     string
	ParentID  *uuid.UUID
	Type          string // "income" | "expense"
	DefaultNature string // "required" | "obligation" | "lifestyle" | "active" | "passive" | "windfall" | ""
	CreatedAt     time.Time
	UpdatedAt time.Time
	DeletedAt *time.Time
}

type Repository struct {
	pool   *pgxpool.Pool
	cursor *sync.CursorStore
}

func NewRepository(pool *pgxpool.Pool, cursor *sync.CursorStore) *Repository {
	return &Repository{pool: pool, cursor: cursor}
}

const scanColumns = `id, user_id, name, icon, color, parent_id, type, default_nature, created_at, updated_at, deleted_at`

func (r *Repository) scan(row pgx.Row) (*Category, error) {
	c := &Category{}
	err := row.Scan(
		&c.ID, &c.UserID, &c.Name, &c.Icon, &c.Color,
		&c.ParentID, &c.Type, &c.DefaultNature,
		&c.CreatedAt, &c.UpdatedAt, &c.DeletedAt,
	)
	if err != nil {
		return nil, err
	}
	return c, nil
}

// GetByID fetches a single category regardless of deleted_at status.
// Used to return the server's current version after a LWW conflict.
func (r *Repository) GetByID(ctx context.Context, id, userID uuid.UUID) (*Category, error) {
	row := r.pool.QueryRow(ctx,
		`SELECT `+scanColumns+` FROM categories WHERE id = $1 AND user_id = $2`,
		id, userID,
	)
	return r.scan(row)
}

// List returns categories for a user.
//
// If updatedSince is non-nil → delta sync: returns all records (active AND deleted)
// with updated_at > updatedSince, no LIMIT applied.
//
// If updatedSince is nil → full sync: returns only active records with pagination.
func (r *Repository) List(ctx context.Context, userID uuid.UUID, updatedSince *time.Time, limit, offset int) ([]*Category, time.Time, error) {
	syncedAt := time.Now().UTC()

	var (
		rows pgx.Rows
		err  error
	)

	if updatedSince != nil {
		rows, err = r.pool.Query(ctx,
			`SELECT `+scanColumns+`
			 FROM categories
			 WHERE user_id = $1 AND updated_at > $2
			 ORDER BY updated_at ASC`,
			userID, updatedSince,
		)
	} else {
		rows, err = r.pool.Query(ctx,
			`SELECT `+scanColumns+`
			 FROM categories
			 WHERE user_id = $1 AND deleted_at IS NULL
			 ORDER BY name ASC
			 LIMIT $2 OFFSET $3`,
			userID, limit, offset,
		)
	}
	if err != nil {
		return nil, syncedAt, err
	}
	defer rows.Close()

	var categories []*Category
	for rows.Next() {
		c := &Category{}
		if err := rows.Scan(
			&c.ID, &c.UserID, &c.Name, &c.Icon, &c.Color,
			&c.ParentID, &c.Type, &c.DefaultNature,
			&c.CreatedAt, &c.UpdatedAt, &c.DeletedAt,
		); err != nil {
			return nil, syncedAt, err
		}
		categories = append(categories, c)
	}
	return categories, syncedAt, rows.Err()
}

// Upsert inserts or updates a category applying Last Write Wins.
//
// Returns (category, conflictResolved, error):
//   - conflictResolved=false: incoming version was accepted.
//   - conflictResolved=true:  server had a newer version; returned category is the server's.
func (r *Repository) Upsert(ctx context.Context, c *Category) (*Category, bool, error) {
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return nil, false, err
	}
	defer tx.Rollback(ctx)

	row := tx.QueryRow(ctx, `
		INSERT INTO categories (id, user_id, name, icon, color, parent_id, type, default_nature, created_at, updated_at)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
		ON CONFLICT (id) DO UPDATE SET
			name           = EXCLUDED.name,
			icon           = EXCLUDED.icon,
			color          = EXCLUDED.color,
			parent_id      = EXCLUDED.parent_id,
			type           = EXCLUDED.type,
			default_nature = EXCLUDED.default_nature,
			updated_at     = EXCLUDED.updated_at
		WHERE categories.updated_at < EXCLUDED.updated_at
		RETURNING `+scanColumns,
		c.ID, c.UserID, c.Name, c.Icon, c.Color, c.ParentID, c.Type, c.DefaultNature,
		c.CreatedAt, c.UpdatedAt,
	)

	result, err := r.scan(row)
	if err == nil {
		if err := r.cursor.Bump(ctx, tx, c.UserID, sync.EntityCategory, result.UpdatedAt); err != nil {
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
	current, err := r.GetByID(ctx, c.ID, c.UserID)
	if err != nil {
		return nil, false, err
	}
	return current, true, nil
}

// SoftDelete sets deleted_at on a category, applying LWW by comparing timestamps.
func (r *Repository) SoftDelete(ctx context.Context, id, userID uuid.UUID, deletedAt time.Time) error {
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)

	tag, err := tx.Exec(ctx, `
		UPDATE categories SET deleted_at = $3, updated_at = $3
		WHERE id = $1 AND user_id = $2
		  AND (deleted_at IS NULL OR updated_at < $3)
	`, id, userID, deletedAt)
	if err != nil {
		return err
	}
	if tag.RowsAffected() > 0 {
		if err := r.cursor.Bump(ctx, tx, userID, sync.EntityCategory, deletedAt); err != nil {
			return err
		}
	}
	return tx.Commit(ctx)
}
