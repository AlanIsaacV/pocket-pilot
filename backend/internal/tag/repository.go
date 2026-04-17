package tag

import (
	"context"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/AlanIsaacV/pocket-pilot/internal/sync"
)

// Tag mirrors the `tags` table.
type Tag struct {
	ID        uuid.UUID
	UserID    uuid.UUID
	Name      string
	CreatedAt time.Time
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

const scanColumns = `id, user_id, name, created_at, updated_at, deleted_at`

func (r *Repository) scan(row pgx.Row) (*Tag, error) {
	t := &Tag{}
	err := row.Scan(&t.ID, &t.UserID, &t.Name, &t.CreatedAt, &t.UpdatedAt, &t.DeletedAt)
	if err != nil {
		return nil, err
	}
	return t, nil
}

// GetByID fetches a single tag regardless of deleted_at status.
func (r *Repository) GetByID(ctx context.Context, id, userID uuid.UUID) (*Tag, error) {
	row := r.pool.QueryRow(ctx,
		`SELECT `+scanColumns+` FROM tags WHERE id = $1 AND user_id = $2`,
		id, userID,
	)
	return r.scan(row)
}

// List returns tags for a user.
// Delta sync when updatedSince is non-nil; full sync with pagination otherwise.
func (r *Repository) List(ctx context.Context, userID uuid.UUID, updatedSince *time.Time, limit, offset int) ([]*Tag, time.Time, error) {
	syncedAt := time.Now().UTC()

	var (
		rows pgx.Rows
		err  error
	)

	if updatedSince != nil {
		rows, err = r.pool.Query(ctx,
			`SELECT `+scanColumns+`
			 FROM tags
			 WHERE user_id = $1 AND updated_at > $2
			 ORDER BY updated_at ASC`,
			userID, updatedSince,
		)
	} else {
		rows, err = r.pool.Query(ctx,
			`SELECT `+scanColumns+`
			 FROM tags
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

	var tags []*Tag
	for rows.Next() {
		t := &Tag{}
		if err := rows.Scan(&t.ID, &t.UserID, &t.Name, &t.CreatedAt, &t.UpdatedAt, &t.DeletedAt); err != nil {
			return nil, syncedAt, err
		}
		tags = append(tags, t)
	}
	return tags, syncedAt, rows.Err()
}

// Upsert inserts or updates a tag applying Last Write Wins.
// Returns (tag, conflictResolved, error).
func (r *Repository) Upsert(ctx context.Context, t *Tag) (*Tag, bool, error) {
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return nil, false, err
	}
	defer tx.Rollback(ctx)

	row := tx.QueryRow(ctx, `
		INSERT INTO tags (id, user_id, name, created_at, updated_at)
		VALUES ($1, $2, $3, $4, $5)
		ON CONFLICT (id) DO UPDATE SET
			name       = EXCLUDED.name,
			updated_at = EXCLUDED.updated_at
		WHERE tags.updated_at < EXCLUDED.updated_at
		RETURNING `+scanColumns,
		t.ID, t.UserID, t.Name, t.CreatedAt, t.UpdatedAt,
	)

	result, err := r.scan(row)
	if err == nil {
		if err := r.cursor.Bump(ctx, tx, t.UserID, sync.EntityTag, result.UpdatedAt); err != nil {
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

// SoftDelete sets deleted_at on a tag, applying LWW by comparing timestamps.
func (r *Repository) SoftDelete(ctx context.Context, id, userID uuid.UUID, deletedAt time.Time) error {
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)

	tag, err := tx.Exec(ctx, `
		UPDATE tags SET deleted_at = $3, updated_at = $3
		WHERE id = $1 AND user_id = $2
		  AND (deleted_at IS NULL OR updated_at < $3)
	`, id, userID, deletedAt)
	if err != nil {
		return err
	}
	if tag.RowsAffected() > 0 {
		if err := r.cursor.Bump(ctx, tx, userID, sync.EntityTag, deletedAt); err != nil {
			return err
		}
	}
	return tx.Commit(ctx)
}
