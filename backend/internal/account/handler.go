package account

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

// Handler implements pb.AccountServiceServer.
// The embedded UnimplementedAccountServiceServer satisfies the interface for any
// RPC methods we haven't implemented yet — the compiler will catch missing methods
// only when you remove the embed. This is the standard gRPC pattern in Go.
type Handler struct {
	pb.UnimplementedAccountServiceServer
	repo *Repository
}

func NewHandler(repo *Repository) *Handler {
	return &Handler{repo: repo}
}

// ── Helpers ───────────────────────────────────────────────────────────────────

// parsePage extracts limit + offset from a PageRequest.
// page_token is an opaque string — for this MVP it simply encodes the offset
// as a decimal integer. That keeps it simple while staying wire-compatible with
// a future cursor-based implementation.
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
	next := offset + limit
	if next >= total {
		return "" // no more pages
	}
	return strconv.Itoa(next)
}

// accountTypeToString / stringToAccountType convert between the proto enum
// and the plain string stored in PostgreSQL. Using a DB enum type would also
// work, but plain text is easier to inspect and migrate.
func accountTypeToString(t pb.AccountType) string {
	switch t {
	case pb.AccountType_ACCOUNT_TYPE_CHECKING:
		return "checking"
	case pb.AccountType_ACCOUNT_TYPE_SAVINGS:
		return "savings"
	case pb.AccountType_ACCOUNT_TYPE_CREDIT_CARD:
		return "credit_card"
	case pb.AccountType_ACCOUNT_TYPE_CASH:
		return "cash"
	case pb.AccountType_ACCOUNT_TYPE_INVESTMENT:
		return "investment"
	default:
		return "checking"
	}
}

func stringToAccountType(s string) pb.AccountType {
	switch s {
	case "checking":
		return pb.AccountType_ACCOUNT_TYPE_CHECKING
	case "savings":
		return pb.AccountType_ACCOUNT_TYPE_SAVINGS
	case "credit_card":
		return pb.AccountType_ACCOUNT_TYPE_CREDIT_CARD
	case "cash":
		return pb.AccountType_ACCOUNT_TYPE_CASH
	case "investment":
		return pb.AccountType_ACCOUNT_TYPE_INVESTMENT
	default:
		return pb.AccountType_ACCOUNT_TYPE_UNSPECIFIED
	}
}

// toProto converts the internal domain model to the proto message.
// Currency is hardcoded to "MXN" for the MVP — extend this by adding
// a currency_code column to the accounts table when needed.
func toProto(a *Account) *pb.Account {
	return &pb.Account{
		Id:     a.ID.String(),
		UserId: a.UserID.String(),
		Name:   a.Name,
		Type:   stringToAccountType(a.Type),
		InitialBalance: &pb.Money{
			AmountMinor:  a.InitialBalance,
			CurrencyCode: "MXN",
		},
		CreatedAt: timestamppb.New(a.CreatedAt),
		UpdatedAt: timestamppb.New(a.UpdatedAt),
	}
}

// notFoundOrInternal maps pgx.ErrNoRows to codes.NotFound and everything
// else to codes.Internal. This pattern is repeated across all handlers.
func notFoundOrInternal(err error, resource string) error {
	if err == pgx.ErrNoRows {
		return status.Errorf(codes.NotFound, "%s not found", resource)
	}
	return status.Errorf(codes.Internal, "database error: %v", err)
}

// ── RPC handlers ──────────────────────────────────────────────────────────────

func (h *Handler) CreateAccount(ctx context.Context, req *pb.CreateAccountRequest) (*pb.CreateAccountResponse, error) {
	userID, err := uuid.Parse(req.UserId)
	if err != nil {
		return nil, status.Errorf(codes.InvalidArgument, "invalid user_id: %v", err)
	}

	var balance int64
	if req.InitialBalance != nil {
		balance = req.InitialBalance.AmountMinor
	}

	acc, err := h.repo.Create(ctx, userID, req.Name, accountTypeToString(req.Type), balance)
	if err != nil {
		return nil, status.Errorf(codes.Internal, "create account: %v", err)
	}
	return &pb.CreateAccountResponse{Account: toProto(acc)}, nil
}

func (h *Handler) GetAccount(ctx context.Context, req *pb.GetAccountRequest) (*pb.GetAccountResponse, error) {
	userID, err := uuid.Parse(req.UserId)
	if err != nil {
		return nil, status.Errorf(codes.InvalidArgument, "invalid user_id: %v", err)
	}
	id, err := uuid.Parse(req.AccountId)
	if err != nil {
		return nil, status.Errorf(codes.InvalidArgument, "invalid account_id: %v", err)
	}

	acc, err := h.repo.GetByID(ctx, id, userID)
	if err != nil {
		return nil, notFoundOrInternal(err, "account")
	}
	return &pb.GetAccountResponse{Account: toProto(acc)}, nil
}

func (h *Handler) ListAccounts(ctx context.Context, req *pb.ListAccountsRequest) (*pb.ListAccountsResponse, error) {
	userID, err := uuid.Parse(req.UserId)
	if err != nil {
		return nil, status.Errorf(codes.InvalidArgument, "invalid user_id: %v", err)
	}

	limit, offset := parsePage(req.Pagination)
	accounts, total, err := h.repo.List(ctx, userID, limit, offset)
	if err != nil {
		return nil, status.Errorf(codes.Internal, "list accounts: %v", err)
	}

	pbAccounts := make([]*pb.Account, len(accounts))
	for i, a := range accounts {
		pbAccounts[i] = toProto(a)
	}
	return &pb.ListAccountsResponse{
		Accounts: pbAccounts,
		Pagination: &pb.PageResponse{
			NextPageToken: nextPageToken(offset, limit, total),
			TotalCount:    int32(total),
		},
	}, nil
}

func (h *Handler) UpdateAccount(ctx context.Context, req *pb.UpdateAccountRequest) (*pb.UpdateAccountResponse, error) {
	userID, err := uuid.Parse(req.UserId)
	if err != nil {
		return nil, status.Errorf(codes.InvalidArgument, "invalid user_id: %v", err)
	}
	id, err := uuid.Parse(req.AccountId)
	if err != nil {
		return nil, status.Errorf(codes.InvalidArgument, "invalid account_id: %v", err)
	}

	var balance int64
	if req.InitialBalance != nil {
		balance = req.InitialBalance.AmountMinor
	}

	acc, err := h.repo.Update(ctx, id, userID, req.Name, accountTypeToString(req.Type), balance)
	if err != nil {
		return nil, notFoundOrInternal(err, "account")
	}
	return &pb.UpdateAccountResponse{Account: toProto(acc)}, nil
}

func (h *Handler) DeleteAccount(ctx context.Context, req *pb.DeleteAccountRequest) (*pb.DeleteAccountResponse, error) {
	userID, err := uuid.Parse(req.UserId)
	if err != nil {
		return nil, status.Errorf(codes.InvalidArgument, "invalid user_id: %v", err)
	}
	id, err := uuid.Parse(req.AccountId)
	if err != nil {
		return nil, status.Errorf(codes.InvalidArgument, "invalid account_id: %v", err)
	}

	if err := h.repo.Delete(ctx, id, userID); err != nil {
		return nil, notFoundOrInternal(err, "account")
	}
	return &pb.DeleteAccountResponse{}, nil
}
