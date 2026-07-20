// Command migrate applies the embedded SQL migrations against DATABASE_URL and
// exits. It is a one-shot companion to cmd/server, shipped in the same image so
// the Raspberry Pi can migrate its schema without a Go/psql toolchain:
//
//	docker compose --profile tools run --rm migrate
//
// Unlike `make migrate` (which blindly re-pipes every .sql through psql and
// tolerates "already exists" errors), this tracks applied versions in a
// schema_migrations table and runs each file exactly once, inside its own
// transaction. The .sql files are NOT idempotent, so tracking is what makes a
// re-run on an already-migrated database a no-op instead of a failure.
package main

import (
	"context"
	"fmt"
	"log/slog"
	"os"
	"sort"
	"strings"

	"github.com/jackc/pgx/v5"

	"github.com/AlanIsaacV/pocket-pilot/migrations"
)

func main() {
	ctx := context.Background()

	dbURL := os.Getenv("DATABASE_URL")
	if dbURL == "" {
		slog.Error("DATABASE_URL environment variable is required")
		os.Exit(1)
	}

	conn, err := pgx.Connect(ctx, dbURL)
	if err != nil {
		slog.Error("connect", "error", err)
		os.Exit(1)
	}
	defer conn.Close(ctx)

	if _, err := conn.Exec(ctx, `
		CREATE TABLE IF NOT EXISTS schema_migrations (
			version    text        PRIMARY KEY,
			applied_at timestamptz NOT NULL DEFAULT now()
		)`); err != nil {
		slog.Error("create schema_migrations", "error", err)
		os.Exit(1)
	}

	files, err := sqlFiles()
	if err != nil {
		slog.Error("read embedded migrations", "error", err)
		os.Exit(1)
	}

	applied := 0
	for _, name := range files {
		var exists bool
		if err := conn.QueryRow(ctx,
			`SELECT EXISTS (SELECT 1 FROM schema_migrations WHERE version = $1)`, name,
		).Scan(&exists); err != nil {
			slog.Error("check version", "file", name, "error", err)
			os.Exit(1)
		}
		if exists {
			continue
		}

		sql, err := migrations.FS.ReadFile(name)
		if err != nil {
			slog.Error("read file", "file", name, "error", err)
			os.Exit(1)
		}

		if err := applyOne(ctx, conn, name, string(sql)); err != nil {
			slog.Error("apply", "file", name, "error", err)
			os.Exit(1)
		}
		slog.Info("applied", "file", name)
		applied++
	}

	slog.Info("migrations up to date", "applied", applied, "total", len(files))
}

// applyOne runs a single migration and records its version in one transaction,
// so a mid-file failure leaves neither the partial DDL nor the version marker.
func applyOne(ctx context.Context, conn *pgx.Conn, name, sql string) error {
	tx, err := conn.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)

	if _, err := tx.Exec(ctx, sql); err != nil {
		return err
	}
	if _, err := tx.Exec(ctx,
		`INSERT INTO schema_migrations (version) VALUES ($1)`, name,
	); err != nil {
		return err
	}
	return tx.Commit(ctx)
}

// sqlFiles returns the embedded .sql file names sorted lexically, which matches
// the zero-padded NNN_ prefix ordering the migrations rely on.
func sqlFiles() ([]string, error) {
	entries, err := migrations.FS.ReadDir(".")
	if err != nil {
		return nil, err
	}
	var names []string
	for _, e := range entries {
		if !e.IsDir() && strings.HasSuffix(e.Name(), ".sql") {
			names = append(names, e.Name())
		}
	}
	sort.Strings(names)
	if len(names) == 0 {
		return nil, fmt.Errorf("no .sql migrations embedded")
	}
	return names, nil
}
