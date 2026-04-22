package investment

import (
	"fmt"

	"github.com/google/uuid"
)

// Canonical enum values for holding/lot fields. Validation normalizes before
// checking, so callers can pass any case.
var (
	validExchanges  = map[string]struct{}{"NASDAQ": {}, "NYSE": {}, "BMV": {}, "OTHER": {}}
	validAssetTypes = map[string]struct{}{"stock": {}, "etf": {}, "other": {}}
	validStatus     = map[string]struct{}{"active": {}, "closed": {}}
	validLotKinds   = map[string]struct{}{"buy": {}, "sell": {}}
	validValidities = map[string]struct{}{"valid": {}, "invalid": {}}
)

func ValidateHolding(h Holding) error {
	if h.Symbol == "" {
		return fmt.Errorf("symbol is required")
	}
	if _, ok := validExchanges[normalizeUpper(h.Exchange)]; !ok {
		return fmt.Errorf("invalid exchange: %s", h.Exchange)
	}
	if h.CurrencyCode == "" {
		return fmt.Errorf("currency_code is required")
	}
	if _, ok := validAssetTypes[normalizeLower(h.AssetType)]; !ok {
		return fmt.Errorf("invalid asset_type: %s", h.AssetType)
	}
	if _, ok := validStatus[normalizeLower(h.Status)]; !ok {
		return fmt.Errorf("invalid status: %s", h.Status)
	}
	if h.ManualPrice != nil && *h.ManualPrice < 0 {
		return fmt.Errorf("manual_price must be >= 0")
	}
	return nil
}

func ValidateLot(l Lot) error {
	if l.AccountID == uuid.Nil {
		return fmt.Errorf("account_id is required")
	}
	if _, ok := validLotKinds[normalizeLower(l.Kind)]; !ok {
		return fmt.Errorf("invalid kind: %s", l.Kind)
	}
	if l.Quantity <= 0 {
		return fmt.Errorf("quantity must be > 0")
	}
	if l.Price < 0 {
		return fmt.Errorf("price must be >= 0")
	}
	if l.FeeCents < 0 {
		return fmt.Errorf("fee_cents must be >= 0")
	}
	if l.OccurredAt.IsZero() {
		return fmt.Errorf("occurred_at is required")
	}
	if _, ok := validValidities[normalizeLower(l.Validity)]; !ok {
		return fmt.Errorf("invalid validity: %s", l.Validity)
	}
	return nil
}
