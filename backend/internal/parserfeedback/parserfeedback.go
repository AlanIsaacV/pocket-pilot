// Package parserfeedback persiste señales de calidad sobre cada decisión final
// del usuario en PendingReviewSheet (aprobar o descartar): un thumb explícito
// opcional + flags derivados que indican si el usuario tuvo que cambiar la
// cuenta, categoría, monto o descripción que el parser sugirió.
//
// Es un módulo push-only: el cliente envía vía outbox, el servidor almacena.
// El cliente nunca hace pull de feedback (ListParserFeedback queda expuesto
// para herramientas server-side y futuras pantallas de admin, pero no es
// consumido por el SyncHandler del cliente).
package parserfeedback

import (
	"context"
	"strconv"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
	"google.golang.org/protobuf/types/known/timestamppb"
	"google.golang.org/protobuf/types/known/wrapperspb"

	pb "github.com/AlanIsaacV/pocket-pilot/internal/gen/proto/pocket_pilot/v1/pocket_pilot/v1"
	"github.com/AlanIsaacV/pocket-pilot/internal/middleware"
	"github.com/AlanIsaacV/pocket-pilot/internal/sync"
)

// Feedback is the domain model. Mirrors the columns of `parser_feedback`.
//
// Punteros = NULL en la columna correspondiente. Aplica a todos los campos de
// trazabilidad (la sugerencia puede haber venido de una ruta sin parser
// identificado), a was_helpful (tri-estado: NULL = sin opinión explícita) y a
// captured_notification_id (puede no existir si la sugerencia se creó por
// otro flujo).
type Feedback struct {
	ID                     uuid.UUID
	UserID                 uuid.UUID
	PendingTransactionID   string
	CapturedNotificationID *string
	BankID                 *string
	PatternID              *string
	ParserVersion          *int32
	ExtractionMethod       *string
	WasHelpful             *bool
	AccountChanged         bool
	CategoryChanged        bool
	AmountChanged          bool
	DescriptionChanged     bool
	WasDismissed           bool
	CreatedAt              time.Time
	UpdatedAt              time.Time
	DeletedAt              *time.Time
}

const scanColumns = `id, user_id, pending_transaction_id, captured_notification_id,
	bank_id, pattern_id, parser_version, extraction_method,
	was_helpful, account_changed, category_changed, amount_changed,
	description_changed, was_dismissed, created_at, updated_at, deleted_at`

func scan(row pgx.Row) (*Feedback, error) {
	f := &Feedback{}
	err := row.Scan(
		&f.ID, &f.UserID, &f.PendingTransactionID, &f.CapturedNotificationID,
		&f.BankID, &f.PatternID, &f.ParserVersion, &f.ExtractionMethod,
		&f.WasHelpful, &f.AccountChanged, &f.CategoryChanged, &f.AmountChanged,
		&f.DescriptionChanged, &f.WasDismissed, &f.CreatedAt, &f.UpdatedAt, &f.DeletedAt,
	)
	if err != nil {
		return nil, err
	}
	return f, nil
}

// Repository ─────────────────────────────────────────────────────────────────

type Repository struct {
	pool   *pgxpool.Pool
	cursor *sync.CursorStore
}

func NewRepository(pool *pgxpool.Pool, cursor *sync.CursorStore) *Repository {
	return &Repository{pool: pool, cursor: cursor}
}

func (r *Repository) GetByID(ctx context.Context, id, userID uuid.UUID) (*Feedback, error) {
	row := r.pool.QueryRow(
		ctx,
		`SELECT `+scanColumns+` FROM parser_feedback WHERE id = $1 AND user_id = $2`,
		id, userID,
	)
	return scan(row)
}

// List returns feedback rows for sync. Delta when updatedSince != nil
// (includes soft-deleted), otherwise full list of active rows with pagination.
func (r *Repository) List(ctx context.Context, userID uuid.UUID, updatedSince *time.Time, limit, offset int) ([]*Feedback, time.Time, error) {
	syncedAt := time.Now().UTC()

	var (
		rows pgx.Rows
		err  error
	)
	if updatedSince != nil {
		rows, err = r.pool.Query(
			ctx,
			`SELECT `+scanColumns+`
			 FROM parser_feedback
			 WHERE user_id = $1 AND updated_at > $2
			 ORDER BY updated_at ASC`,
			userID, updatedSince,
		)
	} else {
		rows, err = r.pool.Query(
			ctx,
			`SELECT `+scanColumns+`
			 FROM parser_feedback
			 WHERE user_id = $1 AND deleted_at IS NULL
			 ORDER BY updated_at DESC
			 LIMIT $2 OFFSET $3`,
			userID, limit, offset,
		)
	}
	if err != nil {
		return nil, syncedAt, err
	}
	defer rows.Close()

	var items []*Feedback
	for rows.Next() {
		f, err := scan(rows)
		if err != nil {
			return nil, syncedAt, err
		}
		items = append(items, f)
	}
	return items, syncedAt, rows.Err()
}

