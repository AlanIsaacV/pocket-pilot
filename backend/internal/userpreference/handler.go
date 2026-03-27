package userpreference

import (
	"context"
	"strconv"
	"strings"
	"time"

	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
	"google.golang.org/protobuf/types/known/emptypb"
	"google.golang.org/protobuf/types/known/timestamppb"

	pb "github.com/AlanIsaacV/pocket-pilot/internal/gen/proto/pocket_pilot/v1/pocket_pilot/v1"
	"github.com/AlanIsaacV/pocket-pilot/internal/middleware"
)

type Handler struct {
	pb.UnimplementedUserPreferenceServiceServer
	repo *Repository
}

func NewHandler(repo *Repository) *Handler {
	return &Handler{repo: repo}
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

func toProto(p *UserPreference) *pb.UserPreference {
	proto := &pb.UserPreference{
		PrefKey:   p.PrefKey,
		PrefValue: p.PrefValue,
		CreatedAt: timestamppb.New(p.CreatedAt),
		UpdatedAt: timestamppb.New(p.UpdatedAt),
	}
	if p.DeletedAt != nil {
		proto.DeletedAt = timestamppb.New(*p.DeletedAt)
	}
	return proto
}

func (h *Handler) ListUserPreferences(ctx context.Context, req *pb.ListUserPreferencesRequest) (*pb.ListUserPreferencesResponse, error) {
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
	prefs, syncedAt, err := h.repo.List(ctx, userID, updatedSince, limit, offset)
	if err != nil {
		return nil, status.Errorf(codes.Internal, "list user preferences: %v", err)
	}

	pbPrefs := make([]*pb.UserPreference, len(prefs))
	for i, p := range prefs {
		pbPrefs[i] = toProto(p)
	}

	nextToken := ""
	if updatedSince == nil {
		nextToken = nextPageToken(offset, limit, len(prefs))
	}

	return &pb.ListUserPreferencesResponse{
		Preferences: pbPrefs,
		Page:        &pb.PageResponse{NextPageToken: nextToken},
		SyncedAt:    timestamppb.New(syncedAt),
	}, nil
}

func (h *Handler) UpsertUserPreference(ctx context.Context, req *pb.UpsertUserPreferenceRequest) (*pb.UpsertUserPreferenceResponse, error) {
	if req.Preference == nil {
		return nil, status.Error(codes.InvalidArgument, "preference is required")
	}

	userID, err := middleware.UserIDFromCtx(ctx)
	if err != nil {
		return nil, err
	}

	prefKey := strings.TrimSpace(req.Preference.PrefKey)
	if prefKey == "" {
		return nil, status.Error(codes.InvalidArgument, "pref_key is required")
	}
	if len(prefKey) > 50 {
		return nil, status.Error(codes.InvalidArgument, "pref_key exceeds 50 chars")
	}

	createdAt := time.Now().UTC()
	if req.Preference.CreatedAt != nil {
		createdAt = req.Preference.CreatedAt.AsTime().UTC()
	}
	updatedAt := time.Now().UTC()
	if req.Preference.UpdatedAt != nil {
		updatedAt = req.Preference.UpdatedAt.AsTime().UTC()
	}

	p := &UserPreference{
		UserID:    userID,
		PrefKey:   prefKey,
		PrefValue: req.Preference.PrefValue,
		CreatedAt: createdAt,
		UpdatedAt: updatedAt,
	}

	result, conflictResolved, err := h.repo.Upsert(ctx, p)
	if err != nil {
		return nil, status.Errorf(codes.Internal, "upsert user preference: %v", err)
	}

	return &pb.UpsertUserPreferenceResponse{
		Preference:       toProto(result),
		ConflictResolved: conflictResolved,
	}, nil
}

func (h *Handler) DeleteUserPreference(ctx context.Context, req *pb.DeleteUserPreferenceRequest) (*emptypb.Empty, error) {
	userID, err := middleware.UserIDFromCtx(ctx)
	if err != nil {
		return nil, err
	}

	prefKey := strings.TrimSpace(req.PrefKey)
	if prefKey == "" {
		return nil, status.Error(codes.InvalidArgument, "pref_key is required")
	}

	var deletedAt time.Time
	if req.DeletedAt != nil {
		deletedAt = req.DeletedAt.AsTime()
	} else {
		deletedAt = time.Now().UTC()
	}

	if err := h.repo.SoftDelete(ctx, userID, prefKey, deletedAt); err != nil {
		return nil, status.Errorf(codes.Internal, "delete user preference: %v", err)
	}

	return &emptypb.Empty{}, nil
}
