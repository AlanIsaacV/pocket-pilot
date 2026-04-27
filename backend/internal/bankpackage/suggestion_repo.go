package bankpackage

import (
	"context"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
)

// Suggestion modela una propuesta del cliente almacenada en
// package_suggestions. Sin user_id por diseño (anonimato — la decisión de
// "este package es banco" no se liga a quién la originó). Mismo patrón
// estructural que internal/notificationparser/CandidateParser.
//
// El admin revisa esta tabla periódicamente; cuando promueve, llama
// bankpackage.Repository.Upsert(ctx, ...) y luego SetPromoted aquí para
// dejar trazabilidad.
type Suggestion struct {
	ID             uuid.UUID
	PackageName    string
	ProposedBankID string // vacío si no
	ProposedLabel  string
	Status         string // pending | promoted | rejected | duplicate
	PromotedToID   *uuid.UUID
	ReviewedAt     *time.Time
	CreatedAt      time.Time
}

// SuggestionRepository persiste las propuestas. Es un repo aparte del
// Repository de bank_packages para mantener responsabilidades enfocadas y
// porque las dos tablas tienen ciclos de vida muy distintos (catálogo
// curado vs cola de revisión).
type SuggestionRepository struct {
	pool *pgxpool.Pool
}

func NewSuggestionRepository(pool *pgxpool.Pool) *SuggestionRepository {
	return &SuggestionRepository{pool: pool}
}

// Insert escribe una nueva fila en package_suggestions. status default
// 'pending' a nivel de DB. Idempotencia a nivel de aplicación: el handler
// puede invocar varias veces para el mismo package — el admin tooling
// deduplica al revisar.
func (r *SuggestionRepository) Insert(ctx context.Context, s Suggestion) (uuid.UUID, error) {
	id := uuid.New()
	_, err := r.pool.Exec(ctx, `
		INSERT INTO package_suggestions (
			id, package_name,
			proposed_bank_id, proposed_label,
			status, created_at
		) VALUES (
			$1, $2,
			NULLIF($3, ''), $4,
			'pending', NOW()
		)
	`,
		id, s.PackageName,
		s.ProposedBankID, s.ProposedLabel,
	)
	return id, err
}
