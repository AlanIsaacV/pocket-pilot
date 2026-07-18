package cardmapping

import (
	"testing"
	"time"

	"github.com/google/uuid"
	"google.golang.org/protobuf/types/known/timestamppb"

	pb "github.com/AlanIsaacV/pocket-pilot/internal/gen/proto/pocket_pilot/v1/pocket_pilot/v1"
)

func TestPatternIDProtoRoundTrip(t *testing.T) {
	now := time.Date(2026, time.July, 18, 12, 0, 0, 0, time.UTC)
	patternID := "purchase_tdc"
	digits := "1234"
	mapping := &Mapping{
		ID:         uuid.New(),
		BankID:     "bbva_mx",
		LastDigits: &digits,
		PatternID:  &patternID,
		AccountID:  uuid.New(),
		CreatedAt:  now,
		UpdatedAt:  now,
	}

	proto := toProto(mapping)
	if proto.PatternId == nil || proto.GetPatternId() != patternID {
		t.Fatalf("toProto() pattern_id = %v, want %q", proto.PatternId, patternID)
	}

	parsed := &Mapping{}
	if err := fromProto(proto, parsed); err != nil {
		t.Fatalf("fromProto() error = %v", err)
	}
	if parsed.PatternID == nil || *parsed.PatternID != patternID {
		t.Fatalf("fromProto() pattern_id = %v, want %q", parsed.PatternID, patternID)
	}
}

func TestFromProtoClearsAbsentPatternID(t *testing.T) {
	patternID := "purchase_tdc"
	mapping := &Mapping{PatternID: &patternID}

	if err := fromProto(&pb.AccountCardMapping{
		BankId:     "bbva_mx",
		LastDigits: "1234",
		AccountId:  uuid.NewString(),
		CreatedAt:  timestamppb.Now(),
		UpdatedAt:  timestamppb.Now(),
	}, mapping); err != nil {
		t.Fatalf("fromProto() error = %v", err)
	}
	if mapping.PatternID != nil {
		t.Fatalf("fromProto() pattern_id = %v, want nil", mapping.PatternID)
	}
}

func TestFromProtoAllowsPatternOnlyWithoutDigits(t *testing.T) {
	mapping := &Mapping{}
	patternID := "purchase_tdc"

	if err := fromProto(&pb.AccountCardMapping{
		BankId:    "bbva_mx",
		PatternId: &patternID,
		AccountId: uuid.NewString(),
		CreatedAt: timestamppb.Now(),
		UpdatedAt: timestamppb.Now(),
	}, mapping); err != nil {
		t.Fatalf("fromProto() error = %v, want nil for pattern-only mapping", err)
	}
	if mapping.LastDigits != nil {
		t.Fatalf("fromProto() last_digits = %v, want nil", mapping.LastDigits)
	}
	if mapping.PatternID == nil || *mapping.PatternID != "purchase_tdc" {
		t.Fatalf("fromProto() pattern_id = %v, want %q", mapping.PatternID, "purchase_tdc")
	}
}

func TestFromProtoRejectsMissingDigitsAndPattern(t *testing.T) {
	mapping := &Mapping{}

	err := fromProto(&pb.AccountCardMapping{
		BankId:    "bbva_mx",
		AccountId: uuid.NewString(),
		CreatedAt: timestamppb.Now(),
		UpdatedAt: timestamppb.Now(),
	}, mapping)
	if err == nil {
		t.Fatal("fromProto() error = nil, want error when both last_digits and pattern_id are absent")
	}
}

func TestToProtoOmitsLastDigitsWhenNil(t *testing.T) {
	patternID := "purchase_tdc"
	now := time.Now().UTC()
	mapping := &Mapping{
		ID:        uuid.New(),
		BankID:    "bbva_mx",
		PatternID: &patternID,
		AccountID: uuid.New(),
		CreatedAt: now,
		UpdatedAt: now,
	}

	proto := toProto(mapping)
	if proto.LastDigits != "" {
		t.Fatalf("toProto() last_digits = %q, want empty", proto.LastDigits)
	}
}
