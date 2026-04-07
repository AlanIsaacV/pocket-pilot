package auth

import (
	"context"
	"time"

	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
	"google.golang.org/protobuf/types/known/emptypb"

	pb "github.com/AlanIsaacV/pocket-pilot/internal/gen/proto/pocket_pilot/v1/pocket_pilot/v1"
	"github.com/AlanIsaacV/pocket-pilot/internal/jwks"
	"github.com/AlanIsaacV/pocket-pilot/internal/middleware"
)

type Handler struct {
	pb.UnimplementedAuthServiceServer
	repo     *Repository
	verifier *jwks.Verifier
	tokens   *TokenService
}

func NewHandler(repo *Repository, verifier *jwks.Verifier, tokens *TokenService) *Handler {
	return &Handler{
		repo:     repo,
		verifier: verifier,
		tokens:   tokens,
	}
}

func (h *Handler) OAuthLogin(ctx context.Context, req *pb.OAuthLoginRequest) (*pb.AuthResponse, error) {
	if req.Provider == "" {
		return nil, status.Error(codes.InvalidArgument, "provider is required")
	}
	if req.IdToken == "" {
		return nil, status.Error(codes.InvalidArgument, "id_token is required")
	}

	claims, err := h.verifier.Verify(req.Provider, req.IdToken)
	if err != nil {
		return nil, status.Errorf(codes.Unauthenticated, "invalid id_token: %v", err)
	}

	user, err := h.repo.FindUserByEmail(ctx, claims.Email)
	if err != nil {
		return nil, status.Errorf(codes.Internal, "find user: %v", err)
	}

	if user != nil {
		if err := h.repo.LinkIdentity(ctx, user.ID, req.Provider, claims.Sub); err != nil {
			return nil, status.Errorf(codes.Internal, "link identity: %v", err)
		}
	} else {
		user, err = h.repo.CreateUserWithIdentity(ctx, claims.Email, req.Provider, claims.Sub)
		if err != nil {
			return nil, status.Errorf(codes.Internal, "create user: %v", err)
		}
	}

	accessToken, err := h.tokens.GenerateAccessToken(user.ID, user.Email)
	if err != nil {
		return nil, status.Errorf(codes.Internal, "generate access token: %v", err)
	}

	rawRefresh, hashRefresh, err := h.tokens.GenerateRefreshToken()
	if err != nil {
		return nil, status.Errorf(codes.Internal, "generate refresh token: %v", err)
	}

	if err := h.repo.SaveRefreshToken(ctx, user.ID, hashRefresh, h.tokens.RefreshTokenExpiresAt()); err != nil {
		return nil, status.Errorf(codes.Internal, "save refresh token: %v", err)
	}

	return &pb.AuthResponse{
		AccessToken:  accessToken,
		RefreshToken: rawRefresh,
		UserId:       user.ID.String(),
	}, nil
}

func (h *Handler) RefreshToken(ctx context.Context, req *pb.RefreshRequest) (*pb.AuthResponse, error) {
	if req.RefreshToken == "" {
		return nil, status.Error(codes.InvalidArgument, "refresh_token is required")
	}

	hash := HashToken(req.RefreshToken)

	record, err := h.repo.FindRefreshToken(ctx, hash)
	if err != nil {
		return nil, status.Errorf(codes.Internal, "find refresh token: %v", err)
	}
	if record == nil {
		return nil, status.Error(codes.Unauthenticated, "invalid refresh token")
	}
	if record.IsRevoked {
		return nil, status.Error(codes.Unauthenticated, "refresh token has been revoked")
	}
	if record.ExpiresAt.Before(time.Now()) {
		return nil, status.Error(codes.Unauthenticated, "refresh token expired")
	}

	if err := h.repo.RevokeToken(ctx, record.ID); err != nil {
		return nil, status.Errorf(codes.Internal, "revoke old token: %v", err)
	}

	user, err := h.repo.FindUserByID(ctx, record.UserID)
	if err != nil {
		return nil, status.Errorf(codes.Internal, "find user: %v", err)
	}
	if user == nil {
		return nil, status.Error(codes.Internal, "user not found for refresh token")
	}

	accessToken, err := h.tokens.GenerateAccessToken(user.ID, user.Email)
	if err != nil {
		return nil, status.Errorf(codes.Internal, "generate access token: %v", err)
	}

	rawRefresh, hashRefresh, err := h.tokens.GenerateRefreshToken()
	if err != nil {
		return nil, status.Errorf(codes.Internal, "generate refresh token: %v", err)
	}

	if err := h.repo.SaveRefreshToken(ctx, user.ID, hashRefresh, h.tokens.RefreshTokenExpiresAt()); err != nil {
		return nil, status.Errorf(codes.Internal, "save refresh token: %v", err)
	}

	return &pb.AuthResponse{
		AccessToken:  accessToken,
		RefreshToken: rawRefresh,
		UserId:       user.ID.String(),
	}, nil
}

func (h *Handler) Logout(ctx context.Context, req *pb.LogoutRequest) (*emptypb.Empty, error) {
	if req.RefreshToken == "" {
		return nil, status.Error(codes.InvalidArgument, "refresh_token is required")
	}

	hash := HashToken(req.RefreshToken)
	if err := h.repo.RevokeTokenByHash(ctx, hash); err != nil {
		return nil, status.Errorf(codes.Internal, "revoke token: %v", err)
	}

	return &emptypb.Empty{}, nil
}

func (h *Handler) RevokeAllSessions(ctx context.Context, _ *emptypb.Empty) (*emptypb.Empty, error) {
	userID, err := middleware.UserIDFromCtx(ctx)
	if err != nil {
		return nil, err
	}

	if err := h.repo.RevokeAllTokens(ctx, userID); err != nil {
		return nil, status.Errorf(codes.Internal, "revoke all sessions: %v", err)
	}

	return &emptypb.Empty{}, nil
}
