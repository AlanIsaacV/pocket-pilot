package yieldconfig

import (
	"context"
	"strconv"
	"time"

	"github.com/google/uuid"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
	"google.golang.org/protobuf/types/known/emptypb"
	"google.golang.org/protobuf/types/known/timestamppb"

	pb "github.com/AlanIsaacV/pocket-pilot/internal/gen/proto/pocket_pilot/v1/pocket_pilot/v1"
	"github.com/AlanIsaacV/pocket-pilot/internal/middleware"
)

type Handler struct {
	pb.UnimplementedYieldConfigServiceServer
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

func parseDateOnly(value string, field string) (time.Time, error) {
	t, err := time.Parse("2006-01-02", value)
	if err != nil {
		return time.Time{}, status.Errorf(codes.InvalidArgument, "invalid %s: must be YYYY-MM-DD", field)
	}
	return dateOnly(t), nil
}

func toProto(cfg *YieldConfig) *pb.YieldConfig {
	proto := &pb.YieldConfig{
		Id:              cfg.ID.String(),
		AccountId:       cfg.AccountID.String(),
		Name:            cfg.Name,
		AmountCents:     cfg.AmountCents,
		ApyRate:         cfg.ApyRate,
		PayoutFrequency: normalizeLower(cfg.PayoutFrequency),
		NextDate:        dateOnly(cfg.NextDate).Format("2006-01-02"),
		AutoRenew:       cfg.AutoRenew,
		Status:          normalizeLower(cfg.Status),
		CreatedAt:       timestamppb.New(cfg.CreatedAt),
		UpdatedAt:       timestamppb.New(cfg.UpdatedAt),
	}
	if cfg.MaturityDate != nil {
		v := dateOnly(*cfg.MaturityDate).Format("2006-01-02")
		proto.MaturityDate = &v
	}
	if cfg.TermDays != nil {
		v := *cfg.TermDays
		proto.TermDays = &v
	}
	if cfg.DeletedAt != nil {
		proto.DeletedAt = timestamppb.New(*cfg.DeletedAt)
	}
	return proto
}

func fromProto(p *pb.YieldConfig, userID uuid.UUID) (*YieldConfig, error) {
	id, err := parseUUID(p.Id, "config.id")
	if err != nil {
		return nil, err
	}

	accountID, err := parseUUID(p.AccountId, "config.account_id")
	if err != nil {
		return nil, err
	}

	nextDate, err := parseDateOnly(p.NextDate, "config.next_date")
	if err != nil {
		return nil, err
	}

	var maturityDate *time.Time
	if p.MaturityDate != nil && *p.MaturityDate != "" {
		parsed, err := parseDateOnly(*p.MaturityDate, "config.maturity_date")
		if err != nil {
			return nil, err
		}
		maturityDate = &parsed
	}

	var termDays *int32
	if p.TermDays != nil {
		v := *p.TermDays
		termDays = &v
	}

	createdAt := time.Now().UTC()
	if p.CreatedAt != nil {
		createdAt = p.CreatedAt.AsTime().UTC()
	}

	updatedAt := time.Now().UTC()
	if p.UpdatedAt != nil {
		updatedAt = p.UpdatedAt.AsTime().UTC()
	}

	return &YieldConfig{
		ID:              id,
		UserID:          userID,
		AccountID:       accountID,
		Name:            p.Name,
		AmountCents:     p.AmountCents,
		ApyRate:         p.ApyRate,
		PayoutFrequency: normalizeLower(p.PayoutFrequency),
		NextDate:        nextDate,
		MaturityDate:    maturityDate,
		TermDays:        termDays,
		AutoRenew:       p.AutoRenew,
		Status:          normalizeLower(p.Status),
		CreatedAt:       createdAt,
		UpdatedAt:       updatedAt,
	}, nil
}

func (h *Handler) ListYieldConfigs(ctx context.Context, req *pb.ListYieldConfigsRequest) (*pb.ListYieldConfigsResponse, error) {
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
		return nil, status.Errorf(codes.Internal, "list yield configs: %v", err)
	}

	pbItems := make([]*pb.YieldConfig, len(items))
	for i, cfg := range items {
		pbItems[i] = toProto(cfg)
	}

	nextToken := ""
	if updatedSince == nil {
		nextToken = nextPageToken(offset, limit, len(items))
	}

	return &pb.ListYieldConfigsResponse{
		Configs:  pbItems,
		Page:     &pb.PageResponse{NextPageToken: nextToken},
		SyncedAt: timestamppb.New(syncedAt),
	}, nil
}

func (h *Handler) UpsertYieldConfig(ctx context.Context, req *pb.UpsertYieldConfigRequest) (*pb.UpsertYieldConfigResponse, error) {
	if req.Config == nil {
		return nil, status.Error(codes.InvalidArgument, "config is required")
	}

	userID, err := middleware.UserIDFromCtx(ctx)
	if err != nil {
		return nil, err
	}

	cfg, err := fromProto(req.Config, userID)
	if err != nil {
		return nil, err
	}

	if err := ValidateYieldConfig(*cfg); err != nil {
		return nil, status.Errorf(codes.InvalidArgument, "invalid yield config: %v", err)
	}

	result, conflictResolved, err := h.repo.Upsert(ctx, cfg)
	if err != nil {
		return nil, status.Errorf(codes.Internal, "upsert yield config: %v", err)
	}

	return &pb.UpsertYieldConfigResponse{
		Config:           toProto(result),
		ConflictResolved: conflictResolved,
	}, nil
}

func (h *Handler) DeleteYieldConfig(ctx context.Context, req *pb.DeleteYieldConfigRequest) (*emptypb.Empty, error) {
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
		return nil, status.Errorf(codes.Internal, "delete yield config: %v", err)
	}

	return &emptypb.Empty{}, nil
}
