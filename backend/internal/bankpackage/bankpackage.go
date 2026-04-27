// Package bankpackage persiste el catálogo global de paquetes Android
// considerados bancarios. Es una tabla compartida entre todos los usuarios
// (sin user_id) que se distribuye en modo pull-only: el cliente nunca empuja
// entradas. Las nuevas entradas se agregan vía promoción admin desde
// package_suggestions (ver SuggestionRepository).
//
// Mismo patrón estructural que internal/notificationparser/notificationparser.go.
package bankpackage

import (
	"context"
	"errors"
	"strconv"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
	"google.golang.org/protobuf/types/known/timestamppb"

	pb "github.com/AlanIsaacV/pocket-pilot/internal/gen/proto/pocket_pilot/v1/pocket_pilot/v1"
	"github.com/AlanIsaacV/pocket-pilot/internal/middleware"
	"github.com/AlanIsaacV/pocket-pilot/internal/sync"
)

// Package es el modelo de dominio. Refleja las columnas de bank_packages.
type Package struct {
	ID           uuid.UUID
	PackageName  string
	BankID       string
	DefaultLabel string
	IsActive     bool
	CreatedAt    time.Time
	UpdatedAt    time.Time
	DeletedAt    *time.Time
}

const scanColumns = `id, package_name, bank_id, default_label, is_active, created_at, updated_at, deleted_at`

func scan(row pgx.Row) (*Package, error) {
	p := &Package{}
	err := row.Scan(
		&p.ID, &p.PackageName, &p.BankID, &p.DefaultLabel, &p.IsActive,
		&p.CreatedAt, &p.UpdatedAt, &p.DeletedAt,
	)
	if err != nil {
		return nil, err
	}
	return p, nil
}

// Repository ─────────────────────────────────────────────────────────────────

// Repository maneja lecturas para todos los usuarios (la tabla es global, sin
// user_id) y escrituras desde el path admin. No hay path de escritura por
// usuario: los clientes nunca empujan entradas al catálogo.
type Repository struct {
	pool   *pgxpool.Pool
	cursor *sync.CursorStore
}

func NewRepository(pool *pgxpool.Pool, cursor *sync.CursorStore) *Repository {
	return &Repository{pool: pool, cursor: cursor}
}

// List devuelve las entradas para sync. Delta cuando updatedSince != nil
// (incluye soft-deleted e inactivos), o lista completa de filas activas
// paginada cuando updatedSince == nil.
func (r *Repository) List(ctx context.Context, updatedSince *time.Time, limit, offset int) ([]*Package, time.Time, error) {
	syncedAt := time.Now().UTC()

	var (
		rows pgx.Rows
		err  error
	)
	if updatedSince != nil {
		rows, err = r.pool.Query(
			ctx,
			`SELECT `+scanColumns+`
			 FROM bank_packages
			 WHERE updated_at > $1
			 ORDER BY updated_at ASC`,
			updatedSince,
		)
	} else {
		rows, err = r.pool.Query(
			ctx,
			`SELECT `+scanColumns+`
			 FROM bank_packages
			 WHERE deleted_at IS NULL AND is_active = TRUE
			 ORDER BY updated_at DESC
			 LIMIT $1 OFFSET $2`,
			limit, offset,
		)
	}
	if err != nil {
		return nil, syncedAt, err
	}
	defer rows.Close()

	var items []*Package
	for rows.Next() {
		p, err := scan(rows)
		if err != nil {
			return nil, syncedAt, err
		}
		items = append(items, p)
	}
	return items, syncedAt, rows.Err()
}

// GetByPackageName es para uso interno (ej. el handler de
// SubmitPackageSuggestion lo usa para detectar duplicados antes de insertar).
// Devuelve nil, nil si no existe.
func (r *Repository) GetByPackageName(ctx context.Context, packageName string) (*Package, error) {
	row := r.pool.QueryRow(
		ctx,
		`SELECT `+scanColumns+`
		 FROM bank_packages
		 WHERE package_name = $1 AND deleted_at IS NULL AND is_active = TRUE`,
		packageName,
	)
	p, err := scan(row)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, nil
	}
	return p, err
}

// Upsert inserta o actualiza por package_name. Bumpea el cursor de
// bank_package para todos los usuarios para que GetSyncStatus reporte el
// cambio. Pensado para el admin path / seed; los clientes no lo invocan.
func (r *Repository) Upsert(ctx context.Context, p *Package) (*Package, error) {
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return nil, err
	}
	defer tx.Rollback(ctx)

	row := tx.QueryRow(
		ctx,
		`INSERT INTO bank_packages (
			package_name, bank_id, default_label, is_active
		) VALUES ($1, $2, $3, $4)
		ON CONFLICT (package_name) DO UPDATE SET
			bank_id       = EXCLUDED.bank_id,
			default_label = EXCLUDED.default_label,
			is_active     = EXCLUDED.is_active,
			updated_at    = NOW(),
			deleted_at    = NULL
		RETURNING `+scanColumns,
		p.PackageName, p.BankID, p.DefaultLabel, p.IsActive,
	)
	result, err := scan(row)
	if err != nil {
		return nil, err
	}

	if err := r.bumpAllUsers(ctx, tx, result.UpdatedAt); err != nil {
		return nil, err
	}
	if err := tx.Commit(ctx); err != nil {
		return nil, err
	}
	return result, nil
}

