package sync

import (
	"context"
	"time"

	"google.golang.org/protobuf/types/known/timestamppb"

	pb "github.com/AlanIsaacV/pocket-pilot/internal/gen/proto/pocket_pilot/v1/pocket_pilot/v1"
	"github.com/AlanIsaacV/pocket-pilot/internal/middleware"
)

// Handler implements pb.SyncServiceServer.
type Handler struct {
	pb.UnimplementedSyncServiceServer
	store *CursorStore
}

func NewHandler(store *CursorStore) *Handler {
	return &Handler{store: store}
}

func (h *Handler) GetSyncStatus(
	ctx context.Context,
	_ *pb.GetSyncStatusRequest,
) (*pb.GetSyncStatusResponse, error) {
	userID, err := middleware.UserIDFromCtx(ctx)
	if err != nil {
		return nil, err
	}

	cursors, err := h.store.GetAll(ctx, userID)
	if err != nil {
		return nil, err
	}

	out := make(map[string]*timestamppb.Timestamp, len(cursors))
	for entity, at := range cursors {
		out[string(entity)] = timestamppb.New(at)
	}
	return &pb.GetSyncStatusResponse{
		Cursors:  out,
		SyncedAt: timestamppb.New(time.Now().UTC()),
	}, nil
}
