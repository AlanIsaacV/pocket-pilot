package marketprice

import (
	"context"
	"time"

	pb "github.com/AlanIsaacV/pocket-pilot/internal/gen/proto/pocket_pilot/v1/pocket_pilot/v1"
	"github.com/AlanIsaacV/pocket-pilot/internal/investment"
)

// AdminHandler serves MarketPriceAdminService. It is gated upstream by
// middleware.NewUnaryAuthInterceptor using MARKETPRICE_ADMIN_TOKEN; the
// handler itself takes no auth action and relies on the interceptor.
type AdminHandler struct {
	pb.UnimplementedMarketPriceAdminServiceServer

	scheduler   *Scheduler
	holdingRepo *investment.HoldingRepository
}

// NewAdminHandler wires the dependencies. The scheduler must already be
// created; it is reused purely for its Refresh method (no ticker needed).
func NewAdminHandler(scheduler *Scheduler, holdingRepo *investment.HoldingRepository) *AdminHandler {
	return &AdminHandler{scheduler: scheduler, holdingRepo: holdingRepo}
}

// AdminRefreshMarketPrices runs a one-shot fetch+upsert cycle. If the
// request contains no symbols, every active (symbol, exchange) pair across
// holdings is refreshed.
func (h *AdminHandler) AdminRefreshMarketPrices(
	ctx context.Context,
	req *pb.AdminRefreshMarketPricesRequest,
) (*pb.AdminRefreshMarketPricesResponse, error) {
	start := time.Now()

	var symbols []investment.SymbolExchange
	if len(req.GetSymbols()) == 0 {
		pairs, err := h.holdingRepo.ListActiveSymbolExchanges(ctx)
		if err != nil {
			return nil, err
		}
		symbols = pairs
	} else {
		symbols = make([]investment.SymbolExchange, 0, len(req.GetSymbols()))
		for _, s := range req.GetSymbols() {
			symbols = append(symbols, investment.SymbolExchange{
				Symbol:   s.GetSymbol(),
				Exchange: s.GetExchange(),
			})
		}
	}

	updated, failed, errs, err := h.scheduler.Refresh(ctx, symbols)
	if err != nil {
		return nil, err
	}

	resp := &pb.AdminRefreshMarketPricesResponse{
		Updated:    int32(updated),
		Failed:     int32(failed),
		DurationMs: time.Since(start).Milliseconds(),
	}
	for _, e := range errs {
		resp.Errors = append(resp.Errors, &pb.SymbolError{
			Symbol:   e.Symbol,
			Exchange: e.Exchange,
			Reason:   e.Reason,
		})
	}
	return resp, nil
}