// SoftDelete marca la entrada como eliminada y bumpea el cursor para todos
// los usuarios.
func (r *Repository) SoftDelete(ctx context.Context, packageName string, deletedAt time.Time) error {
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)

	tag, err := tx.Exec(
		ctx,
		`UPDATE bank_packages
		   SET deleted_at = $2, updated_at = $2
		 WHERE package_name = $1 AND (deleted_at IS NULL OR updated_at < $2)`,
		packageName, deletedAt,
	)
	if err != nil {
		return err
	}
	if tag.RowsAffected() > 0 {
		if err := r.bumpAllUsers(ctx, tx, deletedAt); err != nil {
			return err
		}
	}
	return tx.Commit(ctx)
}

// bumpAllUsers actualiza el cursor de bank_package para cada usuario. La
// tabla es global así que todos deben enterarse del cambio. OK para v1 con
// < ~10k usuarios; si crece, se reemplaza por un cursor global virtual.
// Mismo patrón que internal/notificationparser/notificationparser.go.
func (r *Repository) bumpAllUsers(ctx context.Context, tx pgx.Tx, at time.Time) error {
	rows, err := tx.Query(ctx, `SELECT id FROM users`)
	if err != nil {
		return err
	}
	defer rows.Close()

	var ids []uuid.UUID
	for rows.Next() {
		var id uuid.UUID
		if err := rows.Scan(&id); err != nil {
			return err
		}
		ids = append(ids, id)
	}
	if err := rows.Err(); err != nil {
		return err
	}
	for _, id := range ids {
		if err := r.cursor.Bump(ctx, tx, id, sync.EntityBankPackage, at); err != nil {
			return err
		}
	}
	return nil
}

// Handler ────────────────────────────────────────────────────────────────────

// Handler expone ListBankPackages (catálogo global, pull-only) y
// SubmitPackageSuggestion (anónimo, alimenta package_suggestions). La
// autenticación se requiere en ambos métodos (el cliente debe estar logueado)
// pero la suggestion no persiste user_id — el dato se almacena anónimamente.
type Handler struct {
	pb.UnimplementedBankPackageServiceServer
	repo        *Repository
	suggestions *SuggestionRepository
}

func NewHandler(repo *Repository, suggestions *SuggestionRepository) *Handler {
	return &Handler{repo: repo, suggestions: suggestions}
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

func toProto(p *Package) *pb.BankPackage {
	out := &pb.BankPackage{
		PackageName:  p.PackageName,
		BankId:       p.BankID,
		DefaultLabel: p.DefaultLabel,
		UpdatedAt:    timestamppb.New(p.UpdatedAt),
	}
	if p.DeletedAt != nil {
		out.DeletedAt = timestamppb.New(*p.DeletedAt)
	}
	return out
}

func (h *Handler) ListBankPackages(ctx context.Context, req *pb.ListBankPackagesRequest) (*pb.ListBankPackagesResponse, error) {
	if _, err := middleware.UserIDFromCtx(ctx); err != nil {
		return nil, err
	}

	var updatedSince *time.Time
	if req.UpdatedSince != nil {
		t := req.UpdatedSince.AsTime()
		updatedSince = &t
	}

	limit, offset := parsePage(req.Page)
	items, syncedAt, err := h.repo.List(ctx, updatedSince, limit, offset)
	if err != nil {
		return nil, status.Errorf(codes.Internal, "list bank_packages: %v", err)
	}

	out := make([]*pb.BankPackage, len(items))
	for i, p := range items {
		out[i] = toProto(p)
	}

	nextToken := ""
	if updatedSince == nil {
		nextToken = nextPageToken(offset, limit, len(items))
	}

	return &pb.ListBankPackagesResponse{
		Packages: out,
		Page:     &pb.PageResponse{NextPageToken: nextToken},
		SyncedAt: timestamppb.New(syncedAt),
	}, nil
}

func (h *Handler) SubmitPackageSuggestion(ctx context.Context, req *pb.SubmitPackageSuggestionRequest) (*pb.SubmitPackageSuggestionResponse, error) {
	// Auth requerida pero NO persistimos user_id — el handler la valida solo
	// para evitar que cualquier IP envíe ruido al backend.
	if _, err := middleware.UserIDFromCtx(ctx); err != nil {
		return nil, err
	}

	pkg := strings.TrimSpace(req.PackageName)
	if pkg == "" {
		return nil, status.Error(codes.InvalidArgument, "package_name is required")
	}
	label := strings.TrimSpace(req.ProposedLabel)
	if label == "" {
		return nil, status.Error(codes.InvalidArgument, "proposed_label is required")
	}
	bankID := strings.TrimSpace(req.ProposedBankId)

	id, err := h.suggestions.Insert(ctx, Suggestion{
		PackageName:    pkg,
		ProposedBankID: bankID,
		ProposedLabel:  label,
	})
	if err != nil {
		return nil, status.Errorf(codes.Internal, "insert package_suggestion: %v", err)
	}

	return &pb.SubmitPackageSuggestionResponse{
		SuggestionId: id.String(),
	}, nil
}
