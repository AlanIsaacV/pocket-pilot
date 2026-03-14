package transaction

import (
	"context"
	"strconv"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
	"google.golang.org/protobuf/types/known/timestamppb"

	pb "github.com/AlanIsaacV/pocket-pilot/internal/gen/proto/pocket_pilot/v1/pocket_pilot/v1"
)

type Handler struct {
	pb.UnimplementedTransactionServiceServer
	repo *Repository
}

func NewHandler(repo *Repository) *Handler {
	return &Handler{repo: repo}
}

const dateLayout = "2006-01-02" // Go's reference date in YYYY-MM-DD format

func toProto(t *Transaction) *pb.Transaction {
	return &pb.Transaction{
		Id:          t.ID.String(),
		UserId:      t.UserID.String(),
		AccountId:   t.AccountID.String(),
		CategoryId:  t.CategoryID.String(),
		Amount:      &pb.Money{AmountMinor: t.Amount, CurrencyCode: "MXN"},
		Description: t.Description,
		Date:        t.Date.Format(dateLayout),
		CreatedAt:   timestamppb.New(t.CreatedAt),
		UpdatedAt:   timestamppb.New(t.UpdatedAt),
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

func (h *Handler) CreateTransaction(ctx context.Context, req *pb.CreateTransactionRequest) (*pb.CreateTransactionResponse, error) {
	userID, err := uuid.Parse(req.UserId)
	if err != nil {
		return nil, status.Errorf(codes.InvalidArgument, "invalid user_id: %v", err)
	}
	accountID, err := uuid.Parse(req.AccountId)
	if err != nil {
		return nil, status.Errorf(codes.InvalidArgument, "invalid account_id: %v", err)
	}
	categoryID, err := uuid.Parse(req.CategoryId)
	if err != nil {
		return nil, status.Errorf(codes.InvalidArgument, "invalid category_id: %v", err)
	}
	date, err := time.Parse(dateLayout, req.Date)
	if err != nil {
		return nil, status.Errorf(codes.InvalidArgument, "invalid date format, expected YYYY-MM-DD: %v", err)
	}

	var amount int64
	if req.Amount != nil {
		amount = req.Amount.AmountMinor
	}

	tx, err := h.repo.Create(ctx, userID, accountID, categoryID, amount, req.Description, date)
	if err != nil {
		return nil, status.Errorf(codes.Internal, "create transaction: %v", err)
	}
	return &pb.CreateTransactionResponse{Transaction: toProto(tx)}, nil
}

func (h *Handler) GetTransaction(ctx context.Context, req *pb.GetTransactionRequest) (*pb.GetTransactionResponse, error) {
	userID, err := uuid.Parse(req.UserId)
	if err != nil {
		return nil, status.Errorf(codes.InvalidArgument, "invalid user_id: %v", err)
	}
	id, err := uuid.Parse(req.TransactionId)
	if err != nil {
		return nil, status.Errorf(codes.InvalidArgument, "invalid transaction_id: %v", err)
	}
	tx, err := h.repo.GetByID(ctx, id, userID)
	if err != nil {
		return nil, notFoundOrInternal(err, "transaction")
	}
	return &pb.GetTransactionResponse{Transaction: toProto(tx)}, nil
}

func (h *Handler) ListTransactions(ctx context.Context, req *pb.ListTransactionsRequest) (*pb.ListTransactionsResponse, error) {
	userID, err := uuid.Parse(req.UserId)
	if err != nil {
		return nil, status.Errorf(codes.InvalidArgument, "invalid user_id: %v", err)
	}

	limit, offset := parsePage(req.Pagination)
	txs, total, err := h.repo.List(ctx, userID, ListFilter{
		AccountID:  req.AccountId,
		CategoryID: req.CategoryId,
		DateFrom:   req.DateFrom,
		DateTo:     req.DateTo,
	}, limit, offset)
	if err != nil {
		return nil, status.Errorf(codes.Internal, "list transactions: %v", err)
	}

	pbTxs := make([]*pb.Transaction, len(txs))
	for i, t := range txs {
		pbTxs[i] = toProto(t)
	}
	return &pb.ListTransactionsResponse{
		Transactions: pbTxs,
		Pagination: &pb.PageResponse{
			NextPageToken: nextPageToken(offset, limit, total),
			TotalCount:    int32(total),
		},
	}, nil
}

func (h *Handler) UpdateTransaction(ctx context.Context, req *pb.UpdateTransactionRequest) (*pb.UpdateTransactionResponse, error) {
	userID, err := uuid.Parse(req.UserId)
	if err != nil {
		return nil, status.Errorf(codes.InvalidArgument, "invalid user_id: %v", err)
	}
	id, err := uuid.Parse(req.TransactionId)
	if err != nil {
		return nil, status.Errorf(codes.InvalidArgument, "invalid transaction_id: %v", err)
	}

	// Parse optional UUID fields — use zero UUID as "not provided" sentinel
	var accountID, categoryID uuid.UUID
	if req.AccountId != "" {
		if accountID, err = uuid.Parse(req.AccountId); err != nil {
			return nil, status.Errorf(codes.InvalidArgument, "invalid account_id: %v", err)
		}
	}
	if req.CategoryId != "" {
		if categoryID, err = uuid.Parse(req.CategoryId); err != nil {
			return nil, status.Errorf(codes.InvalidArgument, "invalid category_id: %v", err)
		}
	}

	var amount int64
	if req.Amount != nil {
		amount = req.Amount.AmountMinor
	}

	tx, err := h.repo.Update(ctx, id, userID, accountID, categoryID, amount, req.Description, req.Date)
	if err != nil {
		return nil, notFoundOrInternal(err, "transaction")
	}
	return &pb.UpdateTransactionResponse{Transaction: toProto(tx)}, nil
}

func (h *Handler) DeleteTransaction(ctx context.Context, req *pb.DeleteTransactionRequest) (*pb.DeleteTransactionResponse, error) {
	userID, err := uuid.Parse(req.UserId)
	if err != nil {
		return nil, status.Errorf(codes.InvalidArgument, "invalid user_id: %v", err)
	}
	id, err := uuid.Parse(req.TransactionId)
	if err != nil {
		return nil, status.Errorf(codes.InvalidArgument, "invalid transaction_id: %v", err)
	}
	if err := h.repo.Delete(ctx, id, userID); err != nil {
		return nil, notFoundOrInternal(err, "transaction")
	}
	return &pb.DeleteTransactionResponse{}, nil
}
