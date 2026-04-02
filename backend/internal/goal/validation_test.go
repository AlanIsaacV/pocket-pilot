package goal

import (
	"testing"
	"time"
)

func TestValidateGoal(t *testing.T) {
	targetDate := dateOnly(time.Date(2026, 8, 15, 0, 0, 0, 0, time.UTC))

	tests := []struct {
		name    string
		g       Goal
		wantErr bool
	}{
		{
			name: "valid goal",
			g: Goal{
				Name:              "Laptop",
				TargetAmountCents: 4800000,
				CurrencyCode:      "MXN",
				TargetDate:        targetDate,
			},
			wantErr: false,
		},
		{
			name: "empty name",
			g: Goal{
				Name:              "   ",
				TargetAmountCents: 100,
				CurrencyCode:      "MXN",
				TargetDate:        targetDate,
			},
			wantErr: true,
		},
		{
			name: "target must be positive",
			g: Goal{
				Name:              "Zero target",
				TargetAmountCents: 0,
				CurrencyCode:      "MXN",
				TargetDate:        targetDate,
			},
			wantErr: true,
		},
		{
			name: "currency code required",
			g: Goal{
				Name:              "No currency",
				TargetAmountCents: 1000,
				CurrencyCode:      "",
				TargetDate:        targetDate,
			},
			wantErr: true,
		},
		{
			name: "target date required",
			g: Goal{
				Name:              "No date",
				TargetAmountCents: 1000,
				CurrencyCode:      "MXN",
			},
			wantErr: true,
		},
	}

	for _, tc := range tests {
		tc := tc
		t.Run(tc.name, func(t *testing.T) {
			err := ValidateGoal(tc.g)
			if tc.wantErr && err == nil {
				t.Fatalf("expected error")
			}
			if !tc.wantErr && err != nil {
				t.Fatalf("unexpected error: %v", err)
			}
		})
	}
}
