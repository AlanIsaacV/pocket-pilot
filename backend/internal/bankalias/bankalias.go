// Package bankalias persiste el alias per-user de un package Android marcado
// como banco. Sincronizable (push+pull, LWW) — mismo patrón que
// internal/cardmapping/cardmapping.go.
//
// Diseño Fase 8:
//   - watched_packages (FE-only) decide qué packages procesa el NLS Kotlin
//     en cada device. Es per-device.
//   - bank_aliases (esta entidad) decide qué nombre/bank_id le da el usuario
//     al package, sincronizado entre devices del mismo usuario.
//
// bank_id es opcional: si el package está en bank_packages global, el
// cliente lo prefilla; si no, queda NULL y el alias queda libre (display-only,
// sin pickup automático de parser).
package bankalias

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

// Alias is the domain model. Mirrors bank_aliases columns.
type Alias struct {
	ID           uuid.UUID
	UserID       uuid.UUID
	PackageName  string
	BankID       *string // nullable
	DisplayLabel string
	CreatedAt    time.Time
	UpdatedAt    time.Time
	DeletedAt    *time.Time
}

const scanColumns = `id, user_id, package_name, bank_id, display_label, created_at, updated_at, deleted_at`

func scan(row pgx.Row) (*Alias, error) {
	a := &Alias{}
	err := row.Scan(
		&a.ID, &a.UserID, &a.PackageName, &a.BankID, &a.DisplayLabel,
		&a.CreatedAt, &a.UpdatedAt, &a.DeletedAt,
	)
	if err != nil {
		return nil, err
	}
	return a, nil
}

// Repository ─────────────────────────────────────────────────────────────────

type Repository struct {
	pool   *pgxpool.Pool
	cursor *sync.CursorStore
}

func NewRepository(pool *pgxpool.Pool, cursor *sync.CursorStore) *Repository {
	return &Repository{pool: pool, cursor: cursor}
}

func (r *Repository) GetByID(ctx context.Context, id, userID uuid.UUID) (*Alias, error) {
	row := r.pool.QueryRow(
		ctx,
		`SELECT `+scanColumns+` FROM bank_aliases WHERE id = $1 AND user_id = $2`,
		id, userID,
	)
	return scan(row)
}

