// Package cardmapping persiste el mapeo (banco, últimos 4 dígitos) → cuenta
// que aprende automáticamente del flujo de aprobación de PendingTransactions.
//
// El usuario nunca crea estos registros explícitamente: cuando aprueba una
// sugerencia derivada de una notificación bancaria que incluyó dígitos de
// tarjeta, el cliente persiste el mapeo y lo sincroniza para que la siguiente
// notificación llegue ya con la cuenta pre-asignada.
package cardmapping

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
	"google.golang.org/protobuf/types/known/emptypb"
	"google.golang.org/protobuf/types/known/timestamppb"

	pb "github.com/AlanIsaacV/pocket-pilot/internal/gen/proto/pocket_pilot/v1/pocket_pilot/v1"
	"github.com/AlanIsaacV/pocket-pilot/internal/middleware"
	"github.com/AlanIsaacV/pocket-pilot/internal/sync"
)

// Mapping is the domain model. Mirrors the columns of `account_card_mappings`.
type Mapping struct {
	ID         uuid.UUID
	UserID     uuid.UUID
	BankID     string
	LastDigits string
	AccountID  uuid.UUID
	CreatedAt  time.Time
	UpdatedAt  time.Time
	DeletedAt  *time.Time
}

const scanColumns = `id, user_id, bank_id, last_digits, account_id, created_at, updated_at, deleted_at`

func scan(row pgx.Row) (*Mapping, error) {
	m := &Mapping{}
	err := row.Scan(
		&m.ID, &m.UserID, &m.BankID, &m.LastDigits, &m.AccountID,
		&m.CreatedAt, &m.UpdatedAt, &m.DeletedAt,
	)
	if err != nil {
		return nil, err
	}
	return m, nil
}

// Repository ─────────────────────────────────────────────────────────────────

type Repository struct {
	pool   *pgxpool.Pool
	cursor *sync.CursorStore
}

func NewRepository(pool *pgxpool.Pool, cursor *sync.CursorStore) *Repository {
	return &Repository{pool: pool, cursor: cursor}
}

func (r *Repository) GetByID(ctx context.Context, id, userID uuid.UUID) (*Mapping, error) {
	row := r.pool.QueryRow(
		ctx,
		`SELECT `+scanColumns+` FROM account_card_mappings WHERE id = $1 AND user_id = $2`,
		id, userID,
	)
	return scan(row)
}

