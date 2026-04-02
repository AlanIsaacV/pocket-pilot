package goal

import (
	"context"
	"strconv"
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
	pb.UnimplementedGoalServiceServer
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

func parseDateOnly(value string) (time.Time, error) {
	t, err := time.Parse("2006-01-02", value)
	if err != nil {
		return time.Time{}, status.Error(codes.InvalidArgument, "invalid target_date: must be YYYY-MM-DD")
	}
	return dateOnly(t), nil
}

func toProto(g *Goal) *pb.Goal {
	proto := &pb.Goal{
		Id:                g.ID.String(),
		Name:              g.Name,
		TargetAmountCents: g.TargetAmountCents,
		SavedAmountCents:  g.SavedAmountCents,
		TargetDate:        dateOnly(g.TargetDate).Format("2006-01-02"),
		CreatedAt:         timestamppb.New(g.CreatedAt),
		UpdatedAt:         timestamppb.New(g.UpdatedAt),
	}
	if g.DeletedAt != nil {
		proto.DeletedAt = timestamppb.New(*g.DeletedAt)
	}
	return proto
}

func fromProto(p *pb.Goal, userID uuid.UUID) (*Goal, error) {
	id, err := parseUUID(p.Id, "goal.id")
	if err != nil {
		return nil, err
	}

	targetDate, err := parseDateOnly(p.TargetDate)
	if err != nil {
		return nil, err
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

	return &Goal{
		ID:                id,
		UserID:            userID,
		Name:              normalizeName(p.Name),
		TargetAmountCents: p.TargetAmountCents,
		SavedAmountCents:  p.SavedAmountCents,
		TargetDate:        targetDate,
		CreatedAt:         createdAt,
		UpdatedAt:         updatedAt,
		DeletedAt:         deletedAt,
	}, nil
}

func (h *Handler) ListGoals(ctx context.Context, req *pb.ListGoalsRequest) (*pb.ListGoalsResponse, error) {
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

	goals, syncedAt, err := h.repo.List(ctx, userID, updatedSince, limit, offset)
	if err != nil {
		return nil, status.Errorf(codes.Internal, "list goals: %v", err)
	}

	pbGoals := make([]*pb.Goal, len(goals))
	for i, g := range goals {
		pbGoals[i] = toProto(g)
	}

	nextToken := ""
	if updatedSince == nil {
		nextToken = nextPageToken(offset, limit, len(goals))
	}

	return &pb.ListGoalsResponse{
		Goals:    pbGoals,
		Page:     &pb.PageResponse{NextPageToken: nextToken},
		SyncedAt: timestamppb.New(syncedAt),
	}, nil
}

func (h *Handler) UpsertGoal(ctx context.Context, req *pb.UpsertGoalRequest) (*pb.UpsertGoalResponse, error) {
	if req.Goal == nil {
		return nil, status.Error(codes.InvalidArgument, "goal is required")
	}

	userID, err := middleware.UserIDFromCtx(ctx)
	if err != nil {
		return nil, err
	}

	g, err := fromProto(req.Goal, userID)
	if err != nil {
		return nil, err
	}

	if err := ValidateGoal(*g); err != nil {
		return nil, status.Errorf(codes.InvalidArgument, "invalid goal: %v", err)
	}

	result, conflictResolved, err := h.repo.Upsert(ctx, g)
	if err != nil {
		return nil, status.Errorf(codes.Internal, "upsert goal: %v", err)
	}

	return &pb.UpsertGoalResponse{
		Goal:             toProto(result),
		ConflictResolved: conflictResolved,
	}, nil
}

func (h *Handler) DeleteGoal(ctx context.Context, req *pb.DeleteGoalRequest) (*emptypb.Empty, error) {
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
		return nil, status.Errorf(codes.Internal, "delete goal: %v", err)
	}

	return &emptypb.Empty{}, nil
}
