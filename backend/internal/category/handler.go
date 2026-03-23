package category

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
)

// Handler implements pb.CategoryServiceServer.
type Handler struct {
	pb.UnimplementedCategoryServiceServer
	repo *Repository
}

func NewHandler(repo *Repository) *Handler {
	return &Handler{repo: repo}
}

// ── Helpers ───────────────────────────────────────────────────────────────────

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

func categoryTypeToString(t pb.CategoryType) string {
	switch t {
	case pb.CategoryType_CATEGORY_TYPE_INCOME:
		return "income"
	case pb.CategoryType_CATEGORY_TYPE_EXPENSE:
		return "expense"
	default:
		return ""
	}
}

func stringToCategoryType(s string) pb.CategoryType {
	switch s {
	case "income":
		return pb.CategoryType_CATEGORY_TYPE_INCOME
	case "expense":
		return pb.CategoryType_CATEGORY_TYPE_EXPENSE
	default:
		return pb.CategoryType_CATEGORY_TYPE_UNSPECIFIED
	}
}

func toProto(c *Category) *pb.Category {
	proto := &pb.Category{
		Id:        c.ID.String(),
		UserId:    c.UserID.String(),
		Name:      c.Name,
		Icon:      c.Icon,
		Color:     c.Color,
		Type:      stringToCategoryType(c.Type),
		CreatedAt: timestamppb.New(c.CreatedAt),
		UpdatedAt: timestamppb.New(c.UpdatedAt),
	}
	if c.ParentID != nil {
		proto.ParentId = c.ParentID.String()
	}
	if c.DeletedAt != nil {
		proto.DeletedAt = timestamppb.New(*c.DeletedAt)
	}
	return proto
}

func fromProto(p *pb.Category) (*Category, error) {
	id, err := uuid.Parse(p.Id)
	if err != nil {
		return nil, err
	}
	userID, err := uuid.Parse(p.UserId)
	if err != nil {
		return nil, err
	}

	c := &Category{
		ID:        id,
		UserID:    userID,
		Name:      p.Name,
		Icon:      p.Icon,
		Color:     p.Color,
		Type:      categoryTypeToString(p.Type),
		CreatedAt: p.CreatedAt.AsTime(),
		UpdatedAt: p.UpdatedAt.AsTime(),
	}
	if p.ParentId != "" {
		pid, err := uuid.Parse(p.ParentId)
		if err != nil {
			return nil, err
		}
		c.ParentID = &pid
	}
	return c, nil
}

// ── RPC handlers ──────────────────────────────────────────────────────────────

// ListCategories supports delta sync via updated_since.
func (h *Handler) ListCategories(ctx context.Context, req *pb.ListCategoriesRequest) (*pb.ListCategoriesResponse, error) {
	userID, err := uuid.Parse(req.UserId)
	if err != nil {
		return nil, status.Errorf(codes.InvalidArgument, "invalid user_id: %v", err)
	}

	var updatedSince *time.Time
	if req.UpdatedSince != nil {
		t := req.UpdatedSince.AsTime()
		updatedSince = &t
	}

	limit, offset := parsePage(req.Page)
	categories, syncedAt, err := h.repo.List(ctx, userID, updatedSince, limit, offset)
	if err != nil {
		return nil, status.Errorf(codes.Internal, "list categories: %v", err)
	}

	pbCats := make([]*pb.Category, len(categories))
	for i, c := range categories {
		pbCats[i] = toProto(c)
	}

	nextToken := ""
	if updatedSince == nil {
		nextToken = nextPageToken(offset, limit, len(categories))
	}

	return &pb.ListCategoriesResponse{
		Categories: pbCats,
		Page: &pb.PageResponse{
			NextPageToken: nextToken,
		},
		SyncedAt: timestamppb.New(syncedAt),
	}, nil
}

// UpsertCategory creates or updates a category using Last Write Wins.
func (h *Handler) UpsertCategory(ctx context.Context, req *pb.UpsertCategoryRequest) (*pb.UpsertCategoryResponse, error) {
	if req.Category == nil {
		return nil, status.Error(codes.InvalidArgument, "category is required")
	}

	c, err := fromProto(req.Category)
	if err != nil {
		return nil, status.Errorf(codes.InvalidArgument, "invalid category: %v", err)
	}

	result, conflictResolved, err := h.repo.Upsert(ctx, c)
	if err != nil {
		return nil, status.Errorf(codes.Internal, "upsert category: %v", err)
	}

	return &pb.UpsertCategoryResponse{
		Category:        toProto(result),
		ConflictResolved: conflictResolved,
	}, nil
}

// DeleteCategory soft-deletes a category using Last Write Wins on deleted_at.
func (h *Handler) DeleteCategory(ctx context.Context, req *pb.DeleteCategoryRequest) (*emptypb.Empty, error) {
	id, err := uuid.Parse(req.Id)
	if err != nil {
		return nil, status.Errorf(codes.InvalidArgument, "invalid id: %v", err)
	}
	userID, err := uuid.Parse(req.UserId)
	if err != nil {
		return nil, status.Errorf(codes.InvalidArgument, "invalid user_id: %v", err)
	}

	var deletedAt time.Time
	if req.DeletedAt != nil {
		deletedAt = req.DeletedAt.AsTime()
	} else {
		deletedAt = time.Now().UTC()
	}

	if err := h.repo.SoftDelete(ctx, id, userID, deletedAt); err != nil {
		return nil, status.Errorf(codes.Internal, "delete category: %v", err)
	}
	return &emptypb.Empty{}, nil
}
