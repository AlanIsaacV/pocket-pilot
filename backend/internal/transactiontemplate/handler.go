package transactiontemplate

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
	pb.UnimplementedTransactionTemplateServiceServer
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

func stringToFinancialNature(s string) pb.FinancialNature {
	switch s {
	case "required":
		return pb.FinancialNature_NATURE_REQUIRED
	case "obligation":
		return pb.FinancialNature_NATURE_OBLIGATION
	case "lifestyle":
		return pb.FinancialNature_NATURE_LIFESTYLE
	case "active":
		return pb.FinancialNature_NATURE_ACTIVE
	case "passive":
		return pb.FinancialNature_NATURE_PASSIVE
	case "windfall":
		return pb.FinancialNature_NATURE_WINDFALL
	default:
		return pb.FinancialNature_NATURE_UNSPECIFIED
	}
}

func financialNatureToString(n pb.FinancialNature) string {
	switch n {
	case pb.FinancialNature_NATURE_REQUIRED:
		return "required"
	case pb.FinancialNature_NATURE_OBLIGATION:
		return "obligation"
	case pb.FinancialNature_NATURE_LIFESTYLE:
		return "lifestyle"
	case pb.FinancialNature_NATURE_ACTIVE:
		return "active"
	case pb.FinancialNature_NATURE_PASSIVE:
		return "passive"
	case pb.FinancialNature_NATURE_WINDFALL:
		return "windfall"
	default:
		return ""
	}
}

func toProto(t *Template) *pb.TransactionTemplate {
	proto := &pb.TransactionTemplate{
		Id:           t.ID.String(),
		Name:         t.Name,
		AccountId:    t.AccountID.String(),
		Type:         t.Type,
		CurrencyCode: t.CurrencyCode,
		Tags:         t.Tags,
		Description:  t.Description,
		IsAutoCharge: t.IsAutoCharge,
		IsActive:     t.IsActive,
		Nature:       stringToFinancialNature(t.Nature),
		CreatedAt:    timestamppb.New(t.CreatedAt),
		UpdatedAt:    timestamppb.New(t.UpdatedAt),
	}
	if t.CategoryID != nil {
		s := t.CategoryID.String()
		proto.CategoryId = &s
	}
	if t.ToAccountID != nil {
		s := t.ToAccountID.String()
		proto.ToAccountId = &s
	}
	if t.AmountCents != nil {
		v := *t.AmountCents
		proto.AmountCents = &v
	}
	if t.Frequency != nil {
		v := *t.Frequency
		proto.Frequency = &v
	}
	if t.NextDate != nil {
		v := dateOnly(*t.NextDate).Format("2006-01-02")
		proto.NextDate = &v
	}
	if t.EndDate != nil {
		v := dateOnly(*t.EndDate).Format("2006-01-02")
		proto.EndDate = &v
	}
	if t.DeletedAt != nil {
		proto.DeletedAt = timestamppb.New(*t.DeletedAt)
	}
	return proto
}

func fromProto(p *pb.TransactionTemplate, userID uuid.UUID) (*Template, error) {
	id, err := parseUUID(p.Id, "template.id")
	if err != nil {
		return nil, err
	}
	accountID, err := parseUUID(p.AccountId, "template.account_id")
	if err != nil {
		return nil, err
	}

	var toAccountID *uuid.UUID
	if p.ToAccountId != nil && *p.ToAccountId != "" {
		parsed, err := parseUUID(*p.ToAccountId, "template.to_account_id")
		if err != nil {
			return nil, err
		}
		toAccountID = &parsed
	}

	var categoryID *uuid.UUID
	if p.CategoryId != nil && *p.CategoryId != "" {
		parsed, err := parseUUID(*p.CategoryId, "template.category_id")
		if err != nil {
			return nil, err
		}
		categoryID = &parsed
	}

	var amountCents *int64
	if p.AmountCents != nil {
		v := *p.AmountCents
		amountCents = &v
	}

	var frequency *string
	if p.Frequency != nil {
		v := *p.Frequency
		frequency = &v
	}

	var nextDate *time.Time
	if p.NextDate != nil {
		parsed, err := parseDateOnly(*p.NextDate, "template.next_date")
		if err != nil {
			return nil, err
		}
		nextDate = &parsed
	}

	var endDate *time.Time
	if p.EndDate != nil {
		parsed, err := parseDateOnly(*p.EndDate, "template.end_date")
		if err != nil {
			return nil, err
		}
		endDate = &parsed
	}

	return &Template{
		ID:           id,
		UserID:       userID,
		Name:         p.Name,
		AccountID:    accountID,
		ToAccountID:  toAccountID,
		CategoryID:   categoryID,
		Type:         p.Type,
		AmountCents:  amountCents,
		CurrencyCode: p.CurrencyCode,
		Tags:         p.Tags,
		Description:  p.Description,
		Frequency:    frequency,
		NextDate:     nextDate,
		EndDate:      endDate,
		IsAutoCharge: p.IsAutoCharge,
		IsActive:     p.IsActive,
		Nature:       financialNatureToString(p.Nature),
		CreatedAt:    p.CreatedAt.AsTime(),
		UpdatedAt:    p.UpdatedAt.AsTime(),
	}, nil
}

func (h *Handler) ListTransactionTemplates(ctx context.Context, req *pb.ListTransactionTemplatesRequest) (*pb.ListTransactionTemplatesResponse, error) {
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
	templates, syncedAt, err := h.repo.List(ctx, userID, updatedSince, limit, offset)
	if err != nil {
		return nil, status.Errorf(codes.Internal, "list transaction templates: %v", err)
	}

	pbTemplates := make([]*pb.TransactionTemplate, len(templates))
	for i, template := range templates {
		pbTemplates[i] = toProto(template)
	}

	nextToken := ""
	if updatedSince == nil {
		nextToken = nextPageToken(offset, limit, len(templates))
	}

	return &pb.ListTransactionTemplatesResponse{
		Templates: pbTemplates,
		Page:      &pb.PageResponse{NextPageToken: nextToken},
		SyncedAt:  timestamppb.New(syncedAt),
	}, nil
}

func (h *Handler) UpsertTransactionTemplate(ctx context.Context, req *pb.UpsertTransactionTemplateRequest) (*pb.UpsertTransactionTemplateResponse, error) {
	if req.Template == nil {
		return nil, status.Error(codes.InvalidArgument, "template is required")
	}

	userID, err := middleware.UserIDFromCtx(ctx)
	if err != nil {
		return nil, err
	}

	t, err := fromProto(req.Template, userID)
	if err != nil {
		return nil, err
	}

	if err := ValidateTemplate(*t); err != nil {
		return nil, status.Errorf(codes.InvalidArgument, "invalid template: %v", err)
	}

	result, conflictResolved, err := h.repo.Upsert(ctx, t)
	if err != nil {
		return nil, status.Errorf(codes.Internal, "upsert transaction template: %v", err)
	}

	return &pb.UpsertTransactionTemplateResponse{
		Template:         toProto(result),
		ConflictResolved: conflictResolved,
	}, nil
}

func (h *Handler) DeleteTransactionTemplate(ctx context.Context, req *pb.DeleteTransactionTemplateRequest) (*emptypb.Empty, error) {
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
		return nil, status.Errorf(codes.Internal, "delete transaction template: %v", err)
	}

	return &emptypb.Empty{}, nil
}