// List returns aliases for sync. Delta when updatedSince != nil (includes
// soft-deleted), otherwise full list of active rows with pagination.
func (r *Repository) List(ctx context.Context, userID uuid.UUID, updatedSince *time.Time, limit, offset int) ([]*Alias, time.Time, error) {
	syncedAt := time.Now().UTC()

	var (
		rows pgx.Rows
		err  error
	)
	if updatedSince != nil {
		rows, err = r.pool.Query(
			ctx,
			`SELECT `+scanColumns+`
			 FROM bank_aliases
			 WHERE user_id = $1 AND updated_at > $2
			 ORDER BY updated_at ASC`,
			userID, updatedSince,
		)
	} else {
		rows, err = r.pool.Query(
			ctx,
			`SELECT `+scanColumns+`
			 FROM bank_aliases
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

	var items []*Alias
	for rows.Next() {
		a, err := scan(rows)
		if err != nil {
			return nil, syncedAt, err
		}
		items = append(items, a)
	}
	return items, syncedAt, rows.Err()
}

// Upsert applies LWW. Same id collision → newer updated_at wins. La
// constraint UNIQUE (user_id, package_name) se respeta: si el cliente cambia
// el alias para el mismo package, debe usar el mismo id (igual que
// cardmapping).
func (r *Repository) Upsert(ctx context.Context, a *Alias) (*Alias, bool, error) {
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return nil, false, err
	}
	defer tx.Rollback(ctx)

	row := tx.QueryRow(
		ctx,
		`
		INSERT INTO bank_aliases (
			id, user_id, package_name, bank_id, display_label,
			created_at, updated_at, deleted_at
		)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
		ON CONFLICT (id) DO UPDATE SET
			package_name  = EXCLUDED.package_name,
			bank_id       = EXCLUDED.bank_id,
			display_label = EXCLUDED.display_label,
			updated_at    = EXCLUDED.updated_at,
			deleted_at    = EXCLUDED.deleted_at
		WHERE bank_aliases.updated_at < EXCLUDED.updated_at
		RETURNING `+scanColumns,
		a.ID, a.UserID, a.PackageName, a.BankID, a.DisplayLabel,
		a.CreatedAt, a.UpdatedAt, a.DeletedAt,
	)

	result, err := scan(row)
	if err == nil {
		if err := r.cursor.Bump(ctx, tx, a.UserID, sync.EntityBankAlias, result.UpdatedAt); err != nil {
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
	current, err := r.GetByID(ctx, a.ID, a.UserID)
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
		`UPDATE bank_aliases SET deleted_at = $3, updated_at = $3
		 WHERE id = $1 AND user_id = $2
		   AND (deleted_at IS NULL OR updated_at < $3)`,
		id, userID, deletedAt,
	)
	if err != nil {
		return err
	}
	if tag.RowsAffected() > 0 {
		if err := r.cursor.Bump(ctx, tx, userID, sync.EntityBankAlias, deletedAt); err != nil {
			return err
		}
	}
	return tx.Commit(ctx)
}

// Handler ────────────────────────────────────────────────────────────────────

type Handler struct {
	pb.UnimplementedBankAliasServiceServer
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

func toProto(a *Alias) *pb.BankAlias {
	out := &pb.BankAlias{
		Id:           a.ID.String(),
		PackageName:  a.PackageName,
		DisplayLabel: a.DisplayLabel,
		CreatedAt:    timestamppb.New(a.CreatedAt),
		UpdatedAt:    timestamppb.New(a.UpdatedAt),
	}
	if a.BankID != nil {
		out.BankId = *a.BankID
	}
	if a.DeletedAt != nil {
		out.DeletedAt = timestamppb.New(*a.DeletedAt)
	}
	return out
}

func fromProto(p *pb.BankAlias, a *Alias) error {
	pkg := strings.TrimSpace(p.PackageName)
	if pkg == "" {
		return status.Error(codes.InvalidArgument, "alias.package_name is required")
	}
	label := strings.TrimSpace(p.DisplayLabel)
	if label == "" {
		return status.Error(codes.InvalidArgument, "alias.display_label is required")
	}

	a.PackageName = pkg
	a.DisplayLabel = label
	bankID := strings.TrimSpace(p.BankId)
	if bankID == "" {
		a.BankID = nil
	} else {
		a.BankID = &bankID
	}
	a.CreatedAt = p.CreatedAt.AsTime()
	a.UpdatedAt = p.UpdatedAt.AsTime()
	if p.DeletedAt != nil {
		t := p.DeletedAt.AsTime()
		a.DeletedAt = &t
	}
	return nil
}

func (h *Handler) ListBankAliases(ctx context.Context, req *pb.ListBankAliasesRequest) (*pb.ListBankAliasesResponse, error) {
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
		return nil, status.Errorf(codes.Internal, "list bank_aliases: %v", err)
	}

	out := make([]*pb.BankAlias, len(items))
	for i, a := range items {
		out[i] = toProto(a)
	}

	nextToken := ""
	if updatedSince == nil {
		nextToken = nextPageToken(offset, limit, len(items))
	}

	return &pb.ListBankAliasesResponse{
		Aliases:  out,
		Page:     &pb.PageResponse{NextPageToken: nextToken},
		SyncedAt: timestamppb.New(syncedAt),
	}, nil
}

func (h *Handler) UpsertBankAlias(ctx context.Context, req *pb.UpsertBankAliasRequest) (*pb.UpsertBankAliasResponse, error) {
	if req.Alias == nil {
		return nil, status.Error(codes.InvalidArgument, "alias is required")
	}

	userID, err := middleware.UserIDFromCtx(ctx)
	if err != nil {
		return nil, err
	}

	id, err := parseUUID(req.Alias.Id, "alias.id")
	if err != nil {
		return nil, err
	}

	a := &Alias{ID: id, UserID: userID}
	if err := fromProto(req.Alias, a); err != nil {
		return nil, err
	}

	result, conflictResolved, err := h.repo.Upsert(ctx, a)
	if err != nil {
		return nil, status.Errorf(codes.Internal, "upsert bank_alias: %v", err)
	}

	return &pb.UpsertBankAliasResponse{
		Alias:            toProto(result),
		ConflictResolved: conflictResolved,
	}, nil
}

func (h *Handler) DeleteBankAlias(ctx context.Context, req *pb.DeleteBankAliasRequest) (*emptypb.Empty, error) {
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
		return nil, status.Errorf(codes.Internal, "delete bank_alias: %v", err)
	}
	return &emptypb.Empty{}, nil
}