// Upsert applies LWW. Same id collision → newer updated_at wins. La UNIQUE
// (user_id, pending_transaction_id) actúa como salvaguarda: el cliente debe
// reusar el mismo id para la misma sugerencia (lo hace, ver
// notification_capture_repository.dart::_persistFeedback).
func (r *Repository) Upsert(ctx context.Context, f *Feedback) (*Feedback, bool, error) {
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return nil, false, err
	}
	defer tx.Rollback(ctx)

	row := tx.QueryRow(
		ctx,
		`
		INSERT INTO parser_feedback (
			id, user_id, pending_transaction_id, captured_notification_id,
			bank_id, pattern_id, parser_version, extraction_method,
			was_helpful, account_changed, category_changed, amount_changed,
			description_changed, was_dismissed, created_at, updated_at, deleted_at
		)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17)
		ON CONFLICT (id) DO UPDATE SET
			pending_transaction_id   = EXCLUDED.pending_transaction_id,
			captured_notification_id = EXCLUDED.captured_notification_id,
			bank_id                  = EXCLUDED.bank_id,
			pattern_id               = EXCLUDED.pattern_id,
			parser_version           = EXCLUDED.parser_version,
			extraction_method        = EXCLUDED.extraction_method,
			was_helpful              = EXCLUDED.was_helpful,
			account_changed          = EXCLUDED.account_changed,
			category_changed         = EXCLUDED.category_changed,
			amount_changed           = EXCLUDED.amount_changed,
			description_changed      = EXCLUDED.description_changed,
			was_dismissed            = EXCLUDED.was_dismissed,
			updated_at               = EXCLUDED.updated_at,
			deleted_at               = EXCLUDED.deleted_at
		WHERE parser_feedback.updated_at < EXCLUDED.updated_at
		RETURNING `+scanColumns,
		f.ID, f.UserID, f.PendingTransactionID, f.CapturedNotificationID,
		f.BankID, f.PatternID, f.ParserVersion, f.ExtractionMethod,
		f.WasHelpful, f.AccountChanged, f.CategoryChanged, f.AmountChanged,
		f.DescriptionChanged, f.WasDismissed, f.CreatedAt, f.UpdatedAt, f.DeletedAt,
	)

	result, err := scan(row)
	if err == nil {
		if err := r.cursor.Bump(ctx, tx, f.UserID, sync.EntityParserFeedback, result.UpdatedAt); err != nil {
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

	// LWW rejected: return server's current version.
	current, err := r.GetByID(ctx, f.ID, f.UserID)
	if err != nil {
		return nil, false, err
	}
	return current, true, nil
}

// SoftDelete está disponible para retención server-side futura. NO se expone
// como RPC: el cliente nunca borra feedback.
func (r *Repository) SoftDelete(ctx context.Context, id, userID uuid.UUID, deletedAt time.Time) error {
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)

	tag, err := tx.Exec(
		ctx,
		`UPDATE parser_feedback SET deleted_at = $3, updated_at = $3
		 WHERE id = $1 AND user_id = $2
		   AND (deleted_at IS NULL OR updated_at < $3)`,
		id, userID, deletedAt,
	)
	if err != nil {
		return err
	}
	if tag.RowsAffected() > 0 {
		if err := r.cursor.Bump(ctx, tx, userID, sync.EntityParserFeedback, deletedAt); err != nil {
			return err
		}
	}
	return tx.Commit(ctx)
}

// Handler ────────────────────────────────────────────────────────────────────

type Handler struct {
	pb.UnimplementedParserFeedbackServiceServer
	repo *Repository
}

func NewHandler(repo *Repository) *Handler {
	return &Handler{repo: repo}
}

func parseUUID(s, field string) (uuid.UUID, error) {
	id, err := uuid.Parse(s)
	if err != nil {
		return uuid.UUID{}, status.Errorf(codes.InvalidArgument, "invalid %s: %v", field, err)
	}
	return id, nil
}

func parsePage(req *pb.PageRequest) (limit, offset int) {
	limit = 20
	if req == nil {
		return
	}
	if req.PageSize > 0 {
		limit = int(req.PageSize)
		if limit > 100 {
			limit = 100
		}
	}
	if req.PageToken != "" {
		if n, err := strconv.Atoi(req.PageToken); err == nil {
			offset = n
		}
	}
	return
}

func nextPageToken(offset, limit, count int) string {
	if count < limit {
		return ""
	}
	return strconv.Itoa(offset + limit)
}

