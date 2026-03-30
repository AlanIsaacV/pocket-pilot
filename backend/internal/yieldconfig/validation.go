package yieldconfig

import "fmt"

func ValidateYieldConfig(cfg YieldConfig) error {
	status := normalizeLower(cfg.Status)
	freq := normalizeLower(cfg.PayoutFrequency)

	if status != "active" && status != "paused" && status != "completed" {
		return fmt.Errorf("invalid status")
	}

	if freq != "daily" && freq != "weekly" && freq != "monthly" && freq != "at_maturity" {
		return fmt.Errorf("invalid payout_frequency")
	}

	if cfg.AmountCents <= 0 {
		return fmt.Errorf("amount_cents must be > 0")
	}

	if cfg.ApyRate < 0 {
		return fmt.Errorf("apy_rate must be >= 0")
	}

	if cfg.NextDate.IsZero() {
		return fmt.Errorf("next_date is required")
	}

	if freq == "at_maturity" {
		if cfg.TermDays == nil || *cfg.TermDays <= 0 {
			return fmt.Errorf("at_maturity requires term_days > 0")
		}
		if cfg.MaturityDate == nil {
			return fmt.Errorf("at_maturity requires maturity_date")
		}
		if !dateOnly(cfg.NextDate).Equal(dateOnly(*cfg.MaturityDate)) {
			return fmt.Errorf("at_maturity requires next_date == maturity_date")
		}
	}

	if cfg.AutoRenew && cfg.MaturityDate != nil {
		if cfg.TermDays == nil || *cfg.TermDays <= 0 {
			return fmt.Errorf("auto_renew requires term_days > 0 when maturity_date exists")
		}
	}

	return nil
}