// List returns mappings for sync. Delta when updatedSince != nil (includes
// soft-deleted), otherwise full list of active rows with pagination.
func (r *Repository) List(ctx context.Context, userID uuid.UUID, updatedSince *time.Time, limit, offset int) ([]*Mapping, time.Time, error) {
	syncedAt := time.Now().UTC()

	var (
		rows pgx.Rows
		err  error
	)
	if updatedSince != nil {
		rows, err = r.pool.Query(
			ctx,
			`SELECT `+scanColumns+`
			 FROM account_card_mappings
			 WHERE user_id = $1 AND updated_at > $2
			 ORDER BY updated_at ASC`,
			userID, updatedSince,
		)
	} else {
		rows, err = r.pool.Query(
			ctx,
			`SELECT `+scanColumns+`
			 FROM account_card_mappings
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

	var items []*Mapping
	for rows.Next() {
		m, err := scan(rows)
		if err != nil {
			return nil, syncedAt, err
		}
		items = append(items, m)
	}
	return items, syncedAt, rows.Err()
}

// Upsert applies LWW. Same id collision → newer updated_at wins. Multiple
// active rows for the same (user_id, bank_id, last_digits) are allowed; the
// resolution at read time picks the most recently updated.
func (r *Repository) Upsert(ctx context.Context, m *Mapping) (*Mapping, bool, error) {
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return nil, false, err
	}
	defer tx.Rollback(ctx)

	row := tx.QueryRow(
		ctx,
		`
		INSERT INTO account_card_mappings (
			id, user_id, bank_id, last_digits, account_id,
			created_at, updated_at, deleted_at
		)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
		ON CONFLICT (id) DO UPDATE SET
			bank_id     = EXCLUDED.bank_id,
			last_digits = EXCLUDED.last_digits,
			account_id  = EXCLUDED.account_id,
			updated_at  = EXCLUDED.updated_at,
			deleted_at  = EXCLUDED.deleted_at
		WHERE account_card_mappings.updated_at < EXCLUDED.updated_at
		RETURNING `+scanColumns,
		m.ID, m.UserID, m.BankID, m.LastDigits, m.AccountID,
		m.CreatedAt, m.UpdatedAt, m.DeletedAt,
	)

	result, err := scan(row)
	if err == nil {
		if err := r.cursor.Bump(ctx, tx, m.UserID, sync.EntityAccountCardMapping, result.UpdatedAt); err != nil {
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
	current, err := r.GetByID(ctx, m.ID, m.UserID)
	if err != nil {
		return nil, false, err
	}
	return current, true, nil
}

func (r *Repository) SoftDelete(ctx context.Context, id, userID uuid.UUID, deletedAt time.Time) error {
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)

	tag, err := tx.Exec(
		ctx,
		`UPDATE account_card_mappings SET deleted_at = $3, updated_at = $3
		 WHERE id = $1 AND user_id = $2
		   AND (deleted_at IS NULL OR updated_at < $3)`,
		id, userID, deletedAt,
	)
	if err != nil {
		return err
	}
	if tag.RowsAffected() > 0 {
		if err := r.cursor.Bump(ctx, tx, userID, sync.EntityAccountCardMapping, deletedAt); err != nil {
			return err
		}
	}
	return tx.Commit(ctx)
}

// Handler ────────────────────────────────────────────────────────────────────

type Handler struct {
	pb.UnimplementedAccountCardMappingServiceServer
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

func toProto(m *Mapping) *pb.AccountCardMapping {
	proto := &pb.AccountCardMapping{
		Id:         m.ID.String(),
		BankId:     m.BankID,
		LastDigits: m.LastDigits,
		AccountId:  m.AccountID.String(),
		CreatedAt:  timestamppb.New(m.CreatedAt),
		UpdatedAt:  timestamppb.New(m.UpdatedAt),
	}
	if m.DeletedAt != nil {
		proto.DeletedAt = timestamppb.New(*m.DeletedAt)
	}
	return proto
}

func fromProto(p *pb.AccountCardMapping, m *Mapping) error {
	bankID := strings.TrimSpace(p.BankId)
	if bankID == "" {
		return status.Error(codes.InvalidArgument, "mapping.bank_id is required")
	}
	digits := strings.TrimSpace(p.LastDigits)
	if !isFourDigits(digits) {
		return status.Error(codes.InvalidArgument, "mapping.last_digits must be 4 numeric digits")
	}
	accountID, err := parseUUID(p.AccountId, "mapping.account_id")
	if err != nil {
		return err
	}
	m.BankID = bankID
	m.LastDigits = digits
	m.AccountID = accountID
	m.CreatedAt = p.CreatedAt.AsTime()
	m.UpdatedAt = p.UpdatedAt.AsTime()
	if p.DeletedAt != nil {
		t := p.DeletedAt.AsTime()
		m.DeletedAt = &t
	}
	return nil
}

func isFourDigits(s string) bool {
	if len(s) != 4 {
		return false
	}
	for _, r := range s {
		if r < '0' || r > '9' {
			return false
		}
	}
	return true
}

func (h *Handler) ListAccountCardMappings(ctx context.Context, req *pb.ListAccountCardMappingsRequest) (*pb.ListAccountCardMappingsResponse, error) {
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
		return nil, status.Errorf(codes.Internal, "list account_card_mappings: %v", err)
	}

	out := make([]*pb.AccountCardMapping, len(items))
	for i, m := range items {
		out[i] = toProto(m)
	}

	nextToken := ""
	if updatedSince == nil {
		nextToken = nextPageToken(offset, limit, len(items))
	}

	return &pb.ListAccountCardMappingsResponse{
		Mappings: out,
		Page:     &pb.PageResponse{NextPageToken: nextToken},
		SyncedAt: timestamppb.New(syncedAt),
	}, nil
}

func (h *Handler) UpsertAccountCardMapping(ctx context.Context, req *pb.UpsertAccountCardMappingRequest) (*pb.UpsertAccountCardMappingResponse, error) {
	if req.Mapping == nil {
		return nil, status.Error(codes.InvalidArgument, "mapping is required")
	}

	userID, err := middleware.UserIDFromCtx(ctx)
	if err != nil {
		return nil, err
	}

	id, err := parseUUID(req.Mapping.Id, "mapping.id")
	if err != nil {
		return nil, err
	}

	m := &Mapping{ID: id, UserID: userID}
	if err := fromProto(req.Mapping, m); err != nil {
		return nil, err
	}

	result, conflictResolved, err := h.repo.Upsert(ctx, m)
	if err != nil {
		return nil, status.Errorf(codes.Internal, "upsert account_card_mapping: %v", err)
	}

	return &pb.UpsertAccountCardMappingResponse{
		Mapping:          toProto(result),
		ConflictResolved: conflictResolved,
	}, nil
}

func (h *Handler) DeleteAccountCardMapping(ctx context.Context, req *pb.DeleteAccountCardMappingRequest) (*emptypb.Empty, error) {
	userID, err := middleware.UserIDFromCtx(ctx)
	if err != nil {
		return nil, err
	}
	id, err := parseUUID(req.Id, "id")
	if err != nil {
		return nil, err
	}

	deletedAt := time.Now().UTC()
	if req.DeletedAt != nil {
		deletedAt = req.DeletedAt.AsTime()
	}

	if err := h.repo.SoftDelete(ctx, id, userID, deletedAt); err != nil {
		return nil, status.Errorf(codes.Internal, "delete account_card_mapping: %v", err)
	}
	return &emptypb.Empty{}, nil
}
