package yieldconfig

import (
	"testing"
	"time"
)

func TestValidateYieldConfig(t *testing.T) {
	next := dateOnly(time.Date(2026, 4, 1, 0, 0, 0, 0, time.UTC))
	maturity := dateOnly(time.Date(2026, 6, 30, 0, 0, 0, 0, time.UTC))
	termDays := int32(90)

	tests := []struct {
		name    string
		cfg     YieldConfig
		wantErr bool
	}{
		{
			name: "valid daily active",
			cfg: YieldConfig{
				AmountCents:     100000,
				ApyRate:         14.5,
				PayoutFrequency: "daily",
				NextDate:        next,
				Status:          "active",
			},
			wantErr: false,
		},
		{
			name: "invalid status",
			cfg: YieldConfig{
				AmountCents:     100000,
				ApyRate:         14.5,
				PayoutFrequency: "daily",
				NextDate:        next,
				Status:          "running",
			},
			wantErr: true,
		},
		{
			name: "invalid frequency",
			cfg: YieldConfig{
				AmountCents:     100000,
				ApyRate:         14.5,
				PayoutFrequency: "hourly",
				NextDate:        next,
				Status:          "active",
			},
			wantErr: true,
		},
		{
			name: "at maturity missing term days",
			cfg: YieldConfig{
				AmountCents:     100000,
				ApyRate:         14.5,
				PayoutFrequency: "at_maturity",
				NextDate:        maturity,
				MaturityDate:    &maturity,
				Status:          "active",
			},
			wantErr: true,
		},
		{
			name: "at maturity missing maturity date",
			cfg: YieldConfig{
				AmountCents:     100000,
				ApyRate:         14.5,
				PayoutFrequency: "at_maturity",
				NextDate:        maturity,
				TermDays:        &termDays,
				Status:          "active",
			},
			wantErr: true,
		},
		{
			name: "at maturity next date mismatch",
			cfg: YieldConfig{
				AmountCents:     100000,
				ApyRate:         14.5,
				PayoutFrequency: "at_maturity",
				NextDate:        next,
				MaturityDate:    &maturity,
				TermDays:        &termDays,
				Status:          "active",
			},
			wantErr: true,
		},
		{
			name: "valid at maturity",
			cfg: YieldConfig{
				AmountCents:     100000,
				ApyRate:         14.5,
				PayoutFrequency: "at_maturity",
				NextDate:        maturity,
				MaturityDate:    &maturity,
				TermDays:        &termDays,
				AutoRenew:       true,
				Status:          "active",
			},
			wantErr: false,
		},
	}

	for _, tc := range tests {
		tc := tc
		t.Run(tc.name, func(t *testing.T) {
			err := ValidateYieldConfig(tc.cfg)
			if tc.wantErr && err == nil {
				t.Fatalf("expected error")
			}
			if !tc.wantErr && err != nil {
				t.Fatalf("unexpected error: %v", err)
			}
		})
	}
}