func toProto(f *Feedback) *pb.ParserFeedback {
	proto := &pb.ParserFeedback{
		Id:                   f.ID.String(),
		PendingTransactionId: f.PendingTransactionID,
		AccountChanged:       f.AccountChanged,
		CategoryChanged:      f.CategoryChanged,
		AmountChanged:        f.AmountChanged,
		DescriptionChanged:   f.DescriptionChanged,
		WasDismissed:         f.WasDismissed,
		CreatedAt:            timestamppb.New(f.CreatedAt),
		UpdatedAt:            timestamppb.New(f.UpdatedAt),
	}
	if f.CapturedNotificationID != nil {
		proto.CapturedNotificationId = *f.CapturedNotificationID
	}
	if f.BankID != nil {
		proto.BankId = *f.BankID
	}
	if f.PatternID != nil {
		proto.PatternId = *f.PatternID
	}
	if f.ParserVersion != nil {
		proto.ParserVersion = *f.ParserVersion
	}
	if f.ExtractionMethod != nil {
		proto.ExtractionMethod = *f.ExtractionMethod
	}
	if f.WasHelpful != nil {
		proto.WasHelpful = wrapperspb.Bool(*f.WasHelpful)
	}
	if f.DeletedAt != nil {
		proto.DeletedAt = timestamppb.New(*f.DeletedAt)
	}
	return proto
}

func fromProto(p *pb.ParserFeedback, f *Feedback) error {
	pendingID := strings.TrimSpace(p.PendingTransactionId)
	if pendingID == "" {
		return status.Error(codes.InvalidArgument, "feedback.pending_transaction_id is required")
	}
	f.PendingTransactionID = pendingID

	if v := strings.TrimSpace(p.CapturedNotificationId); v != "" {
		f.CapturedNotificationID = &v
	}
	if v := strings.TrimSpace(p.BankId); v != "" {
		f.BankID = &v
	}
	if v := strings.TrimSpace(p.PatternId); v != "" {
		f.PatternID = &v
	}
	if p.ParserVersion > 0 {
		v := p.ParserVersion
		f.ParserVersion = &v
	}
	if v := strings.TrimSpace(p.ExtractionMethod); v != "" {
		if v != "local" && v != "llm" {
			return status.Errorf(codes.InvalidArgument, "feedback.extraction_method must be 'local' or 'llm', got %q", v)
		}
		f.ExtractionMethod = &v
	}
	if p.WasHelpful != nil {
		v := p.WasHelpful.Value
		f.WasHelpful = &v
	}

	f.AccountChanged = p.AccountChanged
	f.CategoryChanged = p.CategoryChanged
	f.AmountChanged = p.AmountChanged
	f.DescriptionChanged = p.DescriptionChanged
	f.WasDismissed = p.WasDismissed

	if p.CreatedAt == nil || p.UpdatedAt == nil {
		return status.Error(codes.InvalidArgument, "feedback.created_at and updated_at are required")
	}
	f.CreatedAt = p.CreatedAt.AsTime()
	f.UpdatedAt = p.UpdatedAt.AsTime()
	if p.DeletedAt != nil {
		t := p.DeletedAt.AsTime()
		f.DeletedAt = &t
	}
	return nil
}

func (h *Handler) ListParserFeedback(ctx context.Context, req *pb.ListParserFeedbackRequest) (*pb.ListParserFeedbackResponse, error) {
	userID, err := middleware.UserIDFromCtx(ctx)
	if err != nil {
		return nil, err
	}

	var updatedSince *time.Time
	if req.UpdatedSince != nil {
		t := req.UpdatedSince.AsTime()
		updatedSince = &t
	}

	limit, offset := parsePage(req.Page)
	items, syncedAt, err := h.repo.List(ctx, userID, updatedSince, limit, offset)
	if err != nil {
		return nil, status.Errorf(codes.Internal, "list parser_feedback: %v", err)
	}

	out := make([]*pb.ParserFeedback, len(items))
	for i, f := range items {
		out[i] = toProto(f)
	}

	nextToken := ""
	if updatedSince == nil {
		nextToken = nextPageToken(offset, limit, len(items))
	}

	return &pb.ListParserFeedbackResponse{
		Feedback: out,
		Page:     &pb.PageResponse{NextPageToken: nextToken},
		SyncedAt: timestamppb.New(syncedAt),
	}, nil
}

func (h *Handler) UpsertParserFeedback(ctx context.Context, req *pb.UpsertParserFeedbackRequest) (*pb.UpsertParserFeedbackResponse, error) {
	if req.Feedback == nil {
		return nil, status.Error(codes.InvalidArgument, "feedback is required")
	}

	userID, err := middleware.UserIDFromCtx(ctx)
	if err != nil {
		return nil, err
	}

	id, err := parseUUID(req.Feedback.Id, "feedback.id")
	if err != nil {
		return nil, err
	}

	f := &Feedback{ID: id, UserID: userID}
	if err := fromProto(req.Feedback, f); err != nil {
		return nil, err
	}

	result, conflictResolved, err := h.repo.Upsert(ctx, f)
	if err != nil {
		return nil, status.Errorf(codes.Internal, "upsert parser_feedback: %v", err)
	}

	return &pb.UpsertParserFeedbackResponse{
		Feedback:         toProto(result),
		ConflictResolved: conflictResolved,
	}, nil
}
