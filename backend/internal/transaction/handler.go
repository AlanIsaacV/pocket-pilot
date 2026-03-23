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
)

// Handler implements pb.TransactionServiceServer.
type Handler struct {
	pb.UnimplementedTransactionServiceServer
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

func transactionTypeToString(t pb.TransactionType) string {
	switch t {
	case pb.TransactionType_TRANSACTION_TYPE_INCOME:
		return "income"
	case pb.TransactionType_TRANSACTION_TYPE_EXPENSE:
		return "expense"
	case pb.TransactionType_TRANSACTION_TYPE_TRANSFER:
		return "transfer"
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
	case "transfer":
		return pb.TransactionType_TRANSACTION_TYPE_TRANSFER
	default:
		return pb.TransactionType_TRANSACTION_TYPE_UNSPECIFIED
	}
}

func toProto(t *Transaction) *pb.Transaction {
	proto := &pb.Transaction{
		Id:           t.ID.String(),
		UserId:       t.UserID.String(),
		AccountId:    t.AccountID.String(),
		CategoryId:   t.CategoryID.String(),
		Type:         stringToTransactionType(t.Type),
		AmountCents:  t.AmountCents,
		CurrencyCode: t.CurrencyCode,
		Status:       t.Status,
		Tags:         t.Tags,
		Description:  t.Description,
		Date:         timestamppb.New(t.Date),
		CreatedAt:    timestamppb.New(t.CreatedAt),
		UpdatedAt:    timestamppb.New(t.UpdatedAt),
	}
	if t.DeletedAt != nil {
		proto.DeletedAt = timestamppb.New(*t.DeletedAt)
	}
	return proto
}

func fromProto(p *pb.Transaction) (*Transaction, error) {
	id, err := uuid.Parse(p.Id)
	if err != nil {
		return nil, err
	}
	userID, err := uuid.Parse(p.UserId)
	if err != nil {
		return nil, err
	}
	accountID, err := uuid.Parse(p.AccountId)
	if err != nil {
		return nil, err
	}
	categoryID, err := uuid.Parse(p.CategoryId)
	if err != nil {
		return nil, err
	}

	var date time.Time
	if p.Date != nil {
		date = p.Date.AsTime().UTC().Truncate(24 * time.Hour)
	}

	return &Transaction{
		ID:           id,
		UserID:       userID,
		AccountID:    accountID,
		CategoryID:   categoryID,
		Type:         transactionTypeToString(p.Type),
		AmountCents:  p.AmountCents,
		CurrencyCode: p.CurrencyCode,
		Status:       p.Status,
		Tags:         p.Tags,
		Description:  p.Description,
		Date:         date,
		CreatedAt:    p.CreatedAt.AsTime(),
		UpdatedAt:    p.UpdatedAt.AsTime(),
	}, nil
}

// ── RPC handlers ──────────────────────────────────────────────────────────────

// ListTransactions supports delta sync via updated_since.
func (h *Handler) ListTransactions(ctx context.Context, req *pb.ListTransactionsRequest) (*pb.ListTransactionsResponse, error) {
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
		Page: &pb.PageResponse{
			NextPageToken: nextToken,
		},
		SyncedAt: timestamppb.New(syncedAt),
	}, nil
}

// UpsertTransaction creates or updates a transaction using Last Write Wins.
func (h *Handler) UpsertTransaction(ctx context.Context, req *pb.UpsertTransactionRequest) (*pb.UpsertTransactionResponse, error) {
	if req.Transaction == nil {
		return nil, status.Error(codes.InvalidArgument, "transaction is required")
	}

	t, err := fromProto(req.Transaction)
	if err != nil {
		return nil, status.Errorf(codes.InvalidArgument, "invalid transaction: %v", err)
	}

	result, conflictResolved, err := h.repo.Upsert(ctx, t)
	if err != nil {
		return nil, status.Errorf(codes.Internal, "upsert transaction: %v", err)
	}

	return &pb.UpsertTransactionResponse{
		Transaction:     toProto(result),
		ConflictResolved: conflictResolved,
	}, nil
}

// DeleteTransaction soft-deletes a transaction using Last Write Wins on deleted_at.
func (h *Handler) DeleteTransaction(ctx context.Context, req *pb.DeleteTransactionRequest) (*emptypb.Empty, error) {
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
		return nil, status.Errorf(codes.Internal, "delete transaction: %v", err)
	}
	return &emptypb.Empty{}, nil
}
