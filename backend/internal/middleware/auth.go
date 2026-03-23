package middleware

import (
	"context"
	"strings"

	"github.com/google/uuid"
	"google.golang.org/grpc"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/metadata"
	"google.golang.org/grpc/status"
)

// MVP constants — in production these would come from a real auth system (JWT, etc.).
const (
	HardcodedMVPToken  = "MVP-TOKEN-123"
	HardcodedMVPUserID = "00000000-0000-0000-0000-000000000001"
)

type contextKey string

// ContextUserIDKey is the key used to store/retrieve the authenticated user ID in the context.
const ContextUserIDKey contextKey = "user_id"

// UnaryAuthInterceptor validates the Bearer token from the gRPC metadata and injects
// the user ID into the request context. All handlers read user ID via UserIDFromCtx.
func UnaryAuthInterceptor(ctx context.Context, req interface{}, _ *grpc.UnaryServerInfo, handler grpc.UnaryHandler) (interface{}, error) {
	md, ok := metadata.FromIncomingContext(ctx)
	if !ok {
		return nil, status.Error(codes.Unauthenticated, "metadata missing")
	}

	authHeader := md["authorization"]
	if len(authHeader) == 0 {
		return nil, status.Error(codes.Unauthenticated, "authorization token missing")
	}

	token := strings.TrimPrefix(authHeader[0], "Bearer ")
	if token != HardcodedMVPToken {
		return nil, status.Error(codes.Unauthenticated, "invalid token")
	}

	newCtx := context.WithValue(ctx, ContextUserIDKey, HardcodedMVPUserID)
	return handler(newCtx, req)
}

// UserIDFromCtx extracts the authenticated user ID from the context.
// Returns an error if the context was not set up by UnaryAuthInterceptor.
func UserIDFromCtx(ctx context.Context) (uuid.UUID, error) {
	val, ok := ctx.Value(ContextUserIDKey).(string)
	if !ok || val == "" {
		return uuid.UUID{}, status.Error(codes.Unauthenticated, "user not authenticated")
	}
	id, err := uuid.Parse(val)
	if err != nil {
		return uuid.UUID{}, status.Errorf(codes.Internal, "invalid user_id in context: %v", err)
	}
	return id, nil
}
