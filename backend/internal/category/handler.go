package category

import (
	"context"
	"strconv"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
	"google.golang.org/protobuf/types/known/timestamppb"

	pb "github.com/AlanIsaacV/pocket-pilot/internal/gen/proto/pocket_pilot/v1/pocket_pilot/v1"
)

type Handler struct {
	pb.UnimplementedCategoryServiceServer
	repo *Repository
}

func NewHandler(repo *Repository) *Handler {
	return &Handler{repo: repo}
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
	return &pb.Category{
		Id:        c.ID.String(),
		UserId:    c.UserID.String(),
		Name:      c.Name,
		Type:      stringToCategoryType(c.Type),
		CreatedAt: timestamppb.New(c.CreatedAt),
		UpdatedAt: timestamppb.New(c.UpdatedAt),
	}
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

func nextPageToken(offset, limit, total int) string {
	if offset+limit >= total {
		return ""
	}
	return strconv.Itoa(offset + limit)
}

func notFoundOrInternal(err error, resource string) error {
	if err == pgx.ErrNoRows {
		return status.Errorf(codes.NotFound, "%s not found", resource)
	}
	return status.Errorf(codes.Internal, "database error: %v", err)
}

func (h *Handler) CreateCategory(ctx context.Context, req *pb.CreateCategoryRequest) (*pb.CreateCategoryResponse, error) {
	userID, err := uuid.Parse(req.UserId)
	if err != nil {
		return nil, status.Errorf(codes.InvalidArgument, "invalid user_id: %v", err)
	}
	cat, err := h.repo.Create(ctx, userID, req.Name, categoryTypeToString(req.Type))
	if err != nil {
		return nil, status.Errorf(codes.Internal, "create category: %v", err)
	}
	return &pb.CreateCategoryResponse{Category: toProto(cat)}, nil
}

func (h *Handler) GetCategory(ctx context.Context, req *pb.GetCategoryRequest) (*pb.GetCategoryResponse, error) {
	userID, err := uuid.Parse(req.UserId)
	if err != nil {
		return nil, status.Errorf(codes.InvalidArgument, "invalid user_id: %v", err)
	}
	id, err := uuid.Parse(req.CategoryId)
	if err != nil {
		return nil, status.Errorf(codes.InvalidArgument, "invalid category_id: %v", err)
	}
	cat, err := h.repo.GetByID(ctx, id, userID)
	if err != nil {
		return nil, notFoundOrInternal(err, "category")
	}
	return &pb.GetCategoryResponse{Category: toProto(cat)}, nil
}

func (h *Handler) ListCategories(ctx context.Context, req *pb.ListCategoriesRequest) (*pb.ListCategoriesResponse, error) {
	userID, err := uuid.Parse(req.UserId)
	if err != nil {
		return nil, status.Errorf(codes.InvalidArgument, "invalid user_id: %v", err)
	}

	typeFilter := categoryTypeToString(req.Type) // empty string = no filter
	limit, offset := parsePage(req.Pagination)

	cats, total, err := h.repo.List(ctx, userID, typeFilter, limit, offset)
	if err != nil {
		return nil, status.Errorf(codes.Internal, "list categories: %v", err)
	}

	pbCats := make([]*pb.Category, len(cats))
	for i, c := range cats {
		pbCats[i] = toProto(c)
	}
	return &pb.ListCategoriesResponse{
		Categories: pbCats,
		Pagination: &pb.PageResponse{
			NextPageToken: nextPageToken(offset, limit, total),
			TotalCount:    int32(total),
		},
	}, nil
}

func (h *Handler) UpdateCategory(ctx context.Context, req *pb.UpdateCategoryRequest) (*pb.UpdateCategoryResponse, error) {
	userID, err := uuid.Parse(req.UserId)
	if err != nil {
		return nil, status.Errorf(codes.InvalidArgument, "invalid user_id: %v", err)
	}
	id, err := uuid.Parse(req.CategoryId)
	if err != nil {
		return nil, status.Errorf(codes.InvalidArgument, "invalid category_id: %v", err)
	}
	cat, err := h.repo.Update(ctx, id, userID, req.Name, categoryTypeToString(req.Type))
	if err != nil {
		return nil, notFoundOrInternal(err, "category")
	}
	return &pb.UpdateCategoryResponse{Category: toProto(cat)}, nil
}

func (h *Handler) DeleteCategory(ctx context.Context, req *pb.DeleteCategoryRequest) (*pb.DeleteCategoryResponse, error) {
	userID, err := uuid.Parse(req.UserId)
	if err != nil {
		return nil, status.Errorf(codes.InvalidArgument, "invalid user_id: %v", err)
	}
	id, err := uuid.Parse(req.CategoryId)
	if err != nil {
		return nil, status.Errorf(codes.InvalidArgument, "invalid category_id: %v", err)
	}
	if err := h.repo.Delete(ctx, id, userID); err != nil {
		return nil, notFoundOrInternal(err, "category")
	}
	return &pb.DeleteCategoryResponse{}, nil
}
