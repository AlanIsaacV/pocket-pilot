package auth

import (
	"context"
	"errors"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

type Repository struct {
	pool *pgxpool.Pool
}

func NewRepository(pool *pgxpool.Pool) *Repository {
	return &Repository{pool: pool}
}

func (r *Repository) FindUserByEmail(ctx context.Context, email string) (*User, error) {
	row := r.pool.QueryRow(ctx,
		`SELECT id, email, created_at, updated_at FROM users WHERE email = $1 LIMIT 1`,
		email,
	)
	u := &User{}
	err := row.Scan(&u.ID, &u.Email, &u.CreatedAt, &u.UpdatedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	return u, nil
}

func (r *Repository) CreateUserWithIdentity(ctx context.Context, email, provider, providerID string) (*User, error) {
	tx, err := r.pool.BeginTx(ctx, pgx.TxOptions{IsoLevel: pgx.Serializable})
	if err != nil {
		return nil, err
	}
	defer tx.Rollback(ctx)

	var existing uuid.UUID
	err = tx.QueryRow(ctx,
		`SELECT id FROM users WHERE email = $1 LIMIT 1`,
		email,
	).Scan(&existing)
	if err == nil {
		_, err = tx.Exec(ctx,
			`INSERT INTO user_identities (user_id, provider, provider_id) VALUES ($1, $2, $3)
			 ON CONFLICT (provider, provider_id) DO NOTHING`,
			existing, provider, providerID,
		)
		if err != nil {
			return nil, err
		}
		if err := tx.Commit(ctx); err != nil {
			return nil, err
		}
		return &User{ID: existing, Email: email}, nil
	}
	if !errors.Is(err, pgx.ErrNoRows) {
		return nil, err
	}

	u := &User{}
	err = tx.QueryRow(ctx,
		`INSERT INTO users (email) VALUES ($1) RETURNING id, email, created_at, updated_at`,
		email,
	).Scan(&u.ID, &u.Email, &u.CreatedAt, &u.UpdatedAt)
	if err != nil {
		return nil, err
	}

	_, err = tx.Exec(ctx,
		`INSERT INTO user_identities (user_id, provider, provider_id) VALUES ($1, $2, $3)`,
		u.ID, provider, providerID,
	)
	if err != nil {
		return nil, err
	}

	if err := tx.Commit(ctx); err != nil {
		return nil, err
	}
	return u, nil
}

func (r *Repository) LinkIdentity(ctx context.Context, userID uuid.UUID, provider, providerID string) error {
	_, err := r.pool.Exec(ctx,
		`INSERT INTO user_identities (user_id, provider, provider_id) VALUES ($1, $2, $3)
		 ON CONFLICT (provider, provider_id) DO NOTHING`,
		userID, provider, providerID,
	)
	return err
}

func (r *Repository) SaveRefreshToken(ctx context.Context, userID uuid.UUID, tokenHash string, expiresAt time.Time) error {
	_, err := r.pool.Exec(ctx,
		`INSERT INTO refresh_tokens (user_id, token_hash, expires_at) VALUES ($1, $2, $3)`,
		userID, tokenHash, expiresAt,
	)
	return err
}

func (r *Repository) FindRefreshToken(ctx context.Context, tokenHash string) (*RefreshTokenRecord, error) {
	row := r.pool.QueryRow(ctx,
		`SELECT id, user_id, token_hash, expires_at, is_revoked, created_at
		 FROM refresh_tokens
		 WHERE token_hash = $1`,
		tokenHash,
	)
	rt := &RefreshTokenRecord{}
	err := row.Scan(&rt.ID, &rt.UserID, &rt.TokenHash, &rt.ExpiresAt, &rt.IsRevoked, &rt.CreatedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	return rt, nil
}

func (r *Repository) RevokeToken(ctx context.Context, tokenID uuid.UUID) error {
	_, err := r.pool.Exec(ctx,
		`UPDATE refresh_tokens SET is_revoked = TRUE WHERE id = $1`,
		tokenID,
	)
	return err
}

func (r *Repository) RevokeTokenByHash(ctx context.Context, tokenHash string) error {
	_, err := r.pool.Exec(ctx,
		`UPDATE refresh_tokens SET is_revoked = TRUE WHERE token_hash = $1 AND is_revoked = FALSE`,
		tokenHash,
	)
	return err
}

func (r *Repository) RevokeAllTokens(ctx context.Context, userID uuid.UUID) error {
	_, err := r.pool.Exec(ctx,
		`UPDATE refresh_tokens SET is_revoked = TRUE WHERE user_id = $1 AND is_revoked = FALSE`,
		userID,
	)
	return err
}

func (r *Repository) FindUserByID(ctx context.Context, userID uuid.UUID) (*User, error) {
	row := r.pool.QueryRow(ctx,
		`SELECT id, email, created_at, updated_at FROM users WHERE id = $1`,
		userID,
	)
	u := &User{}
	err := row.Scan(&u.ID, &u.Email, &u.CreatedAt, &u.UpdatedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	return u, nil
}
