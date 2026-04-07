package jwks

import (
	"encoding/base64"
	"encoding/json"
	"fmt"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

type Claims struct {
	Email string
	Sub   string
}

type Verifier struct {
	keyStore       *KeyStore
	googleAudience string
	appleAudience  string
}

func NewVerifier(keyStore *KeyStore, googleAudience, appleAudience string) *Verifier {
	return &Verifier{
		keyStore:       keyStore,
		googleAudience: googleAudience,
		appleAudience:  appleAudience,
	}
}

func (v *Verifier) Verify(provider, idToken string) (*Claims, error) {
	if provider != "google" && provider != "apple" {
		return nil, fmt.Errorf("unsupported provider: %s", provider)
	}

	kid, err := extractKid(idToken)
	if err != nil {
		return nil, fmt.Errorf("extract kid: %w", err)
	}

	pubKey, err := v.keyStore.GetKey(provider, kid)
	if err != nil {
		return nil, fmt.Errorf("get key: %w", err)
	}

	token, err := jwt.Parse(idToken, func(t *jwt.Token) (any, error) {
		if _, ok := t.Method.(*jwt.SigningMethodRSA); !ok {
			return nil, fmt.Errorf("unexpected signing method: %v", t.Header["alg"])
		}
		return pubKey, nil
	}, jwt.WithExpirationRequired())
	if err != nil {
		return nil, fmt.Errorf("parse token: %w", err)
	}

	mapClaims, ok := token.Claims.(jwt.MapClaims)
	if !ok || !token.Valid {
		return nil, fmt.Errorf("invalid token claims")
	}

	expectedAud := v.audienceFor(provider)
	if expectedAud != "" {
		aud, _ := mapClaims["aud"].(string)
		if aud != expectedAud {
			return nil, fmt.Errorf("audience mismatch: got %q, want %q", aud, expectedAud)
		}
	}

	if exp, ok := mapClaims["exp"].(float64); ok {
		if time.Unix(int64(exp), 0).Before(time.Now()) {
			return nil, fmt.Errorf("token expired")
		}
	}

	email, _ := mapClaims["email"].(string)
	sub, _ := mapClaims["sub"].(string)
	if email == "" || sub == "" {
		return nil, fmt.Errorf("missing email or sub in token claims")
	}

	return &Claims{Email: email, Sub: sub}, nil
}

func (v *Verifier) audienceFor(provider string) string {
	switch provider {
	case "google":
		return v.googleAudience
	case "apple":
		return v.appleAudience
	default:
		return ""
	}
}

type jwtHeader struct {
	Kid string `json:"kid"`
}

func extractKid(tokenString string) (string, error) {
	dot := -1
	for i, c := range tokenString {
		if c == '.' {
			dot = i
			break
		}
	}
	if dot == -1 {
		return "", fmt.Errorf("invalid JWT format")
	}

	headerBytes, err := base64.RawURLEncoding.DecodeString(tokenString[:dot])
	if err != nil {
		return "", fmt.Errorf("decode header: %w", err)
	}

	var header jwtHeader
	if err := json.Unmarshal(headerBytes, &header); err != nil {
		return "", fmt.Errorf("unmarshal header: %w", err)
	}

	if header.Kid == "" {
		return "", fmt.Errorf("kid not found in JWT header")
	}
	return header.Kid, nil
}
