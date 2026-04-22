package investment

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

// -----------------------------------------------------------------------------
// Shared helpers
// -----------------------------------------------------------------------------

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

func parseDateOnly(value, field string) (time.Time, error) {
	t, err := time.Parse("2006-01-02", value)
	if err != nil {
		return time.Time{}, status.Errorf(codes.InvalidArgument, "invalid %s: must be YYYY-MM-DD", field)
	}
	return dateOnly(t), nil
}

// -----------------------------------------------------------------------------
// InvestmentHolding handler
// -----------------------------------------------------------------------------

type HoldingHandler struct {
	pb.UnimplementedInvestmentHoldingServiceServer
	repo *HoldingRepository
}

func NewHoldingHandler(repo *HoldingRepository) *HoldingHandler {
	return &HoldingHandler{repo: repo}
}

func holdingToProto(h *Holding) *pb.InvestmentHolding {
	proto := &pb.InvestmentHolding{
		Id:           h.ID.String(),
		Symbol:       h.Symbol,
		Exchange:     h.Exchange,
		DisplayName:  h.DisplayName,
		CurrencyCode: h.CurrencyCode,
		AssetType:    h.AssetType,
		Status:       h.Status,
		CreatedAt:    timestamppb.New(h.CreatedAt),
		UpdatedAt:    timestamppb.New(h.UpdatedAt),
	}
	if h.ManualPrice != nil {
		v := *h.ManualPrice
		proto.ManualPrice = &v
	}
	if h.Notes != nil {
		v := *h.Notes
		proto.Notes = &v
	}
	if h.DeletedAt != nil {
		proto.DeletedAt = timestamppb.New(*h.DeletedAt)
	}
	return proto
}

func holdingFromProto(p *pb.InvestmentHolding, userID uuid.UUID) (*Holding, error) {
	id, err := parseUUID(p.Id, "holding.id")
	if err != nil {
		return nil, err
	}

	createdAt := time.Now().UTC()
	if p.CreatedAt != nil {
		createdAt = p.CreatedAt.AsTime().UTC()
	}
	updatedAt := time.Now().UTC()
	if p.UpdatedAt != nil {
		updatedAt = p.UpdatedAt.AsTime().UTC()
	}

	h := &Holding{
		ID:           id,
		UserID:       userID,
		Symbol:       normalizeUpper(p.Symbol),
		Exchange:     normalizeUpper(p.Exchange),
		DisplayName:  p.DisplayName,
		CurrencyCode: p.CurrencyCode,
		AssetType:    normalizeLower(p.AssetType),
		Status:       normalizeLower(p.Status),
		CreatedAt:    createdAt,
		UpdatedAt:    updatedAt,
	}
	if p.ManualPrice != nil {
		v := *p.ManualPrice
		h.ManualPrice = &v
	}
	if p.Notes != nil {
		v := *p.Notes
		h.Notes = &v
	}
	return h, nil
}

func (h *HoldingHandler) ListInvestmentHoldings(ctx context.Context, req *pb.ListInvestmentHoldingsRequest) (*pb.ListInvestmentHoldingsResponse, error) {
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
	items, syncedAt, err := h.repo.List(ctx, userID, updatedSince, limit, offset)
	if err != nil {
		return nil, status.Errorf(codes.Internal, "list holdings: %v", err)
	}

	pbItems := make([]*pb.InvestmentHolding, len(items))
	for i, h := range items {
		pbItems[i] = holdingToProto(h)
	}

	nextToken := ""
	if updatedSince == nil {
		nextToken = nextPageToken(offset, limit, len(items))
	}

	return &pb.ListInvestmentHoldingsResponse{
		Holdings: pbItems,
		Page:     &pb.PageResponse{NextPageToken: nextToken},
		SyncedAt: timestamppb.New(syncedAt),
	}, nil
}

func (h *HoldingHandler) UpsertInvestmentHolding(ctx context.Context, req *pb.UpsertInvestmentHoldingRequest) (*pb.UpsertInvestmentHoldingResponse, error) {
	if req.Holding == nil {
		return nil, status.Error(codes.InvalidArgument, "holding is required")
	}
	userID, err := middleware.UserIDFromCtx(ctx)
	if err != nil {
		return nil, err
	}
	m, err := holdingFromProto(req.Holding, userID)
	if err != nil {
		return nil, err
	}
	if err := ValidateHolding(*m); err != nil {
		return nil, status.Errorf(codes.InvalidArgument, "invalid holding: %v", err)
	}
	result, conflict, err := h.repo.Upsert(ctx, m)
	if err != nil {
		return nil, status.Errorf(codes.Internal, "upsert holding: %v", err)
	}
	return &pb.UpsertInvestmentHoldingResponse{
		Holding:          holdingToProto(result),
		ConflictResolved: conflict,
	}, nil
}

