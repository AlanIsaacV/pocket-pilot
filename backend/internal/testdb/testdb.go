// Package testdb provides a minimal helper for repository integration
// tests. Tests require the TEST_DATABASE_URL env var to point at a
// disposable PostgreSQL instance. If unset, tests are skipped.
package testdb

import (
	"context"
	"os"
	"testing"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
)

// OpenPool returns a pgxpool connected to TEST_DATABASE_URL, or skips
// the test if the env var is empty.
func OpenPool(t *testing.T) *pgxpool.Pool {
	t.Helper()
	url := os.Getenv("TEST_DATABASE_URL")
	if url == "" {
		t.Skip("TEST_DATABASE_URL not set; skipping integration test")
	}
	pool, err := pgxpool.New(context.Background(), url)
	if err != nil {
		t.Fatalf("pgxpool.New: %v", err)
	}
	t.Cleanup(pool.Close)
	return pool
}

// NewUser inserts a fresh users row and returns its id. Rows inserted
// via this helper are cleaned up automatically in t.Cleanup.
func NewUser(t *testing.T, pool *pgxpool.Pool) uuid.UUID {
	t.Helper()
	ctx := context.Background()
	id := uuid.New()
	_, err := pool.Exec(ctx, `
		INSERT INTO users (id, email, created_at, updated_at)
		VALUES ($1, $2, NOW(), NOW())
	`, id, id.String()+"@test.local")
	if err != nil {
		t.Fatalf("insert user: %v", err)
	}
	t.Cleanup(func() {
		_, _ = pool.Exec(ctx, `DELETE FROM users WHERE id = $1`, id)
	})
	return id
}
