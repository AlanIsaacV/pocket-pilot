// Package txrule persiste reglas substring → categoría que aprenden del flujo
// de aprobación de PendingTransactions.
//
// Aplica también (a futuro) a CSV import y la AI assistant tool: cualquier
// transacción cuya descripción contenga (case-insensitive) `match_text` puede
// pre-completar su categoría con `category_id`.
package txrule

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

type Rule struct {
	ID         uuid.UUID
	UserID     uuid.UUID
	MatchText  string
	CategoryID uuid.UUID
	Priority   int32
	MatchCount int32
	CreatedAt  time.Time
	UpdatedAt  time.Time
	DeletedAt  *time.Time
}

const scanColumns = `id, user_id, match_text, category_id, priority, match_count, created_at, updated_at, deleted_at`

func scan(row pgx.Row) (*Rule, error) {
	r := &Rule{}
	err := row.Scan(
		&r.ID, &r.UserID, &r.MatchText, &r.CategoryID, &r.Priority, &r.MatchCount,
		&r.CreatedAt, &r.UpdatedAt, &r.DeletedAt,
	)
	if err != nil {
		return nil, err
	}
	return r, nil
}

// Repository ─────────────────────────────────────────────────────────────────

type Repository struct {
	pool   *pgxpool.Pool
	cursor *sync.CursorStore
}

func NewRepository(pool *pgxpool.Pool, cursor *sync.CursorStore) *Repository {
	return &Repository{pool: pool, cursor: cursor}
}

func (r *Repository) GetByID(ctx context.Context, id, userID uuid.UUID) (*Rule, error) {
	row := r.pool.QueryRow(
		ctx,
		`SELECT `+scanColumns+` FROM transaction_rules WHERE id = $1 AND user_id = $2`,
		id, userID,
	)
	return scan(row)
}

func (r *Repository) List(ctx context.Context, userID uuid.UUID, updatedSince *time.Time, limit, offset int) ([]*Rule, time.Time, error) {
	syncedAt := time.Now().UTC()

	var (
		rows pgx.Rows
		err  error
	)
	if updatedSince != nil {
		rows, err = r.pool.Query(
			ctx,
			`SELECT `+scanColumns+`
			 FROM transaction_rules
			 WHERE user_id = $1 AND updated_at > $2
			 ORDER BY updated_at ASC`,
			userID, updatedSince,
		)
	} else {
		rows, err = r.pool.Query(
			ctx,
			`SELECT `+scanColumns+`
			 FROM transaction_rules
			 WHERE user_id = $1 AND deleted_at IS NULL
			 ORDER BY priority DESC, updated_at DESC
			 LIMIT $2 OFFSET $3`,
			userID, limit, offset,
		)
	}
	if err != nil {
		return nil, syncedAt, err
	}
	defer rows.Close()

	var items []*Rule
	for rows.Next() {
		ru, err := scan(rows)
		if err != nil {
			return nil, syncedAt, err
		}
		items = append(items, ru)
	}
	return items, syncedAt, rows.Err()
}

func (r *Repository) Upsert(ctx context.Context, ru *Rule) (*Rule, bool, error) {
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return nil, false, err
	}
	defer tx.Rollback(ctx)

	row := tx.QueryRow(
		ctx,
		`
		INSERT INTO transaction_rules (
			id, user_id, match_text, category_id, priority, match_count,
			created_at, updated_at, deleted_at
		)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
		ON CONFLICT (id) DO UPDATE SET
			match_text  = EXCLUDED.match_text,
			category_id = EXCLUDED.category_id,
			priority    = EXCLUDED.priority,
			match_count = EXCLUDED.match_count,
			updated_at  = EXCLUDED.updated_at,
			deleted_at  = EXCLUDED.deleted_at
		WHERE transaction_rules.updated_at < EXCLUDED.updated_at
		RETURNING `+scanColumns,
		ru.ID, ru.UserID, ru.MatchText, ru.CategoryID, ru.Priority, ru.MatchCount,
		ru.CreatedAt, ru.UpdatedAt, ru.DeletedAt,
	)

	result, err := scan(row)
	if err == nil {
		if err := r.cursor.Bump(ctx, tx, ru.UserID, sync.EntityTransactionRule, result.UpdatedAt); err != nil {
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

	current, err := r.GetByID(ctx, ru.ID, ru.UserID)
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
		`UPDATE transaction_rules SET deleted_at = $3, updated_at = $3
		 WHERE id = $1 AND user_id = $2
		   AND (deleted_at IS NULL OR updated_at < $3)`,
		id, userID, deletedAt,
	)
	if err != nil {
		return err
	}
	if tag.RowsAffected() > 0 {
		if err := r.cursor.Bump(ctx, tx, userID, sync.EntityTransactionRule, deletedAt); err != nil {
			return err
		}
	}
	return tx.Commit(ctx)
}

