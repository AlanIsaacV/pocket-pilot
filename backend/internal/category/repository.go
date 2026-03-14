package category

import (
	"context"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

type Category struct {
	ID        uuid.UUID
	UserID    uuid.UUID
	Name      string
	Type      string // "income", "expense"
	CreatedAt time.Time
	UpdatedAt time.Time
}

type Repository struct {
	pool *pgxpool.Pool
}

func NewRepository(pool *pgxpool.Pool) *Repository {
	return &Repository{pool: pool}
}

func (r *Repository) Create(ctx context.Context, userID uuid.UUID, name, typ string) (*Category, error) {
	c := &Category{}
	err := r.pool.QueryRow(ctx, `
		INSERT INTO categories (user_id, name, type)
		VALUES ($1, $2, $3)
		RETURNING id, user_id, name, type, created_at, updated_at
	`, userID, name, typ).Scan(
		&c.ID, &c.UserID, &c.Name, &c.Type, &c.CreatedAt, &c.UpdatedAt,
	)
	return c, err
}

func (r *Repository) GetByID(ctx context.Context, id, userID uuid.UUID) (*Category, error) {
	c := &Category{}
	err := r.pool.QueryRow(ctx, `
		SELECT id, user_id, name, type, created_at, updated_at
		FROM categories
		WHERE id = $1 AND user_id = $2 AND deleted_at IS NULL
	`, id, userID).Scan(
		&c.ID, &c.UserID, &c.Name, &c.Type, &c.CreatedAt, &c.UpdatedAt,
	)
	return c, err
}

func (r *Repository) List(ctx context.Context, userID uuid.UUID, typeFilter string, limit, offset int) ([]*Category, int, error) {
	// Build the WHERE clause dynamically based on the optional type filter.
	// Using $3 = '' as the "no filter" sentinel avoids building query strings with fmt.Sprintf.
	var total int
	if err := r.pool.QueryRow(ctx, `
		SELECT COUNT(*) FROM categories
		WHERE user_id = $1 AND deleted_at IS NULL AND ($2 = '' OR type = $2)
	`, userID, typeFilter).Scan(&total); err != nil {
		return nil, 0, err
	}

	rows, err := r.pool.Query(ctx, `
		SELECT id, user_id, name, type, created_at, updated_at
		FROM categories
		WHERE user_id = $1 AND deleted_at IS NULL AND ($2 = '' OR type = $2)
		ORDER BY name ASC
		LIMIT $3 OFFSET $4
	`, userID, typeFilter, limit, offset)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()

	var categories []*Category
	for rows.Next() {
		c := &Category{}
		if err := rows.Scan(&c.ID, &c.UserID, &c.Name, &c.Type, &c.CreatedAt, &c.UpdatedAt); err != nil {
			return nil, 0, err
		}
		categories = append(categories, c)
	}
	return categories, total, rows.Err()
}

func (r *Repository) Update(ctx context.Context, id, userID uuid.UUID, name, typ string) (*Category, error) {
	c := &Category{}
	err := r.pool.QueryRow(ctx, `
		UPDATE categories SET
			name = CASE WHEN $3 != '' THEN $3 ELSE name END,
			type = CASE WHEN $4 != '' THEN $4 ELSE type END
		WHERE id = $1 AND user_id = $2 AND deleted_at IS NULL
		RETURNING id, user_id, name, type, created_at, updated_at
	`, id, userID, name, typ).Scan(
		&c.ID, &c.UserID, &c.Name, &c.Type, &c.CreatedAt, &c.UpdatedAt,
	)
	return c, err
}

func (r *Repository) Delete(ctx context.Context, id, userID uuid.UUID) error {
	result, err := r.pool.Exec(ctx, `
		UPDATE categories SET deleted_at = NOW()
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