func (h *HoldingHandler) DeleteInvestmentHolding(ctx context.Context, req *pb.DeleteInvestmentHoldingRequest) (*emptypb.Empty, error) {
	userID, err := middleware.UserIDFromCtx(ctx)
	if err != nil {
		return nil, err
	}
	id, err := parseUUID(req.Id, "id")
	if err != nil {
		return nil, err
	}
	deletedAt := time.Now().UTC()
	if req.DeletedAt != nil {
		deletedAt = req.DeletedAt.AsTime()
	}
	if err := h.repo.SoftDelete(ctx, id, userID, deletedAt); err != nil {
		return nil, status.Errorf(codes.Internal, "delete holding: %v", err)
	}
	return &emptypb.Empty{}, nil
}

// -----------------------------------------------------------------------------
// InvestmentLot handler
// -----------------------------------------------------------------------------

type LotHandler struct {
	pb.UnimplementedInvestmentLotServiceServer
	repo *LotRepository
}

func NewLotHandler(repo *LotRepository) *LotHandler {
	return &LotHandler{repo: repo}
}

func lotToProto(l *Lot) *pb.InvestmentLot {
	proto := &pb.InvestmentLot{
		Id:         l.ID.String(),
		HoldingId:  l.HoldingID.String(),
		AccountId:  l.AccountID.String(),
		Kind:       l.Kind,
		Quantity:   l.Quantity,
		Price:      l.Price,
		FeeCents:   l.FeeCents,
		OccurredAt: dateOnly(l.OccurredAt).Format("2006-01-02"),
		Validity:   l.Validity,
		CreatedAt:  timestamppb.New(l.CreatedAt),
		UpdatedAt:  timestamppb.New(l.UpdatedAt),
	}
	if l.FxRate != nil {
		v := *l.FxRate
		proto.FxRate = &v
	}
	if l.Notes != nil {
		v := *l.Notes
		proto.Notes = &v
	}
	if l.DeletedAt != nil {
		proto.DeletedAt = timestamppb.New(*l.DeletedAt)
	}
	return proto
}

func lotFromProto(p *pb.InvestmentLot, userID uuid.UUID) (*Lot, error) {
	id, err := parseUUID(p.Id, "lot.id")
	if err != nil {
		return nil, err
	}
	holdingID, err := parseUUID(p.HoldingId, "lot.holding_id")
	if err != nil {
		return nil, err
	}
	accountID, err := parseUUID(p.AccountId, "lot.account_id")
	if err != nil {
		return nil, err
	}
	occurredAt, err := parseDateOnly(p.OccurredAt, "lot.occurred_at")
	if err != nil {
		return nil, err
	}

	createdAt := time.Now().UTC()
	if p.CreatedAt != nil {
		createdAt = p.CreatedAt.AsTime().UTC()
	}
	updatedAt := time.Now().UTC()
	if p.UpdatedAt != nil {
		updatedAt = p.UpdatedAt.AsTime().UTC()
	}

	validity := normalizeLower(p.Validity)
	if validity == "" {
		validity = "valid"
	}

	l := &Lot{
		ID:         id,
		UserID:     userID,
		HoldingID:  holdingID,
		AccountID:  accountID,
		Kind:       normalizeLower(p.Kind),
		Quantity:   p.Quantity,
		Price:      p.Price,
		FeeCents:   p.FeeCents,
		OccurredAt: occurredAt,
		Validity:   validity,
		CreatedAt:  createdAt,
		UpdatedAt:  updatedAt,
	}
	if p.FxRate != nil {
		v := *p.FxRate
		l.FxRate = &v
	}
	if p.Notes != nil {
		v := *p.Notes
		l.Notes = &v
	}
	return l, nil
}

