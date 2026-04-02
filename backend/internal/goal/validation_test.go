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
				SavedAmountCents:  1500000,
				TargetDate:        targetDate,
			},
			wantErr: false,
		},
		{
			name: "empty name",
			g: Goal{
				Name:              "   ",
				TargetAmountCents: 100,
				SavedAmountCents:  0,
				TargetDate:        targetDate,
			},
			wantErr: true,
		},
		{
			name: "target must be positive",
			g: Goal{
				Name:              "Zero target",
				TargetAmountCents: 0,
				SavedAmountCents:  0,
				TargetDate:        targetDate,
			},
			wantErr: true,
		},
		{
			name: "saved cannot be negative",
			g: Goal{
				Name:              "Negative saved",
				TargetAmountCents: 1000,
				SavedAmountCents:  -1,
				TargetDate:        targetDate,
			},
			wantErr: true,
		},
		{
			name: "saved cannot exceed target",
			g: Goal{
				Name:              "Overflow saved",
				TargetAmountCents: 1000,
				SavedAmountCents:  1001,
				TargetDate:        targetDate,
			},
			wantErr: true,
		},
		{
			name: "target date required",
			g: Goal{
				Name:              "No date",
				TargetAmountCents: 1000,
				SavedAmountCents:  0,
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
