package notificationparser_test

import (
	"context"
	"encoding/json"
	"testing"
	"time"

	"github.com/AlanIsaacV/pocket-pilot/internal/notificationparser"
	"github.com/AlanIsaacV/pocket-pilot/internal/testdb"
)

// TestPurgeOldSamples verifica que el sweeper anonimiza candidatos
// `pending` con created_at más viejos que RetentionWindow (90d) y deja
// intactos los recientes y los ya en estado terminal (`promoted`/`rejected`).
func TestCandidateRepository_PurgeOldSamples(t *testing.T) {
	ctx := context.Background()
	pool := testdb.OpenPool(t)
	repo := notificationparser.NewCandidateRepository(pool)

	t.Cleanup(func() {
		_, _ = pool.Exec(ctx, `DELETE FROM candidate_parsers WHERE bank_id = 'test_bank_retention'`)
	})

	// Inserta 3 candidatos:
	//   - viejo (>90d) en pending → debe purgarse
	//   - reciente (<90d) en pending → no se toca
	//   - viejo (>90d) en promoted → no se toca (status terminal)
	mustInsert := func(id, status string, age time.Duration) {
		_, err := pool.Exec(ctx, `
			INSERT INTO candidate_parsers (
				id, bank_id, package_name,
				sample_title, sample_text, sample_big_text,
				proposed_pattern_id, proposed_regex,
				extracted_fields,
				llm_provider, llm_model_version,
				status, created_at
			) VALUES (
				$1::uuid, 'test_bank_retention', 'com.test',
				'title', 'text', 'big',
				'pat', 'regex',
				$2, 'gemini', 'v1',
				$3, NOW() - $4::interval
			)
		`, id, json.RawMessage(`{}`), status, age.String())
		if err != nil {
			t.Fatalf("insert %s: %v", id, err)
		}
	}

	mustInsert("11111111-1111-1111-1111-111111111111", "pending", 100*24*time.Hour)
	mustInsert("22222222-2222-2222-2222-222222222222", "pending", 1*24*time.Hour)
	mustInsert("33333333-3333-3333-3333-333333333333", "promoted", 100*24*time.Hour)

	affected, err := repo.PurgeOldSamples(ctx)
	if err != nil {
		t.Fatalf("PurgeOldSamples: %v", err)
	}
	if affected != 1 {
		t.Fatalf("affected: want 1 got %d", affected)
	}

	// Estado posterior:
	type row struct {
		status      string
		title       *string
		text        *string
		bigText     *string
		purgedAt    *time.Time
	}
	getRow := func(id string) row {
		var r row
		err := pool.QueryRow(ctx, `
			SELECT status, sample_title, sample_text, sample_big_text, purged_at
			  FROM candidate_parsers WHERE id = $1::uuid
		`, id).Scan(&r.status, &r.title, &r.text, &r.bigText, &r.purgedAt)
		if err != nil {
			t.Fatalf("query %s: %v", id, err)
		}
		return r
	}

	purged := getRow("11111111-1111-1111-1111-111111111111")
	if purged.status != "purged" {
		t.Errorf("purged.status: want purged got %s", purged.status)
	}
	if purged.title != nil || purged.text != nil || purged.bigText != nil {
		t.Errorf("purged.samples: want NULLs, got %v %v %v", purged.title, purged.text, purged.bigText)
	}
	if purged.purgedAt == nil {
		t.Error("purged.purgedAt: want non-nil")
	}

	recent := getRow("22222222-2222-2222-2222-222222222222")
	if recent.status != "pending" {
		t.Errorf("recent.status: want pending got %s", recent.status)
	}
	if recent.title == nil || recent.text == nil {
		t.Error("recent.samples: want preserved")
	}
	if recent.purgedAt != nil {
		t.Errorf("recent.purgedAt: want nil got %v", recent.purgedAt)
	}

	terminal := getRow("33333333-3333-3333-3333-333333333333")
	if terminal.status != "promoted" {
		t.Errorf("terminal.status: want promoted got %s", terminal.status)
	}
	if terminal.title == nil {
		t.Error("terminal.samples: want preserved (status terminal no se purga)")
	}
}

// Idempotencia: una segunda llamada inmediata no debe afectar nada porque
// los pending ya pasaron a 'purged'.
func TestCandidateRepository_PurgeOldSamples_Idempotent(t *testing.T) {
	ctx := context.Background()
	pool := testdb.OpenPool(t)
	repo := notificationparser.NewCandidateRepository(pool)

	t.Cleanup(func() {
		_, _ = pool.Exec(ctx, `DELETE FROM candidate_parsers WHERE bank_id = 'test_bank_idem'`)
	})

	_, err := pool.Exec(ctx, `
		INSERT INTO candidate_parsers (
			id, bank_id, package_name,
			sample_title, sample_text, sample_big_text,
			proposed_pattern_id, proposed_regex,
			extracted_fields,
			llm_provider, llm_model_version,
			status, created_at
		) VALUES (
			'44444444-4444-4444-4444-444444444444'::uuid, 'test_bank_idem', 'com.test',
			'title', 'text', 'big',
			'pat', 'regex',
			'{}'::jsonb, 'gemini', 'v1',
			'pending', NOW() - INTERVAL '100 days'
		)
	`)
	if err != nil {
		t.Fatalf("insert: %v", err)
	}

	first, err := repo.PurgeOldSamples(ctx)
	if err != nil {
		t.Fatalf("first PurgeOldSamples: %v", err)
	}
	if first != 1 {
		t.Fatalf("first.affected: want 1 got %d", first)
	}

	second, err := repo.PurgeOldSamples(ctx)
	if err != nil {
		t.Fatalf("second PurgeOldSamples: %v", err)
	}
	if second != 0 {
		t.Fatalf("second.affected: want 0 got %d (sweeper no es idempotente)", second)
	}
}
