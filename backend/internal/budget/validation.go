package budget

import (
	"fmt"

	"github.com/google/uuid"
)

func ValidateBudget(b Budget) error {
	if b.CategoryID == (uuid.UUID{}) {
		return fmt.Errorf("category_id is required")
	}

	if b.CurrencyCode == "" {
		return fmt.Errorf("currency_code is required")
	}

	if b.LimitAmountCents <= 0 {
		return fmt.Errorf("limit_amount_cents must be > 0")
	}

	p := normalizePeriod(b.Period)
	if p != "MONTHLY" && p != "YEARLY" {
		return fmt.Errorf("period must be MONTHLY or YEARLY")
	}

	return nil
}
