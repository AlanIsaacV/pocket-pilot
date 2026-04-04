package transaction

import (
	"testing"
	"time"

	pb "github.com/AlanIsaacV/pocket-pilot/internal/gen/proto/pocket_pilot/v1/pocket_pilot/v1"
	"github.com/google/uuid"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
	"google.golang.org/protobuf/types/known/timestamppb"
)

func TestValidateInstallmentsCount(t *testing.T) {
	tests := []struct {
		name    string
		value   int32
		wantErr bool
	}{
		{name: "one installment", value: 1, wantErr: false},
		{name: "twelve installments", value: 12, wantErr: false},
		{name: "zero invalid", value: 0, wantErr: true},
		{name: "negative invalid", value: -3, wantErr: true},
	}

	for _, tc := range tests {
		tc := tc
		t.Run(tc.name, func(t *testing.T) {
			err := validateInstallmentsCount(tc.value)
			if tc.wantErr && err == nil {
				t.Fatalf("expected error")
			}
			if !tc.wantErr && err != nil {
				t.Fatalf("unexpected error: %v", err)
			}
		})
	}
}

func TestFromProtoRejectsInstallmentsCountLessThanOne(t *testing.T) {
	now := time.Date(2026, 4, 3, 0, 0, 0, 0, time.UTC)
	tx := &pb.Transaction{
		Id:                uuid.NewString(),
		AccountId:         uuid.NewString(),
		Type:              pb.TransactionType_TRANSACTION_TYPE_EXPENSE,
		AmountCents:       1000,
		InstallmentsCount: 0,
		CurrencyCode:      "MXN",
		Status:            "cleared",
		Description:       "Compra",
		Date:              timestamppb.New(now),
		CreatedAt:         timestamppb.New(now),
		UpdatedAt:         timestamppb.New(now),
	}

	_, err := fromProto(tx, uuid.New())
	if err == nil {
		t.Fatalf("expected invalid argument error")
	}

	st, ok := status.FromError(err)
	if !ok {
		t.Fatalf("expected grpc status error")
	}
	if st.Code() != codes.InvalidArgument {
		t.Fatalf("expected InvalidArgument, got %s", st.Code())
	}
}
