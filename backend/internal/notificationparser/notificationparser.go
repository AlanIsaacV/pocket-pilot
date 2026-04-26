// Package notificationparser persiste el catálogo global de parsers de
// notificaciones bancarias. Es una tabla compartida entre todos los usuarios
// (sin user_id) que se distribuye en modo pull-only: el cliente nunca empuja
// cambios. El operador hace updates server-side (SQL directo o, en Fase 4, un
// admin path) y el cliente recoge la nueva versión en el siguiente sync.
package notificationparser

import (
	"context"
	"encoding/json"
	"errors"
	"strconv"
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

// Parser es el modelo de dominio. Refleja las columnas de notification_parsers.
type Parser struct {
	ID         uuid.UUID
	BankID     string
	Version    int
	Definition json.RawMessage
	IsActive   bool
	CreatedAt  time.Time
	UpdatedAt  time.Time
	DeletedAt  *time.Time
}

const scanColumns = `id, bank_id, version, definition, is_active, created_at, updated_at, deleted_at`

func scan(row pgx.Row) (*Parser, error) {
	p := &Parser{}
	err := row.Scan(
		&p.ID, &p.BankID, &p.Version, &p.Definition, &p.IsActive,
		&p.CreatedAt, &p.UpdatedAt, &p.DeletedAt,
	)
	if err != nil {
		return nil, err
	}
	return p, nil
}

// Repository ─────────────────────────────────────────────────────────────────

// Repository maneja lecturas para todos los usuarios (la tabla es global, sin
// user_id) y escrituras desde el path admin/seed. No hay path de escritura por
// usuario: los clientes nunca empujan parsers.
type Repository struct {
	pool   *pgxpool.Pool
	cursor *sync.CursorStore
}

func NewRepository(pool *pgxpool.Pool, cursor *sync.CursorStore) *Repository {
	return &Repository{pool: pool, cursor: cursor}
}

// List devuelve los parsers para sync. Delta cuando updatedSince != nil
// (incluye soft-deleted e inactivos para que el cliente los retire), o lista
// completa de filas activas paginada cuando updatedSince == nil.
func (r *Repository) List(ctx context.Context, updatedSince *time.Time, limit, offset int) ([]*Parser, time.Time, error) {
	syncedAt := time.Now().UTC()

	var (
		rows pgx.Rows
		err  error
	)
	if updatedSince != nil {
		rows, err = r.pool.Query(
			ctx,
			`SELECT `+scanColumns+`
			 FROM notification_parsers
			 WHERE updated_at > $1
			 ORDER BY updated_at ASC`,
			updatedSince,
		)
	} else {
		rows, err = r.pool.Query(
			ctx,
			`SELECT `+scanColumns+`
			 FROM notification_parsers
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

	var items []*Parser
	for rows.Next() {
		p, err := scan(rows)
		if err != nil {
			return nil, syncedAt, err
		}
		items = append(items, p)
	}
	return items, syncedAt, rows.Err()
}

// GetByBankID es para uso interno (Fase 4: el engine server-side reintenta el
// match antes de invocar el LLM). Devuelve nil, nil si no existe.
func (r *Repository) GetByBankID(ctx context.Context, bankID string) (*Parser, error) {
	row := r.pool.QueryRow(
		ctx,
		`SELECT `+scanColumns+`
		 FROM notification_parsers
		 WHERE bank_id = $1 AND deleted_at IS NULL AND is_active = TRUE`,
		bankID,
	)
	p, err := scan(row)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, nil
	}
	return p, err
}

// Upsert inserta o actualiza por bank_id. Bumpea el cursor de notification_parser
// para todos los usuarios para que GetSyncStatus reporte el cambio. Pensado
// para el admin path / seed; los clientes no lo invocan.
func (r *Repository) Upsert(ctx context.Context, p *Parser) (*Parser, error) {
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return nil, err
	}
	defer tx.Rollback(ctx)

	row := tx.QueryRow(
		ctx,
		`INSERT INTO notification_parsers (
			bank_id, version, definition, is_active
		) VALUES ($1, $2, $3, $4)
		ON CONFLICT (bank_id) DO UPDATE SET
			version    = EXCLUDED.version,
			definition = EXCLUDED.definition,
			is_active  = EXCLUDED.is_active,
			updated_at = NOW(),
			deleted_at = NULL
		RETURNING `+scanColumns,
		p.BankID, p.Version, p.Definition, p.IsActive,
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

// SoftDelete marca el parser como eliminado y bumpea el cursor para todos los
// usuarios.
func (r *Repository) SoftDelete(ctx context.Context, bankID string, deletedAt time.Time) error {
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)

	tag, err := tx.Exec(
		ctx,
		`UPDATE notification_parsers
		   SET deleted_at = $2, updated_at = $2
		 WHERE bank_id = $1 AND (deleted_at IS NULL OR updated_at < $2)`,
		bankID, deletedAt,
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

// bumpAllUsers actualiza el cursor de notification_parser para cada usuario.
// La tabla es global así que todos deben enterarse del cambio. OK para v1
// con < ~10k usuarios; si crece, se reemplaza por un cursor global virtual.
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
		if err := r.cursor.Bump(ctx, tx, id, sync.EntityNotificationParser, at); err != nil {
			return err
		}
	}
	return nil
}

// Handler ────────────────────────────────────────────────────────────────────

// Handler expone ListNotificationParsers (catálogo global, pull-only) y
// ParseNotification (Fase 4: fallback al LLM cuando el cliente no encontró
// un match local). La autenticación se requiere en ambos métodos pero el
// filtro por user no aplica para List (tabla global). ParseNotification sí
// usa el userID para rate-limit por feature='notification_parser'.
type Handler struct {
	pb.UnimplementedNotificationParserServiceServer
	repo          *Repository
	llmFallback   *LLMFallback // nil si no se configuró Fase 4 (deshabilitado)
}

// NewHandler construye el handler en su forma minimal (solo List). Para el
// fallback al LLM usar NewHandlerWithLLM.
func NewHandler(repo *Repository) *Handler {
	return &Handler{repo: repo}
}

// NewHandlerWithLLM extiende NewHandler con la dependencia opcional para
// procesar ParseNotification. Si llm es nil, ParseNotification devolverá
// Unimplemented y el cliente caerá al manejo de errores del Fase 3.5
// existente (la noti queda unparseable).
func NewHandlerWithLLM(repo *Repository, llm *LLMFallback) *Handler {
	return &Handler{repo: repo, llmFallback: llm}
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

func toProto(p *Parser) *pb.NotificationParser {
	out := &pb.NotificationParser{
		BankId:     p.BankID,
		Version:    int32(p.Version),
		Definition: string(p.Definition),
		UpdatedAt:  timestamppb.New(p.UpdatedAt),
	}
	if p.DeletedAt != nil {
		out.DeletedAt = timestamppb.New(*p.DeletedAt)
	}
	return out
}

func (h *Handler) ListNotificationParsers(ctx context.Context, req *pb.ListNotificationParsersRequest) (*pb.ListNotificationParsersResponse, error) {
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
		return nil, status.Errorf(codes.Internal, "list notification_parsers: %v", err)
	}

	out := make([]*pb.NotificationParser, len(items))
	for i, p := range items {
		out[i] = toProto(p)
	}

	nextToken := ""
	if updatedSince == nil {
		nextToken = nextPageToken(offset, limit, len(items))
	}

	return &pb.ListNotificationParsersResponse{
		Parsers:  out,
		Page:     &pb.PageResponse{NextPageToken: nextToken},
		SyncedAt: timestamppb.New(syncedAt),
	}, nil
}
