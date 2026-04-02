package budget

import (
	"context"
	"strconv"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
	"google.golang.org/protobuf/types/known/emptypb"
	"google.golang.org/protobuf/types/known/timestamppb"

	pb "github.com/AlanIsaacV/pocket-pilot/internal/gen/proto/pocket_pilot/v1/pocket_pilot/v1"
	"github.com/AlanIsaacV/pocket-pilot/internal/middleware"
)

type Handler struct {
	pb.UnimplementedBudgetServiceServer
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

func toProto(b *Budget) *pb.Budget {
	proto := &pb.Budget{
		Id:               b.ID.String(),
		CategoryId:       b.CategoryID.String(),
		LimitAmountCents: b.LimitAmountCents,
		CurrencyCode:     b.CurrencyCode,
		Period:           b.Period,
		CreatedAt:        timestamppb.New(b.CreatedAt),
		UpdatedAt:        timestamppb.New(b.UpdatedAt),
	}
	if b.DeletedAt != nil {
		proto.DeletedAt = timestamppb.New(*b.DeletedAt)
	}
	return proto
}

func fromProto(p *pb.Budget, userID uuid.UUID) (*Budget, error) {
	id, err := parseUUID(p.Id, "budget.id")
	if err != nil {
		return nil, err
	}

	categoryID, err := parseUUID(p.CategoryId, "budget.category_id")
	if err != nil {
		return nil, err
	}

	currencyCode := strings.ToUpper(strings.TrimSpace(p.CurrencyCode))
	if currencyCode == "" {
		return nil, status.Error(codes.InvalidArgument, "budget.currency_code is required")
	}

	period := normalizePeriod(p.Period)
	if period != "MONTHLY" && period != "YEARLY" {
		return nil, status.Error(codes.InvalidArgument, "budget.period must be MONTHLY or YEARLY")
	}

	createdAt := time.Now().UTC()
	if p.CreatedAt != nil {
		createdAt = p.CreatedAt.AsTime().UTC()
	}

	updatedAt := time.Now().UTC()
	if p.UpdatedAt != nil {
		updatedAt = p.UpdatedAt.AsTime().UTC()
	}

	var deletedAt *time.Time
	if p.DeletedAt != nil {
		t := p.DeletedAt.AsTime().UTC()
		deletedAt = &t
	}

	return &Budget{
		ID:               id,
		UserID:           userID,
		CategoryID:       categoryID,
		LimitAmountCents: p.LimitAmountCents,
		CurrencyCode:     currencyCode,
		Period:           period,
		CreatedAt:        createdAt,
		UpdatedAt:        updatedAt,
		DeletedAt:        deletedAt,
	}, nil
}

func (h *Handler) ListBudgets(ctx context.Context, req *pb.ListBudgetsRequest) (*pb.ListBudgetsResponse, error) {
	userID, err := middleware.UserIDFromCtx(ctx)
	if err != nil {
		return nil, err
	}

	var updatedSince *time.Time
	if req.UpdatedSince != nil {
		t := req.UpdatedSince.AsTime().UTC()
		updatedSince = &t
	}

	limit, offset := parsePage(req.Page)
	if updatedSince != nil {
		limit, offset = parsePage(nil)
	}

	budgets, syncedAt, err := h.repo.List(ctx, userID, updatedSince, limit, offset)
	if err != nil {
		return nil, status.Errorf(codes.Internal, "list budgets: %v", err)
	}

	pbBudgets := make([]*pb.Budget, len(budgets))
	for i, b := range budgets {
		pbBudgets[i] = toProto(b)
	}

	nextToken := ""
	if updatedSince == nil {
		nextToken = nextPageToken(offset, limit, len(budgets))
	}

	return &pb.ListBudgetsResponse{
		Budgets:  pbBudgets,
		Page:     &pb.PageResponse{NextPageToken: nextToken},
		SyncedAt: timestamppb.New(syncedAt),
	}, nil
}

func (h *Handler) UpsertBudget(ctx context.Context, req *pb.UpsertBudgetRequest) (*pb.UpsertBudgetResponse, error) {
	if req.Budget == nil {
		return nil, status.Error(codes.InvalidArgument, "budget is required")
	}

	userID, err := middleware.UserIDFromCtx(ctx)
	if err != nil {
		return nil, err
	}

	b, err := fromProto(req.Budget, userID)
	if err != nil {
		return nil, err
	}

	if err := ValidateBudget(*b); err != nil {
		return nil, status.Errorf(codes.InvalidArgument, "invalid budget: %v", err)
	}

	result, conflictResolved, err := h.repo.Upsert(ctx, b)
	if err != nil {
		return nil, status.Errorf(codes.Internal, "upsert budget: %v", err)
	}

	return &pb.UpsertBudgetResponse{
		Budget:           toProto(result),
		ConflictResolved: conflictResolved,
	}, nil
}

func (h *Handler) DeleteBudget(ctx context.Context, req *pb.DeleteBudgetRequest) (*emptypb.Empty, error) {
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
		deletedAt = req.DeletedAt.AsTime().UTC()
	}

	if err := h.repo.SoftDelete(ctx, id, userID, deletedAt); err != nil {
		if err == pgx.ErrNoRows {
			return &emptypb.Empty{}, nil
		}
		return nil, status.Errorf(codes.Internal, "delete budget: %v", err)
	}

	return &emptypb.Empty{}, nil
}
