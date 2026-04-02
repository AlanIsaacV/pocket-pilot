package goal

import "fmt"

func ValidateGoal(g Goal) error {
	if normalizeName(g.Name) == "" {
		return fmt.Errorf("name is required")
	}

	if g.TargetAmountCents <= 0 {
		return fmt.Errorf("target_amount_cents must be > 0")
	}

	if g.CurrencyCode == "" {
		return fmt.Errorf("currency_code is required")
	}

	if g.TargetDate.IsZero() {
		return fmt.Errorf("target_date is required")
	}

	return nil
}
