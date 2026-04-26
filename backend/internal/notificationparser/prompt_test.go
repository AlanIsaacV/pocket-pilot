package notificationparser

import (
	"strings"
	"testing"
)

func TestParseLLMResponse_Matched(t *testing.T) {
	raw := `{
		"matched": true,
		"bank_id": "bbva_mx",
		"pattern_id": "purchase_card",
		"transaction_type": "expense",
		"amount_cents": 123456,
		"currency_code": "MXN",
		"merchant_description": "STARBUCKS REFORMA",
		"card_last_digits": "1234",
		"proposed_regex": "Cargo\\s+por\\s+\\$(?<amount>[\\d,]+\\.\\d{2})",
		"confidence": 0.95
	}`

	out, err := ParseLLMResponse(raw)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if !out.Matched {
		t.Fatal("expected matched=true")
	}
	if out.AmountCents != 123456 {
		t.Errorf("amount_cents=%d, want 123456", out.AmountCents)
	}
	if out.MerchantDesc != "STARBUCKS REFORMA" {
		t.Errorf("merchant=%q", out.MerchantDesc)
	}
	if out.TransactionType != "expense" {
		t.Errorf("type=%q", out.TransactionType)
	}
}

func TestParseLLMResponse_NotMatched(t *testing.T) {
	raw := `{"matched": false}`
	out, err := ParseLLMResponse(raw)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if out.Matched {
		t.Fatal("expected matched=false")
	}
}

func TestParseLLMResponse_StripsMarkdownFences(t *testing.T) {
	raw := "```json\n{\"matched\": false}\n```"
	out, err := ParseLLMResponse(raw)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if out.Matched {
		t.Fatal("expected matched=false after fence strip")
	}
}

func TestParseLLMResponse_RejectsInvalidJSON(t *testing.T) {
	cases := []string{
		"",
		"   ",
		"not-json",
		`{"matched": true,`,
	}
	for _, raw := range cases {
		if _, err := ParseLLMResponse(raw); err == nil {
			t.Errorf("expected error for %q, got nil", raw)
		}
	}
}

func TestParseLLMResponse_ValidatesAmountAndType(t *testing.T) {
	bad := []string{
		// amount <= 0
		`{"matched": true, "transaction_type": "expense", "amount_cents": 0}`,
		`{"matched": true, "transaction_type": "expense", "amount_cents": -100}`,
		// invalid type
		`{"matched": true, "transaction_type": "tip", "amount_cents": 100}`,
		`{"matched": true, "transaction_type": "", "amount_cents": 100}`,
	}
	for _, raw := range bad {
		if _, err := ParseLLMResponse(raw); err == nil {
			t.Errorf("expected error for %q, got nil", raw)
		}
	}
}

func TestParseLLMResponse_ClampsConfidence(t *testing.T) {
	raw := `{
		"matched": true,
		"transaction_type": "expense",
		"amount_cents": 100,
		"confidence": 1.5
	}`
	out, err := ParseLLMResponse(raw)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if out.Confidence != 0 {
		t.Errorf("expected confidence to be clamped to 0 for out-of-range, got %v", out.Confidence)
	}
}

func TestBuildMessages_ContainsAllFields(t *testing.T) {
	msgs := BuildMessages("com.bbva.bancomermovil", "BBVA México", "Cargo $100", "")
	if len(msgs) != 2 {
		t.Fatalf("expected 2 messages, got %d", len(msgs))
	}
	if msgs[0].Role != "system" {
		t.Errorf("expected first role=system, got %q", msgs[0].Role)
	}
	if msgs[1].Role != "user" {
		t.Errorf("expected second role=user, got %q", msgs[1].Role)
	}
	if !strings.Contains(msgs[1].Content, "com.bbva.bancomermovil") {
		t.Error("user message should include package name")
	}
	if !strings.Contains(msgs[1].Content, "Cargo $100") {
		t.Error("user message should include text")
	}
	if !strings.Contains(msgs[0].Content, "(?<") {
		t.Error("system prompt should mention ECMAScript named groups")
	}
}
