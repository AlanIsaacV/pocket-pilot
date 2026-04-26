package notificationparser

import (
	"context"
	"encoding/json"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
)

// CandidateParser modela una propuesta del LLM almacenada en la tabla
// candidate_parsers. Sin user_id por diseño (anonimato — el sample no se liga
// a quién lo originó). El admin revisa esta tabla periódicamente y promueve
// los candidatos a `notification_parsers` vía SQL directo.
type CandidateParser struct {
	ID                 uuid.UUID
	BankID             string
	PackageName        string
	SampleTitle        string
	SampleText         string
	SampleBigText      string
	ProposedPatternID  string
	ProposedRegex      string // vacío si el LLM no propuso o el regex falló validación
	ProposedTxType     string
	ProposedCurrency   string
	ExtractedFields    json.RawMessage
	LLMProvider        string
	LLMModelVersion    string
	LLMConfidence      float64
	Status             string // pending | promoted | rejected
	CreatedAt          time.Time
}

// CandidateRepository persiste las propuestas del LLM. Es un repo aparte del
// Repository de parsers globales para mantener la responsabilidad enfocada y
// porque las dos tablas tienen ciclos de vida muy distintos (catálogo
// curado vs. cola de revisión).
type CandidateRepository struct {
	pool *pgxpool.Pool
}

func NewCandidateRepository(pool *pgxpool.Pool) *CandidateRepository {
	return &CandidateRepository{pool: pool}
}

// Insert escribe una nueva fila en candidate_parsers. status default es
// 'pending' a nivel de DB. extracted_fields se serializa como JSONB.
func (r *CandidateRepository) Insert(ctx context.Context, c CandidateParser) (uuid.UUID, error) {
	id := uuid.New()
	_, err := r.pool.Exec(ctx, `
		INSERT INTO candidate_parsers (
			id, bank_id, package_name,
			sample_title, sample_text, sample_big_text,
			proposed_pattern_id, proposed_regex, proposed_tx_type, proposed_currency,
			extracted_fields,
			llm_provider, llm_model_version, llm_confidence,
			status, created_at
		) VALUES (
			$1, $2, $3,
			$4, $5, $6,
			$7, NULLIF($8, ''), NULLIF($9, ''), NULLIF($10, ''),
			$11,
			$12, $13, NULLIF($14, 0)::numeric,
			'pending', NOW()
		)
	`,
		id, c.BankID, c.PackageName,
		nullableText(c.SampleTitle), nullableText(c.SampleText), nullableText(c.SampleBigText),
		nullableText(c.ProposedPatternID), c.ProposedRegex, c.ProposedTxType, c.ProposedCurrency,
		c.ExtractedFields,
		c.LLMProvider, c.LLMModelVersion, c.LLMConfidence,
	)
	return id, err
}

// nullableText convierte string vacío a nil para que la columna quede NULL en
// vez de string vacía. Las columnas sample_* son TEXT NULL en el schema.
func nullableText(s string) any {
	if s == "" {
		return nil
	}
	return s
}
