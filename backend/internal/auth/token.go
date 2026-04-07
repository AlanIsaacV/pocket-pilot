package auth

import (
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"time"

	"github.com/golang-jwt/jwt/v5"
	"github.com/google/uuid"
)

const (
	accessTokenExpiry  = 15 * time.Minute
	refreshTokenExpiry = 30 * 24 * time.Hour
	refreshTokenBytes  = 32
)

type TokenService struct {
	jwtSecret []byte
}

func NewTokenService(jwtSecret string) *TokenService {
	return &TokenService{jwtSecret: []byte(jwtSecret)}
}

func (ts *TokenService) GenerateAccessToken(userID uuid.UUID, email string) (string, error) {
	now := time.Now()
	claims := jwt.MapClaims{
		"sub":   userID.String(),
		"email": email,
		"iat":   now.Unix(),
		"exp":   now.Add(accessTokenExpiry).Unix(),
	}
	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	return token.SignedString(ts.jwtSecret)
}

func (ts *TokenService) GenerateRefreshToken() (raw string, hash string, err error) {
	b := make([]byte, refreshTokenBytes)
	if _, err := rand.Read(b); err != nil {
		return "", "", fmt.Errorf("generate random bytes: %w", err)
	}
	raw = hex.EncodeToString(b)
	hash = HashToken(raw)
	return raw, hash, nil
}

func (ts *TokenService) RefreshTokenExpiresAt() time.Time {
	return time.Now().Add(refreshTokenExpiry)
}

func (ts *TokenService) ValidateAccessToken(tokenString string) (uuid.UUID, error) {
	token, err := jwt.Parse(tokenString, func(t *jwt.Token) (any, error) {
		if _, ok := t.Method.(*jwt.SigningMethodHMAC); !ok {
			return nil, fmt.Errorf("unexpected signing method: %v", t.Header["alg"])
		}
		return ts.jwtSecret, nil
	}, jwt.WithExpirationRequired())
	if err != nil {
		return uuid.UUID{}, fmt.Errorf("parse access token: %w", err)
	}

	claims, ok := token.Claims.(jwt.MapClaims)
	if !ok || !token.Valid {
		return uuid.UUID{}, fmt.Errorf("invalid token claims")
	}

	sub, _ := claims["sub"].(string)
	if sub == "" {
		return uuid.UUID{}, fmt.Errorf("missing sub claim")
	}

	userID, err := uuid.Parse(sub)
	if err != nil {
		return uuid.UUID{}, fmt.Errorf("invalid sub claim: %w", err)
	}
	return userID, nil
}

func HashToken(token string) string {
	h := sha256.Sum256([]byte(token))
	return hex.EncodeToString(h[:])
}