// Handler ────────────────────────────────────────────────────────────────────

type Handler struct {
	pb.UnimplementedTransactionRuleServiceServer
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

func toProto(r *Rule) *pb.TransactionRule {
	proto := &pb.TransactionRule{
		Id:         r.ID.String(),
		MatchText:  r.MatchText,
		CategoryId: r.CategoryID.String(),
		Priority:   r.Priority,
		MatchCount: r.MatchCount,
		CreatedAt:  timestamppb.New(r.CreatedAt),
		UpdatedAt:  timestamppb.New(r.UpdatedAt),
	}
	if r.DeletedAt != nil {
		proto.DeletedAt = timestamppb.New(*r.DeletedAt)
	}
	return proto
}

func fromProto(p *pb.TransactionRule, r *Rule) error {
	matchText := strings.TrimSpace(p.MatchText)
	if matchText == "" {
		return status.Error(codes.InvalidArgument, "rule.match_text is required")
	}
	categoryID, err := parseUUID(p.CategoryId, "rule.category_id")
	if err != nil {
		return err
	}
	r.MatchText = matchText
	r.CategoryID = categoryID
	r.Priority = p.Priority
	r.MatchCount = p.MatchCount
	r.CreatedAt = p.CreatedAt.AsTime()
	r.UpdatedAt = p.UpdatedAt.AsTime()
	if p.DeletedAt != nil {
		t := p.DeletedAt.AsTime()
		r.DeletedAt = &t
	}
	return nil
}

func (h *Handler) ListTransactionRules(ctx context.Context, req *pb.ListTransactionRulesRequest) (*pb.ListTransactionRulesResponse, error) {
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
		return nil, status.Errorf(codes.Internal, "list transaction_rules: %v", err)
	}

	out := make([]*pb.TransactionRule, len(items))
	for i, r := range items {
		out[i] = toProto(r)
	}

	nextToken := ""
	if updatedSince == nil {
		nextToken = nextPageToken(offset, limit, len(items))
	}

	return &pb.ListTransactionRulesResponse{
		Rules:    out,
		Page:     &pb.PageResponse{NextPageToken: nextToken},
		SyncedAt: timestamppb.New(syncedAt),
	}, nil
}

func (h *Handler) UpsertTransactionRule(ctx context.Context, req *pb.UpsertTransactionRuleRequest) (*pb.UpsertTransactionRuleResponse, error) {
	if req.Rule == nil {
		return nil, status.Error(codes.InvalidArgument, "rule is required")
	}

	userID, err := middleware.UserIDFromCtx(ctx)
	if err != nil {
		return nil, err
	}

	id, err := parseUUID(req.Rule.Id, "rule.id")
	if err != nil {
		return nil, err
	}

	r := &Rule{ID: id, UserID: userID}
	if err := fromProto(req.Rule, r); err != nil {
		return nil, err
	}

	result, conflictResolved, err := h.repo.Upsert(ctx, r)
	if err != nil {
		return nil, status.Errorf(codes.Internal, "upsert transaction_rule: %v", err)
	}

	return &pb.UpsertTransactionRuleResponse{
		Rule:             toProto(result),
		ConflictResolved: conflictResolved,
	}, nil
}

func (h *Handler) DeleteTransactionRule(ctx context.Context, req *pb.DeleteTransactionRuleRequest) (*emptypb.Empty, error) {
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
		return nil, status.Errorf(codes.Internal, "delete transaction_rule: %v", err)
	}
	return &emptypb.Empty{}, nil
}
