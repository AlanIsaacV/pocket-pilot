package transactiontemplate

import "fmt"

const (
	typeIncome      = "income"
	typeExpense     = "expense"
	typeTransferOut = "transfer_out"

	frequencyDaily   = "DAILY"
	frequencyWeekly  = "WEEKLY"
	frequencyMonthly = "MONTHLY"
	frequencyYearly  = "YEARLY"
)

func ValidateTemplate(t Template) error {
	if !isValidType(t.Type) {
		return fmt.Errorf("invalid type: %s", t.Type)
	}

	if t.Frequency == nil {
		if t.NextDate != nil {
			return fmt.Errorf("next_date must be nil for manual template")
		}
		if t.EndDate != nil {
			return fmt.Errorf("end_date must be nil for manual template")
		}
	} else {
		if !isValidFrequency(*t.Frequency) {
			return fmt.Errorf("invalid frequency: %s", *t.Frequency)
		}
		if t.NextDate == nil {
			return fmt.Errorf("next_date is required for scheduled template")
		}
		if t.AmountCents == nil {
			return fmt.Errorf("amount_cents is required for scheduled template")
		}
		if t.EndDate != nil && dateOnly(*t.EndDate).Before(dateOnly(*t.NextDate)) {
			return fmt.Errorf("end_date must be greater than or equal to next_date")
		}
	}

	if t.Type == typeTransferOut {
		if t.ToAccountID == nil {
			return fmt.Errorf("to_account_id is required for transfer_out")
		}
		if *t.ToAccountID == t.AccountID {
			return fmt.Errorf("to_account_id must be different from account_id")
		}
		if t.CategoryID != nil {
			return fmt.Errorf("category_id must be nil for transfer_out")
		}
	} else if t.ToAccountID != nil {
		return fmt.Errorf("to_account_id must be nil for non-transfer types")
	}

	return nil
}

func isValidType(value string) bool {
	switch value {
	case typeIncome, typeExpense, typeTransferOut:
		return true
	default:
		return false
	}
}

func isValidFrequency(value string) bool {
	switch value {
	case frequencyDaily, frequencyWeekly, frequencyMonthly, frequencyYearly:
		return true
	default:
		return false
	}
}