func (h *LotHandler) ListInvestmentLots(ctx context.Context, req *pb.ListInvestmentLotsRequest) (*pb.ListInvestmentLotsResponse, error) {
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
	items, syncedAt, err := h.repo.List(ctx, userID, updatedSince, limit, offset)
	if err != nil {
		return nil, status.Errorf(codes.Internal, "list lots: %v", err)
	}

	pbItems := make([]*pb.InvestmentLot, len(items))
	for i, l := range items {
		pbItems[i] = lotToProto(l)
	}

	nextToken := ""
	if updatedSince == nil {
		nextToken = nextPageToken(offset, limit, len(items))
	}

	return &pb.ListInvestmentLotsResponse{
		Lots:     pbItems,
		Page:     &pb.PageResponse{NextPageToken: nextToken},
		SyncedAt: timestamppb.New(syncedAt),
	}, nil
}

func (h *LotHandler) UpsertInvestmentLot(ctx context.Context, req *pb.UpsertInvestmentLotRequest) (*pb.UpsertInvestmentLotResponse, error) {
	if req.Lot == nil {
		return nil, status.Error(codes.InvalidArgument, "lot is required")
	}
	userID, err := middleware.UserIDFromCtx(ctx)
	if err != nil {
		return nil, err
	}
	m, err := lotFromProto(req.Lot, userID)
	if err != nil {
		return nil, err
	}
	if err := ValidateLot(*m); err != nil {
		return nil, status.Errorf(codes.InvalidArgument, "invalid lot: %v", err)
	}
	result, conflict, err := h.repo.Upsert(ctx, m)
	if err != nil {
		return nil, status.Errorf(codes.Internal, "upsert lot: %v", err)
	}
	return &pb.UpsertInvestmentLotResponse{
		Lot:              lotToProto(result),
		ConflictResolved: conflict,
	}, nil
}

func (h *LotHandler) DeleteInvestmentLot(ctx context.Context, req *pb.DeleteInvestmentLotRequest) (*emptypb.Empty, error) {
	userID, err := middleware.UserIDFromCtx(ctx)
	if err != nil {
		return nil, err
	}
	id, err := parseUUID(req.Id, "id")
	if err != nil {
		return nil, err
	}
	deletedAt := time.Now().UTC()
	if req.DeletedAt != nil {
		deletedAt = req.DeletedAt.AsTime()
	}
	if err := h.repo.SoftDelete(ctx, id, userID, deletedAt); err != nil {
		return nil, status.Errorf(codes.Internal, "delete lot: %v", err)
	}
	return &emptypb.Empty{}, nil
}

// -----------------------------------------------------------------------------
// MarketPrice handler (read-only)
// -----------------------------------------------------------------------------

type MarketPriceHandler struct {
	pb.UnimplementedMarketPriceServiceServer
	repo *MarketPriceRepository
}

func NewMarketPriceHandler(repo *MarketPriceRepository) *MarketPriceHandler {
	return &MarketPriceHandler{repo: repo}
}

func marketPriceToProto(mp *MarketPrice) *pb.MarketPrice {
	return &pb.MarketPrice{
		Symbol:       mp.Symbol,
		Exchange:     mp.Exchange,
		CurrencyCode: mp.CurrencyCode,
		Price:        mp.Price,
		PriceDate:    dateOnly(mp.PriceDate).Format("2006-01-02"),
		Source:       mp.Source,
		FetchedAt:    timestamppb.New(mp.FetchedAt),
		UpdatedAt:    timestamppb.New(mp.UpdatedAt),
	}
}

func (h *MarketPriceHandler) ListMarketPrices(ctx context.Context, req *pb.ListMarketPricesRequest) (*pb.ListMarketPricesResponse, error) {
	// Auth required but user filter is irrelevant: table is global.
	if _, err := middleware.UserIDFromCtx(ctx); err != nil {
		return nil, err
	}

	var updatedSince *time.Time
	if req.UpdatedSince != nil {
		t := req.UpdatedSince.AsTime()
		updatedSince = &t
	}

	limit, offset := parsePage(req.Page)
	items, syncedAt, err := h.repo.List(ctx, updatedSince, limit, offset)
	if err != nil {
		return nil, status.Errorf(codes.Internal, "list market prices: %v", err)
	}

	pbItems := make([]*pb.MarketPrice, len(items))
	for i, mp := range items {
		pbItems[i] = marketPriceToProto(mp)
	}

	nextToken := ""
	if updatedSince == nil {
		nextToken = nextPageToken(offset, limit, len(items))
	}

	return &pb.ListMarketPricesResponse{
		Prices:   pbItems,
		Page:     &pb.PageResponse{NextPageToken: nextToken},
		SyncedAt: timestamppb.New(syncedAt),
	}, nil
}
