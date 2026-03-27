package userpreference

import (
	"context"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

type UserPreference struct {
	UserID    uuid.UUID
	PrefKey   string
	PrefValue string
	CreatedAt time.Time
	UpdatedAt time.Time
	DeletedAt *time.Time
}

type Repository struct {
	pool *pgxpool.Pool
}

func NewRepository(pool *pgxpool.Pool) *Repository {
	return &Repository{pool: pool}
}

const scanColumns = `user_id, pref_key, pref_value, created_at, updated_at, deleted_at`

func (r *Repository) scan(row pgx.Row) (*UserPreference, error) {
	p := &UserPreference{}
	err := row.Scan(
		&p.UserID, &p.PrefKey, &p.PrefValue,
		&p.CreatedAt, &p.UpdatedAt, &p.DeletedAt,
	)
	if err != nil {
		return nil, err
	}
	return p, nil
}

func (r *Repository) GetByKey(ctx context.Context, userID uuid.UUID, prefKey string) (*UserPreference, error) {
	row := r.pool.QueryRow(ctx,
		`SELECT `+scanColumns+` FROM user_preferences WHERE user_id = $1 AND pref_key = $2`,
		userID, prefKey,
	)
	return r.scan(row)
}

func (r *Repository) List(ctx context.Context, userID uuid.UUID, updatedSince *time.Time, limit, offset int) ([]*UserPreference, time.Time, error) {
	syncedAt := time.Now().UTC()

	var (
		rows pgx.Rows
		err  error
	)

	if updatedSince != nil {
		rows, err = r.pool.Query(ctx,
			`SELECT `+scanColumns+`
			 FROM user_preferences
			 WHERE user_id = $1 AND updated_at > $2
			 ORDER BY updated_at ASC`,
			userID, updatedSince,
		)
	} else {
		rows, err = r.pool.Query(ctx,
			`SELECT `+scanColumns+`
			 FROM user_preferences
			 WHERE user_id = $1 AND deleted_at IS NULL
			 ORDER BY pref_key ASC
			 LIMIT $2 OFFSET $3`,
			userID, limit, offset,
		)
	}
	if err != nil {
		return nil, syncedAt, err
	}
	defer rows.Close()

	var prefs []*UserPreference
	for rows.Next() {
		p := &UserPreference{}
		if err := rows.Scan(
			&p.UserID, &p.PrefKey, &p.PrefValue,
			&p.CreatedAt, &p.UpdatedAt, &p.DeletedAt,
		); err != nil {
			return nil, syncedAt, err
		}
		prefs = append(prefs, p)
	}
	return prefs, syncedAt, rows.Err()
}

func (r *Repository) Upsert(ctx context.Context, p *UserPreference) (*UserPreference, bool, error) {
	row := r.pool.QueryRow(ctx, `
		INSERT INTO user_preferences (user_id, pref_key, pref_value, created_at, updated_at)
		VALUES ($1, $2, $3, $4, $5)
		ON CONFLICT (user_id, pref_key) DO UPDATE SET
			pref_value  = EXCLUDED.pref_value,
			deleted_at  = NULL,
			updated_at  = EXCLUDED.updated_at
		WHERE user_preferences.updated_at < EXCLUDED.updated_at
		RETURNING `+scanColumns,
		p.UserID, p.PrefKey, p.PrefValue, p.CreatedAt, p.UpdatedAt,
	)

	result, err := r.scan(row)
	if err == nil {
		return result, false, nil
	}
	if err != pgx.ErrNoRows {
		return nil, false, err
	}

	current, err := r.GetByKey(ctx, p.UserID, p.PrefKey)
	if err != nil {
		return nil, false, err
	}
	return current, true, nil
}

func (r *Repository) SoftDelete(ctx context.Context, userID uuid.UUID, prefKey string, deletedAt time.Time) error {
	_, err := r.pool.Exec(ctx, `
		UPDATE user_preferences SET deleted_at = $3, updated_at = $3
		WHERE user_id = $1 AND pref_key = $2
		  AND (deleted_at IS NULL OR updated_at < $3)
	`, userID, prefKey, deletedAt)
	return err
}
