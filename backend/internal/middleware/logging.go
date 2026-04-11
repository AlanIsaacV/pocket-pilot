package middleware

import (
	"context"
	"log/slog"
	"time"

	"google.golang.org/grpc"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

// NewUnaryLoggingInterceptor returns a gRPC interceptor that logs every RPC
// call with its method, user, duration and status code. Errors are logged at
// ERROR level; successful calls at INFO.
func NewUnaryLoggingInterceptor() grpc.UnaryServerInterceptor {
	return func(ctx context.Context, req any, info *grpc.UnaryServerInfo, handler grpc.UnaryHandler) (any, error) {
		start := time.Now()

		resp, err := handler(ctx, req)

		duration := time.Since(start)
		code := status.Code(err)

		attrs := []slog.Attr{
			slog.String("method", info.FullMethod),
			slog.String("code", code.String()),
			slog.Duration("duration", duration),
		}

		// Best-effort: extract user_id if it was injected by the auth interceptor.
		if uid, ok := ctx.Value(ContextUserIDKey).(string); ok && uid != "" {
			attrs = append(attrs, slog.String("user_id", uid))
		}

		if err != nil {
			attrs = append(attrs, slog.String("error", err.Error()))
			level := slog.LevelError
			if code == codes.InvalidArgument || code == codes.Unauthenticated {
				level = slog.LevelWarn
			}
			slog.LogAttrs(ctx, level, "rpc error", attrs...)
		} else {
			slog.LogAttrs(ctx, slog.LevelInfo, "rpc ok", attrs...)
		}

		return resp, err
	}
}
