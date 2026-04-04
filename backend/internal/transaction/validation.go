package transaction

import "fmt"

func validateInstallmentsCount(value int32) error {
	if value < 1 {
		return fmt.Errorf("transaction.installments_count must be >= 1")
	}
	return nil
}
