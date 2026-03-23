package tag

import (
	"context"
	"strconv"
	"time"

	"github.com/google/uuid"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
	"google.golang.org/protobuf/types/known/emptypb"
	"google.golang.org/protobuf/types/known/timestamppb"

	"github.com/AlanIsaacV/pocket-pilot/internal/middleware"
	pb "github.com/AlanIsaacV/pocket-pilot/internal/gen/proto/pocket_pilot/v1/pocket_pilot/v1"
)

type Handler struct {
	pb.UnimplementedTagServiceServer
	repo *Repository
}

func NewHandler(repo *Repository) *Handler {
	return &Handler{repo: repo}
}

// ── Helpers ───────────────────────────────────────────────────────────────────

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

func toProto(t *Tag) *pb.Tag {
	proto := &pb.Tag{
		Id:        t.ID.String(),
		Name:      t.Name,
		CreatedAt: timestamppb.New(t.CreatedAt),
		UpdatedAt: timestamppb.New(t.UpdatedAt),
	}
	if t.DeletedAt != nil {
		proto.DeletedAt = timestamppb.New(*t.DeletedAt)
	}
	return proto
}

func fromProto(p *pb.Tag, userID uuid.UUID) (*Tag, error) {
	id, err := parseUUID(p.Id, "tag.id")
	if err != nil {
		return nil, err
	}
	return &Tag{
		ID:        id,
		UserID:    userID,
		Name:      p.Name,
		CreatedAt: p.CreatedAt.AsTime(),
		UpdatedAt: p.UpdatedAt.AsTime(),
	}, nil
}

// ── RPC handlers ──────────────────────────────────────────────────────────────

func (h *Handler) ListTags(ctx context.Context, req *pb.ListTagsRequest) (*pb.ListTagsResponse, error) {
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
	tags, syncedAt, err := h.repo.List(ctx, userID, updatedSince, limit, offset)
	if err != nil {
		return nil, status.Errorf(codes.Internal, "list tags: %v", err)
	}

	pbTags := make([]*pb.Tag, len(tags))
	for i, t := range tags {
		pbTags[i] = toProto(t)
	}

	nextToken := ""
	if updatedSince == nil {
		nextToken = nextPageToken(offset, limit, len(tags))
	}

	return &pb.ListTagsResponse{
		Tags:     pbTags,
		Page:     &pb.PageResponse{NextPageToken: nextToken},
		SyncedAt: timestamppb.New(syncedAt),
	}, nil
}

func (h *Handler) UpsertTag(ctx context.Context, req *pb.UpsertTagRequest) (*pb.UpsertTagResponse, error) {
	if req.Tag == nil {
		return nil, status.Error(codes.InvalidArgument, "tag is required")
	}

	userID, err := middleware.UserIDFromCtx(ctx)
	if err != nil {
		return nil, err
	}

	t, err := fromProto(req.Tag, userID)
	if err != nil {
		return nil, err
	}

	result, conflictResolved, err := h.repo.Upsert(ctx, t)
	if err != nil {
		return nil, status.Errorf(codes.Internal, "upsert tag: %v", err)
	}

	return &pb.UpsertTagResponse{
		Tag:              toProto(result),
		ConflictResolved: conflictResolved,
	}, nil
}

func (h *Handler) DeleteTag(ctx context.Context, req *pb.DeleteTagRequest) (*emptypb.Empty, error) {
	userID, err := middleware.UserIDFromCtx(ctx)
	if err != nil {
		return nil, err
	}

	id, err := parseUUID(req.Id, "id")
	if err != nil {
		return nil, err
	}

	var deletedAt time.Time
	if req.DeletedAt != nil {
		deletedAt = req.DeletedAt.AsTime()
	} else {
		deletedAt = time.Now().UTC()
	}

	if err := h.repo.SoftDelete(ctx, id, userID, deletedAt); err != nil {
		return nil, status.Errorf(codes.Internal, "delete tag: %v", err)
	}
	return &emptypb.Empty{}, nil
}
