package transaction

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
	pb.UnimplementedTransactionServiceServer
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
	case pb.FinancialNature_NATURE_ADJUSTMENT:
		return "adjustment"
	case pb.FinancialNature_NATURE_INVESTMENT:
		return "investment"
	default:
		return ""
	}
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
	case "adjustment":
		return pb.FinancialNature_NATURE_ADJUSTMENT
	case "investment":
		return pb.FinancialNature_NATURE_INVESTMENT
	default:
		return pb.FinancialNature_NATURE_UNSPECIFIED
	}
}

func transactionTypeToString(t pb.TransactionType) string {
	switch t {
	case pb.TransactionType_TRANSACTION_TYPE_INCOME:
		return "income"
	case pb.TransactionType_TRANSACTION_TYPE_EXPENSE:
		return "expense"
	case pb.TransactionType_TRANSACTION_TYPE_TRANSFER_OUT:
		return "transfer_out"
	case pb.TransactionType_TRANSACTION_TYPE_TRANSFER_IN:
		return "transfer_in"
	default:
		return "expense"
	}
}

func stringToTransactionType(s string) pb.TransactionType {
	switch s {
	case "income":
		return pb.TransactionType_TRANSACTION_TYPE_INCOME
	case "expense":
		return pb.TransactionType_TRANSACTION_TYPE_EXPENSE
	case "transfer_out":
		return pb.TransactionType_TRANSACTION_TYPE_TRANSFER_OUT
	case "transfer_in":
		return pb.TransactionType_TRANSACTION_TYPE_TRANSFER_IN
	default:
		return pb.TransactionType_TRANSACTION_TYPE_UNSPECIFIED
	}
}

func toProto(t *Transaction) *pb.Transaction {
	proto := &pb.Transaction{
		Id:                t.ID.String(),
		AccountId:         t.AccountID.String(),
		Type:              stringToTransactionType(t.Type),
		AmountCents:       t.AmountCents,
		InstallmentsCount: t.InstallmentsCount,
		CurrencyCode:      t.CurrencyCode,
		Status:            t.Status,
		Tags:              t.Tags,
		Description:       t.Description,
		Nature:            stringToFinancialNature(t.Nature),
		Date:              timestamppb.New(t.Date),
		CreatedAt:         timestamppb.New(t.CreatedAt),
		UpdatedAt:         timestamppb.New(t.UpdatedAt),
	}
	if t.Source != "" {
		s := t.Source
		proto.Source = &s
	}
	if t.CategoryID != nil {
		s := t.CategoryID.String()
		proto.CategoryId = &s
	}
	if t.LinkedTransactionID != nil {
		s := t.LinkedTransactionID.String()
		proto.LinkedTransactionId = &s
	}
	if t.TemplateID != nil {
		s := t.TemplateID.String()
		proto.TemplateId = &s
	}
	if t.YieldID != nil {
		s := t.YieldID.String()
		proto.YieldId = &s
	}
	if t.HoldingID != nil {
		s := t.HoldingID.String()
		proto.HoldingId = &s
	}
	if t.LotID != nil {
		s := t.LotID.String()
		proto.LotId = &s
	}
	if t.DeletedAt != nil {
		proto.DeletedAt = timestamppb.New(*t.DeletedAt)
	}
	return proto
}

