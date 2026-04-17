package transactiontemplate_test

import (
	"context"
	"testing"
	"time"

	"github.com/google/uuid"

	"github.com/AlanIsaacV/pocket-pilot/internal/account"
	"github.com/AlanIsaacV/pocket-pilot/internal/sync"
	"github.com/AlanIsaacV/pocket-pilot/internal/testdb"
	"github.com/AlanIsaacV/pocket-pilot/internal/transactiontemplate"
)

func newTestTemplate(user, accountID uuid.UUID, t time.Time) *transactiontemplate.Template {
	return &transactiontemplate.Template{
		ID:           uuid.New(),
		UserID:       user,
		Name:         "Test Template",
		AccountID:    accountID,
		Type:         "expense",
		CurrencyCode: "MXN",
		Tags:         []string{},
		CreatedAt:    t,
		UpdatedAt:    t,
		IsActive:     true,
	}
}

func setupTemplatePrereqs(t *testing.T) (context.Context, *sync.CursorStore, *transactiontemplate.Repository, uuid.UUID, uuid.UUID) {
	t.Helper()
	ctx := context.Background()
	pool := testdb.OpenPool(t)
	user := testdb.NewUser(t, pool)
	cursor := sync.NewCursorStore(pool)
	accRepo := account.NewRepository(pool, cursor)
	tmplRepo := transactiontemplate.NewRepository(pool, cursor)

	t.Cleanup(func() {
		_, _ = pool.Exec(ctx, `DELETE FROM transaction_templates WHERE user_id = $1`, user)
		_, _ = pool.Exec(ctx, `DELETE FROM user_sync_cursors WHERE user_id = $1`, user)
		_, _ = pool.Exec(ctx, `DELETE FROM accounts WHERE user_id = $1`, user)
	})

	createdAcc := time.Now().UTC().Add(-2 * time.Hour).Truncate(time.Microsecond)
	acc := &account.Account{
		ID: uuid.New(), UserID: user, Name: "A", Type: "bank",
		CurrencyCode: "MXN", CreatedAt: createdAcc, UpdatedAt: createdAcc,
	}
	if _, _, err := accRepo.Upsert(ctx, acc); err != nil {
		t.Fatalf("prereq account: %v", err)
	}
	// Scrub cursors so only the template bump is asserted.
	if _, err := pool.Exec(ctx, `DELETE FROM user_sync_cursors WHERE user_id = $1`, user); err != nil {
		t.Fatalf("scrub: %v", err)
	}
	return ctx, cursor, tmplRepo, user, acc.ID
}

func TestTemplateRepo_Upsert_BumpsCursor(t *testing.T) {
	ctx, cursor, repo, user, accID := setupTemplatePrereqs(t)
	now := time.Now().UTC().Truncate(time.Microsecond)
	if _, _, err := repo.Upsert(ctx, newTestTemplate(user, accID, now)); err != nil {
		t.Fatalf("Upsert: %v", err)
	}
	got, _ := cursor.GetAll(ctx, user)
	if !got[sync.EntityTransactionTemplate].Equal(now) {
		t.Fatalf("cursor: want %v got %v", now, got[sync.EntityTransactionTemplate])
	}
}

func TestTemplateRepo_SoftDelete_BumpsCursor(t *testing.T) {
	ctx, cursor, repo, user, accID := setupTemplatePrereqs(t)
	created := time.Now().UTC().Add(-time.Hour).Truncate(time.Microsecond)
	tmpl := newTestTemplate(user, accID, created)
	if _, _, err := repo.Upsert(ctx, tmpl); err != nil {
		t.Fatalf("Upsert: %v", err)
	}
	deletedAt := time.Now().UTC().Truncate(time.Microsecond)
	if err := repo.SoftDelete(ctx, tmpl.ID, user, deletedAt); err != nil {
		t.Fatalf("SoftDelete: %v", err)
	}
	got, _ := cursor.GetAll(ctx, user)
	if !got[sync.EntityTransactionTemplate].Equal(deletedAt) {
		t.Fatalf("cursor: want %v got %v", deletedAt, got[sync.EntityTransactionTemplate])
	}
}

func TestTemplateRepo_Upsert_LWWRejection_DoesNotBump(t *testing.T) {
	ctx, cursor, repo, user, accID := setupTemplatePrereqs(t)
	newer := time.Now().UTC().Truncate(time.Microsecond)
	older := newer.Add(-time.Hour)

	id := uuid.New()
	if _, _, err := repo.Upsert(ctx, &transactiontemplate.Template{
		ID: id, UserID: user, Name: "new", AccountID: accID,
		Type: "expense", CurrencyCode: "MXN", Tags: []string{},
		CreatedAt: newer, UpdatedAt: newer, IsActive: true,
	}); err != nil {
		t.Fatalf("Upsert newer: %v", err)
	}

	_, resolved, err := repo.Upsert(ctx, &transactiontemplate.Template{
		ID: id, UserID: user, Name: "old", AccountID: accID,
		Type: "expense", CurrencyCode: "MXN", Tags: []string{},
		CreatedAt: older, UpdatedAt: older, IsActive: true,
	})
	if err != nil {
		t.Fatalf("Upsert older: %v", err)
	}
	if !resolved {
		t.Fatalf("expected conflict_resolved=true")
	}
	got, _ := cursor.GetAll(ctx, user)
	if !got[sync.EntityTransactionTemplate].Equal(newer) {
		t.Fatalf("cursor regressed: want %v got %v", newer, got[sync.EntityTransactionTemplate])
	}
}
