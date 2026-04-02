package goal

import "fmt"

func ValidateGoal(g Goal) error {
	if normalizeName(g.Name) == "" {
		return fmt.Errorf("name is required")
	}

	if g.TargetAmountCents <= 0 {
		return fmt.Errorf("target_amount_cents must be > 0")
	}

	if g.SavedAmountCents < 0 {
		return fmt.Errorf("saved_amount_cents must be >= 0")
	}

	if g.SavedAmountCents > g.TargetAmountCents {
		return fmt.Errorf("saved_amount_cents must be <= target_amount_cents")
	}

	if g.TargetDate.IsZero() {
		return fmt.Errorf("target_date is required")
	}

	return nil
}