func fromProto(p *pb.Transaction, userID uuid.UUID) (*Transaction, error) {
	if err := validateInstallmentsCount(p.GetInstallmentsCount()); err != nil {
		return nil, status.Error(codes.InvalidArgument, err.Error())
	}

	id, err := parseUUID(p.Id, "transaction.id")
	if err != nil {
		return nil, err
	}
	accountID, err := parseUUID(p.AccountId, "transaction.account_id")
	if err != nil {
		return nil, err
	}

	var categoryID *uuid.UUID
	if p.CategoryId != nil && *p.CategoryId != "" {
		cid, err := parseUUID(*p.CategoryId, "transaction.category_id")
		if err != nil {
			return nil, err
		}
		categoryID = &cid
	}

	var linkedID *uuid.UUID
	if p.LinkedTransactionId != nil && *p.LinkedTransactionId != "" {
		lid, err := parseUUID(*p.LinkedTransactionId, "transaction.linked_transaction_id")
		if err != nil {
			return nil, err
		}
		linkedID = &lid
	}

	var templateID *uuid.UUID
	if p.TemplateId != nil && *p.TemplateId != "" {
		tid, err := parseUUID(*p.TemplateId, "transaction.template_id")
		if err != nil {
			return nil, err
		}
		templateID = &tid
	}

	var yieldID *uuid.UUID
	if p.YieldId != nil && *p.YieldId != "" {
		yid, err := parseUUID(*p.YieldId, "transaction.yield_id")
		if err != nil {
			return nil, err
		}
		yieldID = &yid
	}

	var holdingID *uuid.UUID
	if p.HoldingId != nil && *p.HoldingId != "" {
		hid, err := parseUUID(*p.HoldingId, "transaction.holding_id")
		if err != nil {
			return nil, err
		}
		holdingID = &hid
	}

	var lotID *uuid.UUID
	if p.LotId != nil && *p.LotId != "" {
		lid, err := parseUUID(*p.LotId, "transaction.lot_id")
		if err != nil {
			return nil, err
		}
		lotID = &lid
	}

	var date time.Time
	if p.Date != nil {
		date = p.Date.AsTime().UTC().Truncate(24 * time.Hour)
	}

	source := "manual"
	if p.Source != nil && *p.Source != "" {
		source = *p.Source
	}

	return &Transaction{
		ID:                  id,
		UserID:              userID,
		AccountID:           accountID,
		CategoryID:          categoryID,
		LinkedTransactionID: linkedID,
		TemplateID:          templateID,
		YieldID:             yieldID,
		HoldingID:           holdingID,
		LotID:               lotID,
		Type:                transactionTypeToString(p.Type),
		AmountCents:         p.AmountCents,
		InstallmentsCount:   p.InstallmentsCount,
		CurrencyCode:        p.CurrencyCode,
		Status:              p.Status,
		Source:              source,
		Tags:                p.Tags,
		Description:         p.Description,
		Nature:              financialNatureToString(p.Nature),
		Date:                date,
		CreatedAt:           p.CreatedAt.AsTime(),
		UpdatedAt:           p.UpdatedAt.AsTime(),
	}, nil
}

// ── RPC handlers ──────────────────────────────────────────────────────────────

func (h *Handler) ListTransactions(ctx context.Context, req *pb.ListTransactionsRequest) (*pb.ListTransactionsResponse, error) {
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
	txs, syncedAt, err := h.repo.List(ctx, userID, updatedSince, limit, offset)
	if err != nil {
		return nil, status.Errorf(codes.Internal, "list transactions: %v", err)
	}

	pbTxs := make([]*pb.Transaction, len(txs))
	for i, t := range txs {
		pbTxs[i] = toProto(t)
	}

	nextToken := ""
	if updatedSince == nil {
		nextToken = nextPageToken(offset, limit, len(txs))
	}

	return &pb.ListTransactionsResponse{
		Transactions: pbTxs,
		Page:         &pb.PageResponse{NextPageToken: nextToken},
		SyncedAt:     timestamppb.New(syncedAt),
	}, nil
}

func (h *Handler) UpsertTransaction(ctx context.Context, req *pb.UpsertTransactionRequest) (*pb.UpsertTransactionResponse, error) {
	if req.Transaction == nil {
		return nil, status.Error(codes.InvalidArgument, "transaction is required")
	}

	userID, err := middleware.UserIDFromCtx(ctx)
	if err != nil {
		return nil, err
	}

	t, err := fromProto(req.Transaction, userID)
	if err != nil {
		return nil, err
	}

	result, conflictResolved, err := h.repo.Upsert(ctx, t)
	if err != nil {
		if err == ErrTemplateReferenceNotFound || err == ErrTemplateReferenceDateNotAllowed {
			return nil, status.Errorf(codes.InvalidArgument, "upsert transaction: %v", err)
		}
		return nil, status.Errorf(codes.Internal, "upsert transaction: %v", err)
	}

	return &pb.UpsertTransactionResponse{
		Transaction:      toProto(result),
		ConflictResolved: conflictResolved,
	}, nil
}

func (h *Handler) DeleteTransaction(ctx context.Context, req *pb.DeleteTransactionRequest) (*emptypb.Empty, error) {
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
		return nil, status.Errorf(codes.Internal, "delete transaction: %v", err)
	}
	return &emptypb.Empty{}, nil
}
