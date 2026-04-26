package notificationparser

import (
	"errors"
	"strings"
	"testing"
)

func TestValidateRegex(t *testing.T) {
	tests := []struct {
		name     string
		input    string
		wantErr  error // nil means success
	}{
		{
			name:    "empty",
			input:   "",
			wantErr: ErrRegexEmpty,
		},
		{
			name:    "whitespace only",
			input:   "   ",
			wantErr: ErrRegexEmpty,
		},
		{
			name:    "too long",
			input:   strings.Repeat("a", MaxRegexLength+1),
			wantErr: ErrRegexTooLong,
		},
		{
			name:    "python named group",
			input:   `(?P<amount>\d+)`,
			wantErr: ErrRegexPythonNamedGroup,
		},
		{
			name:    "backreference",
			input:   `(\w+)\s+\1`,
			wantErr: ErrRegexBackreference,
		},
		{
			name:    "nested quantifier .+ .+",
			input:   `Cargo (.+)+ MXN`,
			wantErr: ErrRegexNestedQuantifier,
		},
		{
			name:    "nested quantifier .* .*",
			input:   `Compra (.*)* OK`,
			wantErr: ErrRegexNestedQuantifier,
		},
		{
			name:    "valid simple regex",
			input:   `Cargo aprobado por \$(?<amount>[\d,]+\.\d{2})`,
			wantErr: nil,
		},
		{
			name:    "valid bbva purchase pattern",
			input:   `Cargo\s+por\s+\$(?<amount>[\d,]+\.\d{2})\s+en\s+(?<merchant>.+)`,
			wantErr: nil,
		},
		{
			name:    "invalid syntax (unbalanced paren)",
			input:   `Cargo (\d+`,
			wantErr: ErrRegexCompile,
		},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			err := ValidateRegex(tc.input)
			if tc.wantErr == nil {
				if err != nil {
					t.Fatalf("expected nil, got %v", err)
				}
				return
			}
			if err == nil {
				t.Fatalf("expected error %v, got nil", tc.wantErr)
			}
			if !errors.Is(err, tc.wantErr) {
				t.Fatalf("expected error %v, got %v", tc.wantErr, err)
			}
		})
	}
}

func TestValidateRegex_AcceptsBBVASeed(t *testing.T) {
	// Sanity check: los regex actuales del parser BBVA deben pasar la
	// validación. Si esto falla tras un cambio, es señal de que la
	// validación se volvió demasiado estricta para producción.
	bbvaPatterns := []string{
		`Cargo\s+aprobado\s+por\s+\$(?<amount>[\d,]+\.\d{2})\s+en\s+(?<merchant>.+)`,
		`Recibiste\s+\$(?<amount>[\d,]+\.\d{2})\s+de\s+(?<sender>[^.\n]+)`,
		`Retiro\s+por\s+\$(?<amount>[\d,]+\.\d{2})`,
	}
	for _, p := range bbvaPatterns {
		if err := ValidateRegex(p); err != nil {
			t.Errorf("expected valid bbva pattern %q to pass, got %v", p, err)
		}
	}
}
