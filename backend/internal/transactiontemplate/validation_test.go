package transactiontemplate

import (
	"testing"
	"time"

	"github.com/google/uuid"
)

func TestValidateTemplate(t *testing.T) {
	accountID := uuid.New()
	otherAccountID := uuid.New()
	categoryID := uuid.New()

	frequencyDaily := strPtr("DAILY")
	frequencyInvalid := strPtr("HOURLY")

	amount := int64Ptr(120050)

	nextDate := timePtr(dateOnly(time.Date(2026, time.March, 29, 15, 4, 0, 0, time.FixedZone("UTC-5", -5*3600))))
	endDateAfter := timePtr(dateOnly(time.Date(2026, time.April, 3, 9, 8, 7, 0, time.UTC)))
	endDateBefore := timePtr(dateOnly(time.Date(2026, time.March, 28, 23, 59, 59, 0, time.UTC)))

	tests := []struct {
		name    string
		tpl     Template
		wantErr bool
	}{
		{
			name: "valid manual income template",
			tpl: Template{
				ID:           uuid.New(),
				UserID:       uuid.New(),
				Name:         "Salary",
				AccountID:    accountID,
				Type:         "income",
				CurrencyCode: "USD",
			},
			wantErr: false,
		},
		{
			name: "invalid type",
			tpl: Template{
				ID:           uuid.New(),
				UserID:       uuid.New(),
				Name:         "Invalid Type",
				AccountID:    accountID,
				Type:         "transfer",
				CurrencyCode: "USD",
			},
			wantErr: true,
		},
		{
			name: "manual template with next_date set",
			tpl: Template{
				ID:           uuid.New(),
				UserID:       uuid.New(),
				Name:         "Manual With Next Date",
				AccountID:    accountID,
				Type:         "expense",
				CurrencyCode: "USD",
				NextDate:     nextDate,
			},
			wantErr: true,
		},
		{
			name: "manual template with end_date set",
			tpl: Template{
				ID:           uuid.New(),
				UserID:       uuid.New(),
				Name:         "Manual With End Date",
				AccountID:    accountID,
				Type:         "expense",
				CurrencyCode: "USD",
				EndDate:      endDateAfter,
			},
			wantErr: true,
		},
		{
			name: "scheduled with invalid frequency",
			tpl: Template{
				ID:           uuid.New(),
				UserID:       uuid.New(),
				Name:         "Bad Frequency",
				AccountID:    accountID,
				Type:         "income",
				CurrencyCode: "USD",
				Frequency:    frequencyInvalid,
				NextDate:     nextDate,
				AmountCents:  amount,
			},
			wantErr: true,
		},
		{
			name: "scheduled missing next_date",
			tpl: Template{
				ID:           uuid.New(),
				UserID:       uuid.New(),
				Name:         "Missing Next Date",
				AccountID:    accountID,
				Type:         "income",
				CurrencyCode: "USD",
				Frequency:    frequencyDaily,
				AmountCents:  amount,
			},
			wantErr: true,
		},
		{
			name: "scheduled missing amount",
			tpl: Template{
				ID:           uuid.New(),
				UserID:       uuid.New(),
				Name:         "Missing Amount",
				AccountID:    accountID,
				Type:         "income",
				CurrencyCode: "USD",
				Frequency:    frequencyDaily,
				NextDate:     nextDate,
			},
			wantErr: true,
		},
		{
			name: "scheduled end_date before next_date",
			tpl: Template{
				ID:           uuid.New(),
				UserID:       uuid.New(),
				Name:         "Invalid Date Range",
				AccountID:    accountID,
				Type:         "expense",
				CurrencyCode: "USD",
				Frequency:    frequencyDaily,
				NextDate:     nextDate,
				EndDate:      endDateBefore,
				AmountCents:  amount,
			},
			wantErr: true,
		},
		{
			name: "valid scheduled expense with end_date equal next_date",
			tpl: Template{
				ID:           uuid.New(),
				UserID:       uuid.New(),
				Name:         "Scheduled Expense",
				AccountID:    accountID,
				Type:         "expense",
				CurrencyCode: "USD",
				Frequency:    frequencyDaily,
				NextDate:     nextDate,
				EndDate:      nextDate,
				AmountCents:  amount,
			},
			wantErr: false,
		},
		{
			name: "transfer_out requires to_account_id",
			tpl: Template{
				ID:           uuid.New(),
				UserID:       uuid.New(),
				Name:         "Transfer Missing To",
				AccountID:    accountID,
				Type:         "transfer_out",
				CurrencyCode: "USD",
			},
			wantErr: true,
		},
		{
			name: "transfer_out to_account_id must differ from account_id",
			tpl: Template{
				ID:           uuid.New(),
				UserID:       uuid.New(),
				Name:         "Transfer Same Account",
				AccountID:    accountID,
				ToAccountID:  uuidPtr(accountID),
				Type:         "transfer_out",
				CurrencyCode: "USD",
			},
			wantErr: true,
		},
		{
			name: "transfer_out category must be nil",
			tpl: Template{
				ID:           uuid.New(),
				UserID:       uuid.New(),
				Name:         "Transfer With Category",
				AccountID:    accountID,
				ToAccountID:  uuidPtr(otherAccountID),
				CategoryID:   uuidPtr(categoryID),
				Type:         "transfer_out",
				CurrencyCode: "USD",
			},
			wantErr: true,
		},
		{
			name: "non transfer with to_account_id set",
			tpl: Template{
				ID:           uuid.New(),
				UserID:       uuid.New(),
				Name:         "Expense With To Account",
				AccountID:    accountID,
				ToAccountID:  uuidPtr(otherAccountID),
				Type:         "expense",
				CurrencyCode: "USD",
			},
			wantErr: true,
		},
		{
			name: "valid scheduled transfer_out",
			tpl: Template{
				ID:           uuid.New(),
				UserID:       uuid.New(),
				Name:         "Monthly Transfer",
				AccountID:    accountID,
				ToAccountID:  uuidPtr(otherAccountID),
				Type:         "transfer_out",
				CurrencyCode: "USD",
				Frequency:    frequencyDaily,
				NextDate:     nextDate,
				EndDate:      endDateAfter,
				AmountCents:  amount,
			},
			wantErr: false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			err := ValidateTemplate(tt.tpl)
			if tt.wantErr && err == nil {
				t.Fatalf("expected error, got nil")
			}
			if !tt.wantErr && err != nil {
				t.Fatalf("expected no error, got %v", err)
			}
		})
	}
}

func strPtr(v string) *string {
	return &v
}

func int64Ptr(v int64) *int64 {
	return &v
}

func timePtr(v time.Time) *time.Time {
	return &v
}

func uuidPtr(v uuid.UUID) *uuid.UUID {
	return &v
}
