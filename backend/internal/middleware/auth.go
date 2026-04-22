package middleware

import (
	"context"
	"strings"

	"github.com/golang-jwt/jwt/v5"
	"github.com/google/uuid"
	"google.golang.org/grpc"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/metadata"
	"google.golang.org/grpc/status"
)

type contextKey string

const ContextUserIDKey contextKey = "user_id"

var publicMethods = map[string]bool{
	"/pocket_pilot.v1.AuthService/OAuthLogin":   true,
	"/pocket_pilot.v1.AuthService/RefreshToken": true,
	"/pocket_pilot.v1.AuthService/Logout":       true,
}

// NewUnaryAuthInterceptor builds the auth interceptor for the gRPC server.
//
//   - publicMethods always bypass (see top of file).
//   - Methods in adminMethods bypass JWT when the caller presents
//     "Authorization: Bearer <adminToken>". adminToken "" disables the path.
//   - Everything else validates the JWT with jwtSecret.
//
// Admin-authenticated calls do NOT carry a user_id in context; handlers for
// those RPCs must not use middleware.UserIDFromCtx.
func NewUnaryAuthInterceptor(jwtSecret, adminToken string, adminMethods map[string]bool) grpc.UnaryServerInterceptor {
	secret := []byte(jwtSecret)

	return func(ctx context.Context, req any, info *grpc.UnaryServerInfo, handler grpc.UnaryHandler) (any, error) {
		if publicMethods[info.FullMethod] {
			return handler(ctx, req)
		}

		md, ok := metadata.FromIncomingContext(ctx)
		if !ok {
			return nil, status.Error(codes.Unauthenticated, "metadata missing")
		}

		authHeader := md["authorization"]
		if len(authHeader) == 0 {
			return nil, status.Error(codes.Unauthenticated, "authorization token missing")
		}

		if adminToken != "" && adminMethods[info.FullMethod] {
			if authHeader[0] == "Bearer "+adminToken {
				return handler(ctx, req)
			}
		}

		tokenString := strings.TrimPrefix(authHeader[0], "Bearer ")
		if tokenString == authHeader[0] {
			return nil, status.Error(codes.Unauthenticated, "invalid authorization format")
		}

		token, err := jwt.Parse(tokenString, func(t *jwt.Token) (any, error) {
			if _, ok := t.Method.(*jwt.SigningMethodHMAC); !ok {
				return nil, status.Errorf(codes.Unauthenticated, "unexpected signing method: %v", t.Header["alg"])
			}
			return secret, nil
		}, jwt.WithExpirationRequired())
		if err != nil {
			return nil, status.Errorf(codes.Unauthenticated, "invalid token: %v", err)
		}

		claims, ok := token.Claims.(jwt.MapClaims)
		if !ok || !token.Valid {
			return nil, status.Error(codes.Unauthenticated, "invalid token claims")
		}

		sub, _ := claims["sub"].(string)
		if sub == "" {
			return nil, status.Error(codes.Unauthenticated, "missing sub claim")
		}

		newCtx := context.WithValue(ctx, ContextUserIDKey, sub)
		return handler(newCtx, req)
	}
}

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
