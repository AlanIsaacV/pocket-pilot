package account

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

// Handler implements pb.AccountServiceServer.
// UnimplementedAccountServiceServer satisfies the interface for any unimplemented RPCs.
type Handler struct {
	pb.UnimplementedAccountServiceServer
	repo *Repository
}

func NewHandler(repo *Repository) *Handler {
	return &Handler{repo: repo}
}

// ── Helpers ───────────────────────────────────────────────────────────────────

// parsePage extracts limit + offset from a PageRequest.
// page_token encodes the offset as a decimal integer (simple cursor for the MVP).
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
		return "" // no more pages
	}
	return strconv.Itoa(offset + limit)
}

func accountTypeToString(t pb.AccountType) string {
	switch t {
	case pb.AccountType_ACCOUNT_TYPE_BANK:
		return "bank"
	case pb.AccountType_ACCOUNT_TYPE_CASH:
		return "cash"
	case pb.AccountType_ACCOUNT_TYPE_CREDIT_CARD:
		return "credit_card"
	case pb.AccountType_ACCOUNT_TYPE_LOAN:
		return "loan"
	case pb.AccountType_ACCOUNT_TYPE_INVESTMENT:
		return "investment"
	case pb.AccountType_ACCOUNT_TYPE_CRYPYO:
		return "crypto"
	case pb.AccountType_ACCOUNT_TYPE_OTHER:
		return "other"
	default:
		return "other"
	}
}

func stringToAccountType(s string) pb.AccountType {
	switch s {
	case "bank":
		return pb.AccountType_ACCOUNT_TYPE_BANK
	case "cash":
		return pb.AccountType_ACCOUNT_TYPE_CASH
	case "credit_card":
		return pb.AccountType_ACCOUNT_TYPE_CREDIT_CARD
	case "loan":
		return pb.AccountType_ACCOUNT_TYPE_LOAN
	case "investment":
		return pb.AccountType_ACCOUNT_TYPE_INVESTMENT
	case "crypto":
		return pb.AccountType_ACCOUNT_TYPE_CRYPYO
	default:
		return pb.AccountType_ACCOUNT_TYPE_OTHER
	}
}

func toProto(a *Account) *pb.Account {
	proto := &pb.Account{
		Id:        a.ID.String(),
		UserId:    a.UserID.String(),
		Name:      a.Name,
		Type:      stringToAccountType(a.Type),
		CreatedAt: timestamppb.New(a.CreatedAt),
		UpdatedAt: timestamppb.New(a.UpdatedAt),
	}
	if a.CreditLimitCents != nil {
		proto.CreditLimitCents = *a.CreditLimitCents
	}
	if a.StatementDay != nil {
		proto.StatementDay = *a.StatementDay
	}
	if a.PaymentDueDay != nil {
		proto.PaymentDueDay = *a.PaymentDueDay
	}
	if a.InterestRateApr != nil {
		proto.InterestRateApr = int32(*a.InterestRateApr)
	}
	if a.TermMonths != nil {
		proto.TermMonths = *a.TermMonths
	}
	if a.DeletedAt != nil {
		proto.DeletedAt = timestamppb.New(*a.DeletedAt)
	}
	return proto
}

func fromProto(p *pb.Account) (*Account, error) {
	id, err := uuid.Parse(p.Id)
	if err != nil {
		return nil, err
	}
	userID, err := uuid.Parse(p.UserId)
	if err != nil {
		return nil, err
	}

	a := &Account{
		ID:        id,
		UserID:    userID,
		Name:      p.Name,
		Type:      accountTypeToString(p.Type),
		CreatedAt: p.CreatedAt.AsTime(),
		UpdatedAt: p.UpdatedAt.AsTime(),
	}
	if p.CreditLimitCents != 0 {
		v := p.CreditLimitCents
		a.CreditLimitCents = &v
	}
	if p.StatementDay != 0 {
		v := p.StatementDay
		a.StatementDay = &v
	}
	if p.PaymentDueDay != 0 {
		v := p.PaymentDueDay
		a.PaymentDueDay = &v
	}
	if p.InterestRateApr != 0 {
		v := float64(p.InterestRateApr)
		a.InterestRateApr = &v
	}
	if p.TermMonths != 0 {
		v := p.TermMonths
		a.TermMonths = &v
	}
	return a, nil
}

// ── RPC handlers ──────────────────────────────────────────────────────────────

// ListAccounts supports delta sync via updated_since.
// If updated_since is set, returns all records (active + deleted) modified after that timestamp.
// If not set (first sync), returns only active records with pagination.
func (h *Handler) ListAccounts(ctx context.Context, req *pb.ListAccountsRequest) (*pb.ListAccountsResponse, error) {
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
	accounts, syncedAt, err := h.repo.List(ctx, userID, updatedSince, limit, offset)
	if err != nil {
		return nil, status.Errorf(codes.Internal, "list accounts: %v", err)
	}

	pbAccounts := make([]*pb.Account, len(accounts))
	for i, a := range accounts {
		pbAccounts[i] = toProto(a)
	}

	nextToken := ""
	if updatedSince == nil {
		// Only paginate on full sync.
		nextToken = nextPageToken(offset, limit, len(accounts))
	}

	return &pb.ListAccountsResponse{
		Accounts: pbAccounts,
		Page: &pb.PageResponse{
			NextPageToken: nextToken,
		},
		SyncedAt: timestamppb.New(syncedAt),
	}, nil
}

// UpsertAccount creates or updates an account using Last Write Wins.
// If the server has a newer version, conflict_resolved=true is returned with the server's version.
func (h *Handler) UpsertAccount(ctx context.Context, req *pb.UpsertAccountRequest) (*pb.UpsertAccountResponse, error) {
	if req.Account == nil {
		return nil, status.Error(codes.InvalidArgument, "account is required")
	}

	a, err := fromProto(req.Account)
	if err != nil {
		return nil, status.Errorf(codes.InvalidArgument, "invalid account: %v", err)
	}

	result, conflictResolved, err := h.repo.Upsert(ctx, a)
	if err != nil {
		return nil, status.Errorf(codes.Internal, "upsert account: %v", err)
	}

	return &pb.UpsertAccountResponse{
		Account:         toProto(result),
		ConflictResolved: conflictResolved,
	}, nil
}

// DeleteAccount soft-deletes an account using Last Write Wins on deleted_at.
// If the server has a newer version, the delete is silently ignored.
func (h *Handler) DeleteAccount(ctx context.Context, req *pb.DeleteAccountRequest) (*emptypb.Empty, error) {
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
		return nil, status.Errorf(codes.Internal, "delete account: %v", err)
	}
	return &emptypb.Empty{}, nil
}
