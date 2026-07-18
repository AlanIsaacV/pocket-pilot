# Custom Auth con Social Login Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement custom authentication using Google/Apple social login with JWKS validation, JWT access tokens, and opaque refresh tokens.

**Architecture:** Flutter obtains OIDC id_token from native SDKs, sends it to Go backend via gRPC. Backend validates the token cryptographically using manual JWKS (fetching RSA public keys from Google/Apple), then issues its own JWT access token (HS256, 15 min) and opaque refresh token (30 days). Account linking by email. Refresh token rotation on every use.

**Tech Stack:** Go (pgx, golang-jwt/jwt/v5, crypto/rsa), Flutter/Dart (google_sign_in, sign_in_with_apple, flutter_secure_storage, grpc), PostgreSQL, gRPC/Protobuf.

---

## File Map

### New files

| File | Responsibility |
|------|---------------|
| `proto/pocket_pilot/v1/auth_service.proto` | gRPC contract for AuthService |
| `backend/internal/auth/model.go` | Structs: User, UserIdentity, RefreshTokenRecord |
| `backend/internal/auth/repository.go` | DB queries: users, user_identities, refresh_tokens |
| `backend/internal/auth/token.go` | JWT generation (HS256) + opaque refresh token generation |
| `backend/internal/auth/handler.go` | AuthServiceServer: OAuthLogin, RefreshToken, Logout, RevokeAllSessions |
| `backend/internal/jwks/jwks.go` | JWKS fetch, RSA key parsing, in-memory cache with TTL |
| `backend/internal/jwks/verify.go` | Validate id_token: RSA signature, exp, aud; return claims |
| `frontend/lib/src/core/auth/token_store.dart` | flutter_secure_storage wrapper for tokens |
| `frontend/lib/src/core/auth/auth_service.dart` | Native SDK calls + gRPC AuthService client |
| `frontend/lib/src/core/auth/auth_provider.dart` | ChangeNotifier: auth state, login, logout, revokeAll |
| `frontend/lib/src/ui/screens/login/login_screen.dart` | Login screen UI |

### Modified files

| File | Change |
|------|--------|
| `backend/migrations/001_initial_schema.sql` | Add users, user_identities, refresh_tokens tables + FK refs |
| `backend/internal/config/config.go` | Add GoogleClientID, AppleClientID, JWTSecret fields |
| `backend/internal/middleware/auth.go` | Replace MVP token with JWT validation + route exclusions |
| `backend/cmd/server/main.go` | Wire auth handler, pass JWTSecret to middleware |
| `backend/go.mod` | Add golang-jwt/jwt/v5 dependency |
| `frontend/pubspec.yaml` | Add google_sign_in, sign_in_with_apple, flutter_secure_storage |
| `frontend/lib/src/core/grpc/auth_interceptor.dart` | Replace MVP token with TokenStore + refresh retry logic |
| `frontend/lib/main.dart` | Add AuthProvider, TokenStore to MultiProvider; remove kMvpUserId refs |
| `frontend/lib/src/ui/router.dart` | Add login route, redirect guard with AuthProvider |
| `frontend/lib/src/ui/app.dart` | Pass AuthProvider as refreshListenable to router |

---

## Task 1: Database Schema — Auth Tables

**Files:**
- Modify: `backend/migrations/001_initial_schema.sql`

- [ ] **Step 1: Add auth tables to the migration file**

Open `backend/migrations/001_initial_schema.sql`. Add the following **before** the `accounts` table (users must exist first so FKs work):

```sql
-- ── Auth ─────────────────────────────────────────────────────────────────────

CREATE TABLE users (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email       TEXT NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE user_identities (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id       UUID NOT NULL REFERENCES users(id),
    provider      TEXT NOT NULL,
    provider_id   TEXT NOT NULL,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(provider, provider_id)
);

CREATE TABLE refresh_tokens (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     UUID NOT NULL REFERENCES users(id),
    token_hash  TEXT NOT NULL,
    expires_at  TIMESTAMPTZ NOT NULL,
    is_revoked  BOOLEAN NOT NULL DEFAULT FALSE,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_refresh_tokens_user_id ON refresh_tokens(user_id);
CREATE UNIQUE INDEX idx_refresh_tokens_token_hash ON refresh_tokens(token_hash);

CREATE TRIGGER set_updated_at_users
    BEFORE UPDATE ON users
    FOR EACH ROW
EXECUTE FUNCTION trigger_set_updated_at();
```

Note: The `trigger_set_updated_at()` function is defined later in the file. Move the function definition **before** the auth tables, or move the trigger creation to after the function definition. The simplest approach: insert the auth tables after the existing `CREATE OR REPLACE FUNCTION trigger_set_updated_at()` block (line 232), and add the trigger right there. But since other tables also reference `users`, we need the `CREATE TABLE users` before `accounts`. So instead:

**Recommended approach:** Insert the 3 table definitions + indexes at the very top of the file (before `CREATE TYPE account_type`). Insert the `CREATE TRIGGER set_updated_at_users` block alongside the other triggers at the bottom of the file (after line 293).

- [ ] **Step 2: Add FK references from existing tables to users**

Add `REFERENCES users(id)` to the `user_id` column of every existing table. For each table, change:

```sql
-- accounts (line 4):
user_id            uuid         NOT NULL,
-- becomes:
user_id            uuid         NOT NULL REFERENCES users(id),
```

Apply the same change to: `accounts`, `categories`, `tags`, `yield_configs`, `transaction_templates`, `transactions`, `user_preferences` (the user_id in the PRIMARY KEY), `goals`, `budgets`, `ai_usage`, `ai_unsupported_tool_reports`.

For `user_preferences`, the PK is `(user_id, pref_key)` — add a separate FK:

```sql
-- After the user_preferences CREATE TABLE, before the indexes:
ALTER TABLE user_preferences ADD CONSTRAINT fk_user_preferences_user FOREIGN KEY (user_id) REFERENCES users(id);
```

Actually, simpler: just add `REFERENCES users(id)` inline to the `user_id` column definition in each table. The composite PK still works.

- [ ] **Step 3: Re-apply migration**

```bash
cd /Volumes/rusty-drive/projects/pocket-pilot && make down && make migrate
```

Expected: All tables created successfully, no errors.

- [ ] **Step 4: Verify schema**

```bash
docker exec -i pocket-pilot-db psql -U pocket_pilot -d pocket_pilot -c "\dt"
```

Expected: `users`, `user_identities`, `refresh_tokens` appear in the table list alongside existing tables.

```bash
docker exec -i pocket-pilot-db psql -U pocket_pilot -d pocket_pilot -c "\d users"
docker exec -i pocket-pilot-db psql -U pocket_pilot -d pocket_pilot -c "\d user_identities"
docker exec -i pocket-pilot-db psql -U pocket_pilot -d pocket_pilot -c "\d refresh_tokens"
```

- [ ] **Step 5: Commit**

```bash
git add backend/migrations/001_initial_schema.sql
git commit -m "feat(auth): add users, user_identities, refresh_tokens tables and FK refs"
```

---

## Task 2: Proto Contract — AuthService

**Files:**
- Create: `proto/pocket_pilot/v1/auth_service.proto`

- [ ] **Step 1: Create the proto file**

Create `proto/pocket_pilot/v1/auth_service.proto`:

```protobuf
syntax = "proto3";

package pocket_pilot.v1;

import "google/protobuf/empty.proto";

option go_package = "github.com/AlanIsaacV/pocket-pilot/backend/internal/gen/proto/pocket_pilot/v1;pocketpilotv1";

message OAuthLoginRequest {
  string provider = 1;
  string id_token = 2;
}

message AuthResponse {
  string access_token = 1;
  string refresh_token = 2;
  string user_id = 3;
}

message RefreshRequest {
  string refresh_token = 1;
}

message LogoutRequest {
  string refresh_token = 1;
}

service AuthService {
  rpc OAuthLogin(OAuthLoginRequest) returns (AuthResponse);
  rpc RefreshToken(RefreshRequest) returns (AuthResponse);
  rpc Logout(LogoutRequest) returns (google.protobuf.Empty);
  rpc RevokeAllSessions(google.protobuf.Empty) returns (google.protobuf.Empty);
}
```

- [ ] **Step 2: Generate code**

```bash
cd /Volumes/rusty-drive/projects/pocket-pilot && make proto
```

Expected: No errors. Generated files appear in:
- `backend/internal/gen/proto/pocket_pilot/v1/` (Go: `auth_service.pb.go`, `auth_service_grpc.pb.go`)
- `frontend/lib/src/generated/pocket_pilot/v1/` (Dart: `auth_service.pb.dart`, `auth_service.pbgrpc.dart`, etc.)

- [ ] **Step 3: Verify generated Go code compiles**

```bash
cd /Volumes/rusty-drive/projects/pocket-pilot/backend && go build ./...
```

Expected: Build succeeds.

- [ ] **Step 4: Commit**

```bash
git add proto/pocket_pilot/v1/auth_service.proto
git add backend/internal/gen/
git add frontend/lib/src/generated/
git commit -m "feat(auth): add AuthService proto contract and generated code"
```

---

## Task 3: Backend — Config + Go dependency

**Files:**
- Modify: `backend/internal/config/config.go`
- Modify: `backend/go.mod` (via `go get`)

- [ ] **Step 1: Add golang-jwt dependency**

```bash
cd /Volumes/rusty-drive/projects/pocket-pilot/backend && go get github.com/golang-jwt/jwt/v5
```

Expected: `go.mod` and `go.sum` updated.

- [ ] **Step 2: Add auth config fields**

Edit `backend/internal/config/config.go`. Replace the entire file content:

```go
package config

import (
	"fmt"
	"os"
	"strconv"
)

type Config struct {
	DatabaseURL         string
	GRPCPort            string
	GeminiAPIKey        string
	AIDailyRequestLimit int
	AIMonthlyTokenLimit int
	GoogleClientID      string
	AppleClientID       string
	JWTSecret           string
}

func Load() (Config, error) {
	dbURL := os.Getenv("DATABASE_URL")
	if dbURL == "" {
		return Config{}, fmt.Errorf("DATABASE_URL environment variable is required")
	}

	port := os.Getenv("GRPC_PORT")
	if port == "" {
		port = "50051"
	}

	geminiKey := os.Getenv("GEMINI_API_KEY")
	if geminiKey == "" {
		return Config{}, fmt.Errorf("GEMINI_API_KEY environment variable is required")
	}

	jwtSecret := os.Getenv("JWT_SECRET")
	if jwtSecret == "" {
		return Config{}, fmt.Errorf("JWT_SECRET environment variable is required")
	}

	googleClientID := os.Getenv("GOOGLE_CLIENT_ID")
	appleClientID := os.Getenv("APPLE_CLIENT_ID")

	dailyLimit := 50
	if v := os.Getenv("AI_DAILY_REQUEST_LIMIT"); v != "" {
		if n, err := strconv.Atoi(v); err == nil && n > 0 {
			dailyLimit = n
		}
	}

	monthlyTokenLimit := 500_000
	if v := os.Getenv("AI_MONTHLY_TOKEN_LIMIT"); v != "" {
		if n, err := strconv.Atoi(v); err == nil && n > 0 {
			monthlyTokenLimit = n
		}
	}

	return Config{
		DatabaseURL:         dbURL,
		GRPCPort:            port,
		GeminiAPIKey:        geminiKey,
		AIDailyRequestLimit: dailyLimit,
		AIMonthlyTokenLimit: monthlyTokenLimit,
		GoogleClientID:      googleClientID,
		AppleClientID:       appleClientID,
		JWTSecret:           jwtSecret,
	}, nil
}
```

- [ ] **Step 3: Verify build**

```bash
cd /Volumes/rusty-drive/projects/pocket-pilot/backend && go build ./...
```

Expected: Build succeeds.

- [ ] **Step 4: Commit**

```bash
git add backend/internal/config/config.go backend/go.mod backend/go.sum
git commit -m "feat(auth): add JWT_SECRET, GOOGLE_CLIENT_ID, APPLE_CLIENT_ID to config"
```

---

## Task 4: Backend — Auth Models

**Files:**
- Create: `backend/internal/auth/model.go`

- [ ] **Step 1: Create the model file**

Create `backend/internal/auth/model.go`:

```go
package auth

import (
	"time"

	"github.com/google/uuid"
)

type User struct {
	ID        uuid.UUID
	Email     string
	CreatedAt time.Time
	UpdatedAt time.Time
}

type UserIdentity struct {
	ID         uuid.UUID
	UserID     uuid.UUID
	Provider   string
	ProviderID string
	CreatedAt  time.Time
}

type RefreshTokenRecord struct {
	ID        uuid.UUID
	UserID    uuid.UUID
	TokenHash string
	ExpiresAt time.Time
	IsRevoked bool
	CreatedAt time.Time
}
```

- [ ] **Step 2: Verify build**

```bash
cd /Volumes/rusty-drive/projects/pocket-pilot/backend && go build ./...
```

Expected: Build succeeds.

- [ ] **Step 3: Commit**

```bash
git add backend/internal/auth/model.go
git commit -m "feat(auth): add User, UserIdentity, RefreshTokenRecord models"
```

---

## Task 5: Backend — Auth Repository

**Files:**
- Create: `backend/internal/auth/repository.go`

- [ ] **Step 1: Create the repository file**

Create `backend/internal/auth/repository.go`:

```go
package auth

import (
	"context"
	"errors"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

type Repository struct {
	pool *pgxpool.Pool
}

func NewRepository(pool *pgxpool.Pool) *Repository {
	return &Repository{pool: pool}
}

// FindUserByEmail returns the first user with the given email, or nil if not found.
func (r *Repository) FindUserByEmail(ctx context.Context, email string) (*User, error) {
	row := r.pool.QueryRow(ctx,
		`SELECT id, email, created_at, updated_at FROM users WHERE email = $1 LIMIT 1`,
		email,
	)
	u := &User{}
	err := row.Scan(&u.ID, &u.Email, &u.CreatedAt, &u.UpdatedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	return u, nil
}

// CreateUserWithIdentity inserts a new user and links the provider identity in a single transaction.
// Uses SERIALIZABLE isolation to prevent race conditions on concurrent first-login with the same email.
func (r *Repository) CreateUserWithIdentity(ctx context.Context, email, provider, providerID string) (*User, error) {
	tx, err := r.pool.BeginTx(ctx, pgx.TxOptions{IsoLevel: pgx.Serializable})
	if err != nil {
		return nil, err
	}
	defer tx.Rollback(ctx)

	// Double-check inside the transaction.
	var existing uuid.UUID
	err = tx.QueryRow(ctx,
		`SELECT id FROM users WHERE email = $1 LIMIT 1`,
		email,
	).Scan(&existing)
	if err == nil {
		// User was created concurrently — link identity to existing user and return.
		_, err = tx.Exec(ctx,
			`INSERT INTO user_identities (user_id, provider, provider_id) VALUES ($1, $2, $3)
			 ON CONFLICT (provider, provider_id) DO NOTHING`,
			existing, provider, providerID,
		)
		if err != nil {
			return nil, err
		}
		if err := tx.Commit(ctx); err != nil {
			return nil, err
		}
		u := &User{ID: existing, Email: email}
		return u, nil
	}
	if !errors.Is(err, pgx.ErrNoRows) {
		return nil, err
	}

	u := &User{}
	err = tx.QueryRow(ctx,
		`INSERT INTO users (email) VALUES ($1) RETURNING id, email, created_at, updated_at`,
		email,
	).Scan(&u.ID, &u.Email, &u.CreatedAt, &u.UpdatedAt)
	if err != nil {
		return nil, err
	}

	_, err = tx.Exec(ctx,
		`INSERT INTO user_identities (user_id, provider, provider_id) VALUES ($1, $2, $3)`,
		u.ID, provider, providerID,
	)
	if err != nil {
		return nil, err
	}

	if err := tx.Commit(ctx); err != nil {
		return nil, err
	}
	return u, nil
}

// LinkIdentity adds a provider identity to an existing user. No-op if the identity already exists.
func (r *Repository) LinkIdentity(ctx context.Context, userID uuid.UUID, provider, providerID string) error {
	_, err := r.pool.Exec(ctx,
		`INSERT INTO user_identities (user_id, provider, provider_id) VALUES ($1, $2, $3)
		 ON CONFLICT (provider, provider_id) DO NOTHING`,
		userID, provider, providerID,
	)
	return err
}

// SaveRefreshToken stores the hash of a refresh token.
func (r *Repository) SaveRefreshToken(ctx context.Context, userID uuid.UUID, tokenHash string, expiresAt time.Time) error {
	_, err := r.pool.Exec(ctx,
		`INSERT INTO refresh_tokens (user_id, token_hash, expires_at) VALUES ($1, $2, $3)`,
		userID, tokenHash, expiresAt,
	)
	return err
}

// FindRefreshToken looks up a non-revoked, non-expired refresh token by its hash.
func (r *Repository) FindRefreshToken(ctx context.Context, tokenHash string) (*RefreshTokenRecord, error) {
	row := r.pool.QueryRow(ctx,
		`SELECT id, user_id, token_hash, expires_at, is_revoked, created_at
		 FROM refresh_tokens
		 WHERE token_hash = $1`,
		tokenHash,
	)
	rt := &RefreshTokenRecord{}
	err := row.Scan(&rt.ID, &rt.UserID, &rt.TokenHash, &rt.ExpiresAt, &rt.IsRevoked, &rt.CreatedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	return rt, nil
}

// RevokeToken marks a single refresh token as revoked by its ID.
func (r *Repository) RevokeToken(ctx context.Context, tokenID uuid.UUID) error {
	_, err := r.pool.Exec(ctx,
		`UPDATE refresh_tokens SET is_revoked = TRUE WHERE id = $1`,
		tokenID,
	)
	return err
}

// RevokeTokenByHash marks a single refresh token as revoked by its hash.
func (r *Repository) RevokeTokenByHash(ctx context.Context, tokenHash string) error {
	_, err := r.pool.Exec(ctx,
		`UPDATE refresh_tokens SET is_revoked = TRUE WHERE token_hash = $1 AND is_revoked = FALSE`,
		tokenHash,
	)
	return err
}

// RevokeAllTokens marks all active refresh tokens for a user as revoked.
func (r *Repository) RevokeAllTokens(ctx context.Context, userID uuid.UUID) error {
	_, err := r.pool.Exec(ctx,
		`UPDATE refresh_tokens SET is_revoked = TRUE WHERE user_id = $1 AND is_revoked = FALSE`,
		userID,
	)
	return err
}

// FindUserByID returns a user by their ID.
func (r *Repository) FindUserByID(ctx context.Context, userID uuid.UUID) (*User, error) {
	row := r.pool.QueryRow(ctx,
		`SELECT id, email, created_at, updated_at FROM users WHERE id = $1`,
		userID,
	)
	u := &User{}
	err := row.Scan(&u.ID, &u.Email, &u.CreatedAt, &u.UpdatedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	return u, nil
}
```

- [ ] **Step 2: Verify build**

```bash
cd /Volumes/rusty-drive/projects/pocket-pilot/backend && go build ./...
```

Expected: Build succeeds.

- [ ] **Step 3: Commit**

```bash
git add backend/internal/auth/repository.go
git commit -m "feat(auth): add auth repository with user CRUD and refresh token management"
```

---

## Task 6: Backend — JWKS Package

**Files:**
- Create: `backend/internal/jwks/jwks.go`
- Create: `backend/internal/jwks/verify.go`

- [ ] **Step 1: Create `jwks.go` — JWKS fetch and cache**

Create `backend/internal/jwks/jwks.go`:

```go
package jwks

import (
	"crypto/rsa"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"math/big"
	"net/http"
	"sync"
	"time"
)

const cacheTTL = 1 * time.Hour

var providerJWKSURLs = map[string]string{
	"google": "https://www.googleapis.com/oauth2/v3/certs",
	"apple":  "https://appleid.apple.com/auth/keys",
}

type jwkSet struct {
	Keys []jwk `json:"keys"`
}

type jwk struct {
	Kid string `json:"kid"`
	Kty string `json:"kty"`
	Alg string `json:"alg"`
	N   string `json:"n"`
	E   string `json:"e"`
}

type cachedKeys struct {
	keys      map[string]*rsa.PublicKey // kid → public key
	fetchedAt time.Time
}

type KeyStore struct {
	mu    sync.RWMutex
	cache map[string]*cachedKeys // provider → cached keys
}

func NewKeyStore() *KeyStore {
	return &KeyStore{
		cache: make(map[string]*cachedKeys),
	}
}

// GetKey returns the RSA public key for the given provider and kid.
// Fetches from the provider's JWKS endpoint if the cache is empty or expired.
func (ks *KeyStore) GetKey(provider, kid string) (*rsa.PublicKey, error) {
	jwksURL, ok := providerJWKSURLs[provider]
	if !ok {
		return nil, fmt.Errorf("unknown provider: %s", provider)
	}

	// Try cache first.
	ks.mu.RLock()
	cached, ok := ks.cache[provider]
	ks.mu.RUnlock()

	if ok && time.Since(cached.fetchedAt) < cacheTTL {
		if key, found := cached.keys[kid]; found {
			return key, nil
		}
	}

	// Cache miss or expired — fetch fresh keys.
	keys, err := fetchJWKS(jwksURL)
	if err != nil {
		return nil, fmt.Errorf("fetch JWKS for %s: %w", provider, err)
	}

	ks.mu.Lock()
	ks.cache[provider] = &cachedKeys{keys: keys, fetchedAt: time.Now()}
	ks.mu.Unlock()

	key, found := keys[kid]
	if !found {
		return nil, fmt.Errorf("kid %q not found in %s JWKS", kid, provider)
	}
	return key, nil
}

func fetchJWKS(url string) (map[string]*rsa.PublicKey, error) {
	resp, err := http.Get(url)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("JWKS endpoint returned %d", resp.StatusCode)
	}

	var set jwkSet
	if err := json.NewDecoder(resp.Body).Decode(&set); err != nil {
		return nil, fmt.Errorf("decode JWKS: %w", err)
	}

	keys := make(map[string]*rsa.PublicKey, len(set.Keys))
	for _, k := range set.Keys {
		if k.Kty != "RSA" {
			continue
		}
		pub, err := parseRSAPublicKey(k.N, k.E)
		if err != nil {
			return nil, fmt.Errorf("parse key kid=%s: %w", k.Kid, err)
		}
		keys[k.Kid] = pub
	}
	return keys, nil
}

func parseRSAPublicKey(nB64, eB64 string) (*rsa.PublicKey, error) {
	nBytes, err := base64.RawURLEncoding.DecodeString(nB64)
	if err != nil {
		return nil, fmt.Errorf("decode n: %w", err)
	}

	eBytes, err := base64.RawURLEncoding.DecodeString(eB64)
	if err != nil {
		return nil, fmt.Errorf("decode e: %w", err)
	}

	n := new(big.Int).SetBytes(nBytes)
	e := 0
	for _, b := range eBytes {
		e = e<<8 + int(b)
	}

	return &rsa.PublicKey{N: n, E: e}, nil
}
```

- [ ] **Step 2: Create `verify.go` — Token verification**

Create `backend/internal/jwks/verify.go`:

```go
package jwks

import (
	"crypto/rsa"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

// Claims holds the verified claims extracted from an OIDC id_token.
type Claims struct {
	Email string
	Sub   string // Provider-unique user ID
}

// Verifier validates OIDC id_tokens from Google and Apple.
type Verifier struct {
	keyStore      *KeyStore
	googleAudience string
	appleAudience  string
}

func NewVerifier(keyStore *KeyStore, googleAudience, appleAudience string) *Verifier {
	return &Verifier{
		keyStore:      keyStore,
		googleAudience: googleAudience,
		appleAudience:  appleAudience,
	}
}

// Verify validates the id_token for the given provider.
// It checks: RSA signature (RS256), expiration, and audience.
func (v *Verifier) Verify(provider, idToken string) (*Claims, error) {
	expectedAud := v.audienceFor(provider)
	if expectedAud == "" && provider != "google" && provider != "apple" {
		return nil, fmt.Errorf("unsupported provider: %s", provider)
	}

	// Extract kid from the unverified header.
	kid, err := extractKid(idToken)
	if err != nil {
		return nil, fmt.Errorf("extract kid: %w", err)
	}

	// Get the RSA public key from the cache/JWKS endpoint.
	pubKey, err := v.keyStore.GetKey(provider, kid)
	if err != nil {
		return nil, fmt.Errorf("get key: %w", err)
	}

	// Parse and verify the token.
	token, err := jwt.Parse(idToken, func(t *jwt.Token) (interface{}, error) {
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

	// Validate audience.
	if expectedAud != "" {
		aud, _ := mapClaims["aud"].(string)
		if aud != expectedAud {
			return nil, fmt.Errorf("audience mismatch: got %q, want %q", aud, expectedAud)
		}
	}

	// Validate expiration (belt-and-suspenders — jwt.Parse checks this, but be explicit).
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

// jwtHeader is the minimal structure we need from the JWT header.
type jwtHeader struct {
	Kid string `json:"kid"`
	Alg string `json:"alg"`
}

// extractKid decodes the JWT header without verifying the signature to get the kid.
func extractKid(tokenString string) (string, error) {
	// JWT format: header.payload.signature
	// Find the first dot.
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

// rsaPublicKeyFunc is a helper for tests — not used in production but prevents
// the import from being flagged as unused.
var _ = func() *rsa.PublicKey { return nil }
```

Remove the last two lines (`var _ = ...`) — they were a placeholder. The file should end after the `extractKid` function.

- [ ] **Step 3: Verify build**

```bash
cd /Volumes/rusty-drive/projects/pocket-pilot/backend && go build ./...
```

Expected: Build succeeds.

- [ ] **Step 4: Commit**

```bash
git add backend/internal/jwks/
git commit -m "feat(auth): add JWKS key store and OIDC token verifier"
```

---

## Task 7: Backend — Token Generation

**Files:**
- Create: `backend/internal/auth/token.go`

- [ ] **Step 1: Create the token generation file**

Create `backend/internal/auth/token.go`:

```go
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
	refreshTokenExpiry = 30 * 24 * time.Hour // 30 days
	refreshTokenBytes  = 32
)

type TokenService struct {
	jwtSecret []byte
}

func NewTokenService(jwtSecret string) *TokenService {
	return &TokenService{jwtSecret: []byte(jwtSecret)}
}

// GenerateAccessToken creates a signed JWT (HS256) with the user's ID and email.
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

// GenerateRefreshToken creates a cryptographically random opaque token.
// Returns the raw token (to send to the client) and its SHA-256 hash (to store in DB).
func (ts *TokenService) GenerateRefreshToken() (raw string, hash string, err error) {
	b := make([]byte, refreshTokenBytes)
	if _, err := rand.Read(b); err != nil {
		return "", "", fmt.Errorf("generate random bytes: %w", err)
	}
	raw = hex.EncodeToString(b)
	hash = HashToken(raw)
	return raw, hash, nil
}

// RefreshTokenExpiresAt returns the expiration time for a new refresh token.
func (ts *TokenService) RefreshTokenExpiresAt() time.Time {
	return time.Now().Add(refreshTokenExpiry)
}

// ValidateAccessToken parses and validates a JWT access token.
// Returns the user_id (from the "sub" claim).
func (ts *TokenService) ValidateAccessToken(tokenString string) (uuid.UUID, error) {
	token, err := jwt.Parse(tokenString, func(t *jwt.Token) (interface{}, error) {
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

// HashToken returns the hex-encoded SHA-256 hash of a token string.
func HashToken(token string) string {
	h := sha256.Sum256([]byte(token))
	return hex.EncodeToString(h[:])
}
```

- [ ] **Step 2: Verify build**

```bash
cd /Volumes/rusty-drive/projects/pocket-pilot/backend && go build ./...
```

Expected: Build succeeds.

- [ ] **Step 3: Commit**

```bash
git add backend/internal/auth/token.go
git commit -m "feat(auth): add JWT access token and opaque refresh token generation"
```

---

## Task 8: Backend — Auth Handler

**Files:**
- Create: `backend/internal/auth/handler.go`

- [ ] **Step 1: Create the auth handler**

Create `backend/internal/auth/handler.go`:

```go
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

	// 1. Verify the third-party OIDC token.
	claims, err := h.verifier.Verify(req.Provider, req.IdToken)
	if err != nil {
		return nil, status.Errorf(codes.Unauthenticated, "invalid id_token: %v", err)
	}

	// 2. Find or create user (account linking by email).
	user, err := h.repo.FindUserByEmail(ctx, claims.Email)
	if err != nil {
		return nil, status.Errorf(codes.Internal, "find user: %v", err)
	}

	if user != nil {
		// Link new identity to existing user (no-op if already linked).
		if err := h.repo.LinkIdentity(ctx, user.ID, req.Provider, claims.Sub); err != nil {
			return nil, status.Errorf(codes.Internal, "link identity: %v", err)
		}
	} else {
		// Create new user with identity.
		user, err = h.repo.CreateUserWithIdentity(ctx, claims.Email, req.Provider, claims.Sub)
		if err != nil {
			return nil, status.Errorf(codes.Internal, "create user: %v", err)
		}
	}

	// 3. Generate our own tokens.
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

	// 1. Find the refresh token record.
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

	// 2. Revoke the used token (rotation).
	if err := h.repo.RevokeToken(ctx, record.ID); err != nil {
		return nil, status.Errorf(codes.Internal, "revoke old token: %v", err)
	}

	// 3. Look up the user for the access token claims.
	user, err := h.repo.FindUserByID(ctx, record.UserID)
	if err != nil {
		return nil, status.Errorf(codes.Internal, "find user: %v", err)
	}
	if user == nil {
		return nil, status.Error(codes.Internal, "user not found for refresh token")
	}

	// 4. Generate new token pair.
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
```

- [ ] **Step 2: Verify build**

```bash
cd /Volumes/rusty-drive/projects/pocket-pilot/backend && go build ./...
```

Expected: Build succeeds.

- [ ] **Step 3: Commit**

```bash
git add backend/internal/auth/handler.go
git commit -m "feat(auth): add AuthService gRPC handler with OAuthLogin, RefreshToken, Logout, RevokeAllSessions"
```

---

## Task 9: Backend — Update Middleware and Server Wiring

**Files:**
- Modify: `backend/internal/middleware/auth.go`
- Modify: `backend/cmd/server/main.go`

- [ ] **Step 1: Replace the auth middleware**

Replace the entire content of `backend/internal/middleware/auth.go`:

```go
package middleware

import (
	"context"
	"strings"

	"github.com/google/uuid"
	"google.golang.org/grpc"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/metadata"
	"google.golang.org/grpc/status"

	"github.com/golang-jwt/jwt/v5"
)

type contextKey string

const ContextUserIDKey contextKey = "user_id"

// publicMethods lists gRPC full method names that do not require authentication.
var publicMethods = map[string]bool{
	"/pocket_pilot.v1.AuthService/OAuthLogin":    true,
	"/pocket_pilot.v1.AuthService/RefreshToken":  true,
	"/pocket_pilot.v1.AuthService/Logout":        true,
}

// NewUnaryAuthInterceptor returns a gRPC unary interceptor that validates
// JWT access tokens from the Authorization metadata header.
func NewUnaryAuthInterceptor(jwtSecret string) grpc.UnaryServerInterceptor {
	secret := []byte(jwtSecret)

	return func(ctx context.Context, req interface{}, info *grpc.UnaryServerInfo, handler grpc.UnaryHandler) (interface{}, error) {
		// Skip auth for public methods.
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

		tokenString := strings.TrimPrefix(authHeader[0], "Bearer ")
		if tokenString == authHeader[0] {
			return nil, status.Error(codes.Unauthenticated, "invalid authorization format")
		}

		// Parse and validate JWT.
		token, err := jwt.Parse(tokenString, func(t *jwt.Token) (interface{}, error) {
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

// UserIDFromCtx extracts the authenticated user ID from the context.
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
```

- [ ] **Step 2: Update `main.go` to wire auth handler and new middleware**

Replace the entire content of `backend/cmd/server/main.go`:

```go
package main

import (
	"context"
	"fmt"
	"log"
	"net"
	"os"
	"os/signal"
	"syscall"

	"google.golang.org/grpc"
	"google.golang.org/grpc/reflection"

	"github.com/AlanIsaacV/pocket-pilot/internal/account"
	"github.com/AlanIsaacV/pocket-pilot/internal/aiassistant"
	"github.com/AlanIsaacV/pocket-pilot/internal/auth"
	"github.com/AlanIsaacV/pocket-pilot/internal/budget"
	"github.com/AlanIsaacV/pocket-pilot/internal/category"
	"github.com/AlanIsaacV/pocket-pilot/internal/config"
	"github.com/AlanIsaacV/pocket-pilot/internal/database"
	pb "github.com/AlanIsaacV/pocket-pilot/internal/gen/proto/pocket_pilot/v1/pocket_pilot/v1"
	"github.com/AlanIsaacV/pocket-pilot/internal/goal"
	"github.com/AlanIsaacV/pocket-pilot/internal/jwks"
	"github.com/AlanIsaacV/pocket-pilot/internal/middleware"
	"github.com/AlanIsaacV/pocket-pilot/internal/tag"
	"github.com/AlanIsaacV/pocket-pilot/internal/transaction"
	"github.com/AlanIsaacV/pocket-pilot/internal/transactiontemplate"
	"github.com/AlanIsaacV/pocket-pilot/internal/userpreference"
	"github.com/AlanIsaacV/pocket-pilot/internal/yieldconfig"
)

func main() {
	cfg, err := config.Load()
	if err != nil {
		log.Fatalf("config: %v", err)
	}

	ctx := context.Background()

	pool, err := database.NewPool(ctx, cfg.DatabaseURL)
	if err != nil {
		log.Fatalf("database: %v", err)
	}
	defer pool.Close()
	log.Println("connected to PostgreSQL")

	// Wire up repositories and handlers
	accountHandler := account.NewHandler(account.NewRepository(pool))
	categoryHandler := category.NewHandler(category.NewRepository(pool))
	transactionHandler := transaction.NewHandler(transaction.NewRepository(pool))
	transactionTemplateHandler := transactiontemplate.NewHandler(transactiontemplate.NewRepository(pool))
	yieldConfigHandler := yieldconfig.NewHandler(yieldconfig.NewRepository(pool))
	goalHandler := goal.NewHandler(goal.NewRepository(pool))
	budgetHandler := budget.NewHandler(budget.NewRepository(pool))
	tagHandler := tag.NewHandler(tag.NewRepository(pool))
	userPreferenceHandler := userpreference.NewHandler(userpreference.NewRepository(pool))

	// AI Assistant
	geminiProvider := aiassistant.NewGeminiProvider(cfg.GeminiAPIKey)
	aiRepo := aiassistant.NewRepository(pool)
	aiRateLimiter := aiassistant.NewRateLimiter(aiRepo, cfg.AIDailyRequestLimit, cfg.AIMonthlyTokenLimit)
	aiHandler := aiassistant.NewHandler(geminiProvider, aiRateLimiter, aiRepo)

	// Auth
	keyStore := jwks.NewKeyStore()
	verifier := jwks.NewVerifier(keyStore, cfg.GoogleClientID, cfg.AppleClientID)
	tokenService := auth.NewTokenService(cfg.JWTSecret)
	authRepo := auth.NewRepository(pool)
	authHandler := auth.NewHandler(authRepo, verifier, tokenService)

	// gRPC server with JWT auth interceptor.
	srv := grpc.NewServer(
		grpc.UnaryInterceptor(middleware.NewUnaryAuthInterceptor(cfg.JWTSecret)),
	)
	pb.RegisterAccountServiceServer(srv, accountHandler)
	pb.RegisterCategoryServiceServer(srv, categoryHandler)
	pb.RegisterTransactionServiceServer(srv, transactionHandler)
	pb.RegisterTransactionTemplateServiceServer(srv, transactionTemplateHandler)
	pb.RegisterYieldConfigServiceServer(srv, yieldConfigHandler)
	pb.RegisterGoalServiceServer(srv, goalHandler)
	pb.RegisterBudgetServiceServer(srv, budgetHandler)
	pb.RegisterTagServiceServer(srv, tagHandler)
	pb.RegisterUserPreferenceServiceServer(srv, userPreferenceHandler)
	pb.RegisterAIAssistantServiceServer(srv, aiHandler)
	pb.RegisterAuthServiceServer(srv, authHandler)

	reflection.Register(srv)

	lis, err := net.Listen("tcp", fmt.Sprintf(":%s", cfg.GRPCPort))
	if err != nil {
		log.Fatalf("listen: %v", err)
	}

	// Graceful shutdown on CTRL+C or SIGTERM
	quit := make(chan os.Signal, 1)
	signal.Notify(quit, os.Interrupt, syscall.SIGTERM)
	go func() {
		<-quit
		log.Println("shutting down...")
		srv.GracefulStop()
	}()

	log.Printf("gRPC server listening on :%s", cfg.GRPCPort)
	if err := srv.Serve(lis); err != nil {
		log.Fatalf("serve: %v", err)
	}
}
```

- [ ] **Step 3: Update .env file (add JWT_SECRET)**

Add to `.env` (or wherever environment variables are set for local dev):

```
JWT_SECRET=your-dev-secret-change-in-production-min-32-chars!!
GOOGLE_CLIENT_ID=your-google-client-id.apps.googleusercontent.com
APPLE_CLIENT_ID=com.yourcompany.pocketpilot
```

- [ ] **Step 4: Verify build**

```bash
cd /Volumes/rusty-drive/projects/pocket-pilot/backend && go build ./...
```

Expected: Build succeeds.

- [ ] **Step 5: Commit**

```bash
git add backend/internal/middleware/auth.go backend/cmd/server/main.go
git commit -m "feat(auth): replace MVP token with JWT validation, wire AuthService in server"
```

---

## Task 10: Frontend — Add Dependencies

**Files:**
- Modify: `frontend/pubspec.yaml`

- [ ] **Step 1: Add auth dependencies to pubspec.yaml**

Add the following under the `dependencies:` section in `frontend/pubspec.yaml`, after the voice dependencies:

```yaml
  # --- Auth ---
  # google_sign_in: obtiene el OIDC id_token de Google.
  # sign_in_with_apple: obtiene el identity token de Apple.
  # flutter_secure_storage: almacenamiento cifrado para tokens.
  google_sign_in: ^6.2.2
  sign_in_with_apple: ^6.1.4
  flutter_secure_storage: ^9.2.4
```

- [ ] **Step 2: Install dependencies**

```bash
cd /Volumes/rusty-drive/projects/pocket-pilot/frontend && flutter pub get
```

Expected: Dependencies resolve successfully.

- [ ] **Step 3: Commit**

```bash
git add frontend/pubspec.yaml frontend/pubspec.lock
git commit -m "feat(auth): add google_sign_in, sign_in_with_apple, flutter_secure_storage dependencies"
```

---

## Task 11: Frontend — Token Store

**Files:**
- Create: `frontend/lib/src/core/auth/token_store.dart`

- [ ] **Step 1: Create the token store**

Create `frontend/lib/src/core/auth/token_store.dart`:

```dart
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Secure storage wrapper for auth tokens.
///
/// Stores access_token, refresh_token, and user_id in the platform's
/// secure keychain (iOS) or encrypted shared preferences (Android).
class TokenStore {
  static const _keyAccessToken = 'access_token';
  static const _keyRefreshToken = 'refresh_token';
  static const _keyUserId = 'user_id';

  final FlutterSecureStorage _storage;

  TokenStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  Future<void> save({
    required String accessToken,
    required String refreshToken,
    required String userId,
  }) async {
    await Future.wait([
      _storage.write(key: _keyAccessToken, value: accessToken),
      _storage.write(key: _keyRefreshToken, value: refreshToken),
      _storage.write(key: _keyUserId, value: userId),
    ]);
  }

  Future<String?> getAccessToken() => _storage.read(key: _keyAccessToken);

  Future<String?> getRefreshToken() => _storage.read(key: _keyRefreshToken);

  Future<String?> getUserId() => _storage.read(key: _keyUserId);

  Future<bool> hasTokens() async {
    final token = await _storage.read(key: _keyAccessToken);
    return token != null;
  }

  Future<void> clear() async {
    await Future.wait([
      _storage.delete(key: _keyAccessToken),
      _storage.delete(key: _keyRefreshToken),
      _storage.delete(key: _keyUserId),
    ]);
  }
}
```

- [ ] **Step 2: Verify compilation**

```bash
cd /Volumes/rusty-drive/projects/pocket-pilot/frontend && flutter analyze lib/src/core/auth/token_store.dart
```

Expected: No issues found.

- [ ] **Step 3: Commit**

```bash
git add frontend/lib/src/core/auth/token_store.dart
git commit -m "feat(auth): add TokenStore for secure token storage"
```

---

## Task 12: Frontend — Auth Service

**Files:**
- Create: `frontend/lib/src/core/auth/auth_service.dart`

- [ ] **Step 1: Create the auth service**

Create `frontend/lib/src/core/auth/auth_service.dart`:

```dart
import 'dart:convert';

import 'package:google_sign_in/google_sign_in.dart';
import 'package:grpc/grpc.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import 'package:pocket_pilot/src/core/auth/token_store.dart';
import 'package:pocket_pilot/src/core/grpc/grpc_client.dart';
import 'package:pocket_pilot/src/generated/pocket_pilot/v1/auth_service.pbgrpc.dart';

class AuthService {
  final TokenStore _tokenStore;
  late final AuthServiceClient _client;

  AuthService({required TokenStore tokenStore}) : _tokenStore = tokenStore {
    _client = AuthServiceClient(GrpcClient.channel);
  }

  /// Signs in with Google and returns the OIDC id_token.
  Future<String> loginWithGoogle() async {
    final googleSignIn = GoogleSignIn(scopes: ['email']);
    final account = await googleSignIn.signIn();
    if (account == null) {
      throw Exception('Google sign-in cancelled');
    }
    final authentication = await account.authentication;
    final idToken = authentication.idToken;
    if (idToken == null) {
      throw Exception('Google id_token is null');
    }
    return idToken;
  }

  /// Signs in with Apple and returns the identity token.
  Future<String> loginWithApple() async {
    final credential = await SignInWithApple.getAppleIDCredential(
      scopes: [AppleIDAuthorizationScopes.email],
    );
    final identityToken = credential.identityToken;
    if (identityToken == null) {
      throw Exception('Apple identity token is null');
    }
    return identityToken;
  }

  /// Sends the provider token to the backend, receives our own tokens, and stores them.
  Future<void> authenticate({
    required String provider,
    required String idToken,
  }) async {
    final response = await _client.oAuthLogin(
      OAuthLoginRequest()
        ..provider = provider
        ..idToken = idToken,
    );
    await _tokenStore.save(
      accessToken: response.accessToken,
      refreshToken: response.refreshToken,
      userId: response.userId,
    );
  }

  /// Refreshes the token pair using the stored refresh token.
  /// Returns true if successful, false if refresh failed (should force logout).
  Future<bool> refresh() async {
    final refreshToken = await _tokenStore.getRefreshToken();
    if (refreshToken == null) return false;

    try {
      final response = await _client.refreshToken(
        RefreshRequest()..refreshToken = refreshToken,
      );
      await _tokenStore.save(
        accessToken: response.accessToken,
        refreshToken: response.refreshToken,
        userId: response.userId,
      );
      return true;
    } on GrpcError {
      return false;
    }
  }

  /// Logs out by revoking the current refresh token on the server, then clearing local storage.
  Future<void> logout() async {
    final refreshToken = await _tokenStore.getRefreshToken();
    if (refreshToken != null) {
      try {
        await _client.logout(LogoutRequest()..refreshToken = refreshToken);
      } catch (_) {
        // Best-effort: if the server is unreachable, still clear local tokens.
      }
    }
    await _tokenStore.clear();
  }

  /// Revokes all sessions on the server (requires auth), then clears local storage.
  Future<void> revokeAllSessions() async {
    try {
      await _client.revokeAllSessions(Empty());
    } catch (_) {
      // Best-effort.
    }
    await _tokenStore.clear();
  }
}
```

Note: The `Empty()` import comes from `package:protobuf/protobuf.dart` or from the generated empty proto. Check the generated code for the correct import. It may need to be imported from `package:pocket_pilot/src/generated/google/protobuf/empty.pb.dart`.

- [ ] **Step 2: Fix imports if needed**

After creating the file, run:

```bash
cd /Volumes/rusty-drive/projects/pocket-pilot/frontend && flutter analyze lib/src/core/auth/auth_service.dart
```

Fix any import issues based on the analyzer output. The `Empty()` class may need:

```dart
import 'package:pocket_pilot/src/generated/google/protobuf/empty.pb.dart' as pb;
```

And use `pb.Empty()` for `revokeAllSessions`.

- [ ] **Step 3: Commit**

```bash
git add frontend/lib/src/core/auth/auth_service.dart
git commit -m "feat(auth): add AuthService with Google/Apple login, refresh, and logout"
```

---

## Task 13: Frontend — Auth Provider

**Files:**
- Create: `frontend/lib/src/core/auth/auth_provider.dart`

- [ ] **Step 1: Create the auth provider**

Create `frontend/lib/src/core/auth/auth_provider.dart`:

```dart
import 'package:flutter/foundation.dart';

import 'package:pocket_pilot/src/core/auth/auth_service.dart';
import 'package:pocket_pilot/src/core/auth/token_store.dart';

class AuthProvider extends ChangeNotifier {
  final AuthService _authService;
  final TokenStore _tokenStore;

  bool _isAuthenticated = false;
  bool get isAuthenticated => _isAuthenticated;

  AuthProvider({
    required AuthService authService,
    required TokenStore tokenStore,
  })  : _authService = authService,
        _tokenStore = tokenStore;

  /// Checks secure storage for existing tokens on app startup.
  Future<void> init() async {
    _isAuthenticated = await _tokenStore.hasTokens();
    notifyListeners();
  }

  /// Signs in with Google.
  Future<void> loginWithGoogle() async {
    final idToken = await _authService.loginWithGoogle();
    await _authService.authenticate(provider: 'google', idToken: idToken);
    _isAuthenticated = true;
    notifyListeners();
  }

  /// Signs in with Apple.
  Future<void> loginWithApple() async {
    final idToken = await _authService.loginWithApple();
    await _authService.authenticate(provider: 'apple', idToken: idToken);
    _isAuthenticated = true;
    notifyListeners();
  }

  /// Logs out the current session.
  Future<void> logout() async {
    await _authService.logout();
    _isAuthenticated = false;
    notifyListeners();
  }

  /// Revokes all sessions across all devices.
  Future<void> revokeAllSessions() async {
    await _authService.revokeAllSessions();
    _isAuthenticated = false;
    notifyListeners();
  }

  /// Called by the auth interceptor when token refresh fails.
  void forceLogout() {
    _tokenStore.clear();
    _isAuthenticated = false;
    notifyListeners();
  }
}
```

- [ ] **Step 2: Verify compilation**

```bash
cd /Volumes/rusty-drive/projects/pocket-pilot/frontend && flutter analyze lib/src/core/auth/auth_provider.dart
```

Expected: No issues found.

- [ ] **Step 3: Commit**

```bash
git add frontend/lib/src/core/auth/auth_provider.dart
git commit -m "feat(auth): add AuthProvider with login, logout, and session management"
```

---

## Task 14: Frontend — Auth Interceptor (Replace MVP)

**Files:**
- Modify: `frontend/lib/src/core/grpc/auth_interceptor.dart`

- [ ] **Step 1: Replace the auth interceptor**

Replace the entire content of `frontend/lib/src/core/grpc/auth_interceptor.dart`:

```dart
import 'dart:async';

import 'package:grpc/grpc.dart';

import 'package:pocket_pilot/src/core/auth/auth_provider.dart';
import 'package:pocket_pilot/src/core/auth/auth_service.dart';
import 'package:pocket_pilot/src/core/auth/token_store.dart';

/// gRPC interceptor that:
/// 1. Injects the JWT access token into every request's metadata.
/// 2. On UNAUTHENTICATED response, attempts to refresh the token and retries once.
/// 3. Serializes concurrent refresh attempts via a Completer-based lock.
class AuthInterceptor implements ClientInterceptor {
  final TokenStore _tokenStore;
  final AuthService _authService;
  final AuthProvider _authProvider;

  Completer<bool>? _refreshCompleter;

  AuthInterceptor({
    required TokenStore tokenStore,
    required AuthService authService,
    required AuthProvider authProvider,
  })  : _tokenStore = tokenStore,
        _authService = authService,
        _authProvider = authProvider;

  @override
  ResponseFuture<R> interceptUnary<Q, R>(
    ClientMethod<Q, R> method,
    Q request,
    CallOptions options,
    ClientUnaryInvoker<Q, R> invoker,
  ) {
    // Wrap in a custom ResponseFuture that handles retry.
    return ResponseFuture<R>(
      _interceptUnaryAsync(method, request, options, invoker),
    );
  }

  Future<R> _interceptUnaryAsync<Q, R>(
    ClientMethod<Q, R> method,
    Q request,
    CallOptions options,
    ClientUnaryInvoker<Q, R> invoker,
  ) async {
    // First attempt with current token.
    final opts = await _withAuthHeader(options);
    try {
      return await invoker(method, request, opts);
    } on GrpcError catch (e) {
      if (e.code != StatusCode.unauthenticated) rethrow;
    }

    // Token expired — try to refresh (serialized).
    final refreshed = await _serializedRefresh();
    if (!refreshed) {
      _authProvider.forceLogout();
      throw GrpcError.unauthenticated('Session expired. Please log in again.');
    }

    // Retry with new token.
    final retryOpts = await _withAuthHeader(options);
    return await invoker(method, request, retryOpts);
  }

  Future<CallOptions> _withAuthHeader(CallOptions options) async {
    final token = await _tokenStore.getAccessToken();
    if (token == null) return options;
    return options.mergedWith(
      CallOptions(metadata: {'authorization': 'Bearer $token'}),
    );
  }

  /// Ensures only one refresh is in-flight at a time.
  /// Concurrent callers wait for the same result.
  Future<bool> _serializedRefresh() async {
    if (_refreshCompleter != null) {
      return _refreshCompleter!.future;
    }

    _refreshCompleter = Completer<bool>();
    try {
      final result = await _authService.refresh();
      _refreshCompleter!.complete(result);
      return result;
    } catch (e) {
      _refreshCompleter!.complete(false);
      return false;
    } finally {
      _refreshCompleter = null;
    }
  }

  @override
  ResponseStream<R> interceptStreaming<Q, R>(
    ClientMethod<Q, R> method,
    Stream<Q> requests,
    CallOptions options,
    ClientStreamingInvoker<Q, R> invoker,
  ) {
    // Streaming calls: inject token but no retry logic.
    // Streaming is not used in this app currently.
    return invoker(method, requests, options);
  }
}
```

**Important note:** The `ResponseFuture` constructor in the `grpc` package may not accept a plain `Future`. If that's the case, the interceptor needs a different approach. Check the existing pattern — the current interceptor returns `invoker(...)` directly. The retry pattern requires wrapping. An alternative approach:

Instead of wrapping in `ResponseFuture`, use the simpler approach of catching errors at the call site. But the standard pattern in grpc-dart for interceptors with retry is to create a custom `ResponseFuture`. If the `grpc` package version (5.x) doesn't support constructing a `ResponseFuture` from a `Future`, use this alternative:

```dart
@override
ResponseFuture<R> interceptUnary<Q, R>(
  ClientMethod<Q, R> method,
  Q request,
  CallOptions options,
  ClientUnaryInvoker<Q, R> invoker,
) {
  // For the initial call, inject the token synchronously from cache if available.
  // The retry-on-UNAUTHENTICATED logic is handled at a higher level.
  final tokenFuture = _tokenStore.getAccessToken();

  // Since we can't easily wrap ResponseFuture with retry logic,
  // inject the token and return. The retry logic should live in a
  // wrapper around the gRPC client calls instead.
  //
  // For now, inject the token if available (read synchronously from the last cached value).
  return invoker(
    method,
    request,
    options.mergedWith(
      CallOptions(providers: [_metadataProvider]),
    ),
  );
}

Future<void> _metadataProvider(
  Map<String, String> metadata,
  String uri,
) async {
  final token = await _tokenStore.getAccessToken();
  if (token != null) {
    metadata['authorization'] = 'Bearer $token';
  }
}
```

The `CallOptions.providers` approach is the idiomatic grpc-dart way to inject metadata asynchronously. For the retry logic, implement it as a wrapper around `AuthServiceClient` calls. Since the interceptor approach for retry is complex in grpc-dart 5.x, place the retry-on-UNAUTHENTICATED logic in a try/catch wrapper within `AuthService` or at the ViewModel call site.

**Recommended final approach** — use `CallOptions.providers` for token injection and keep retry logic in a helper:

```dart
import 'dart:async';

import 'package:grpc/grpc.dart';

import 'package:pocket_pilot/src/core/auth/auth_provider.dart';
import 'package:pocket_pilot/src/core/auth/auth_service.dart';
import 'package:pocket_pilot/src/core/auth/token_store.dart';

class AuthInterceptor implements ClientInterceptor {
  final TokenStore _tokenStore;

  AuthInterceptor({required TokenStore tokenStore}) : _tokenStore = tokenStore;

  @override
  ResponseFuture<R> interceptUnary<Q, R>(
    ClientMethod<Q, R> method,
    Q request,
    CallOptions options,
    ClientUnaryInvoker<Q, R> invoker,
  ) {
    return invoker(
      method,
      request,
      options.mergedWith(CallOptions(providers: [_addAuthMetadata])),
    );
  }

  Future<void> _addAuthMetadata(
    Map<String, String> metadata,
    String uri,
  ) async {
    final token = await _tokenStore.getAccessToken();
    if (token != null) {
      metadata['authorization'] = 'Bearer $token';
    }
  }

  @override
  ResponseStream<R> interceptStreaming<Q, R>(
    ClientMethod<Q, R> method,
    Stream<Q> requests,
    CallOptions options,
    ClientStreamingInvoker<Q, R> invoker,
  ) {
    return invoker(
      method,
      requests,
      options.mergedWith(CallOptions(providers: [_addAuthMetadata])),
    );
  }
}
```

Then add a retry wrapper to handle UNAUTHENTICATED errors. Create a helper function that ViewModels and sync handlers can use:

Add to `frontend/lib/src/core/auth/auth_retry.dart`:

```dart
import 'dart:async';

import 'package:grpc/grpc.dart';

import 'package:pocket_pilot/src/core/auth/auth_provider.dart';
import 'package:pocket_pilot/src/core/auth/auth_service.dart';

/// Wraps a gRPC call with automatic token refresh on UNAUTHENTICATED error.
/// Serializes concurrent refresh attempts.
class AuthRetry {
  final AuthService _authService;
  final AuthProvider _authProvider;

  Completer<bool>? _refreshCompleter;

  AuthRetry({
    required AuthService authService,
    required AuthProvider authProvider,
  })  : _authService = authService,
        _authProvider = authProvider;

  /// Executes [call]. If it fails with UNAUTHENTICATED, refreshes the token
  /// and retries once. If refresh fails, forces logout.
  Future<T> call<T>(Future<T> Function() grpcCall) async {
    try {
      return await grpcCall();
    } on GrpcError catch (e) {
      if (e.code != StatusCode.unauthenticated) rethrow;
    }

    final refreshed = await _serializedRefresh();
    if (!refreshed) {
      _authProvider.forceLogout();
      throw GrpcError.unauthenticated('Session expired. Please log in again.');
    }

    return await grpcCall();
  }

  Future<bool> _serializedRefresh() async {
    if (_refreshCompleter != null) {
      return _refreshCompleter!.future;
    }

    _refreshCompleter = Completer<bool>();
    try {
      final result = await _authService.refresh();
      _refreshCompleter!.complete(result);
      return result;
    } catch (e) {
      _refreshCompleter!.complete(false);
      return false;
    } finally {
      _refreshCompleter = null;
    }
  }
}
```

- [ ] **Step 2: Verify compilation**

```bash
cd /Volumes/rusty-drive/projects/pocket-pilot/frontend && flutter analyze lib/src/core/grpc/auth_interceptor.dart lib/src/core/auth/auth_retry.dart
```

Expected: No issues found.

- [ ] **Step 3: Commit**

```bash
git add frontend/lib/src/core/grpc/auth_interceptor.dart frontend/lib/src/core/auth/auth_retry.dart
git commit -m "feat(auth): replace MVP token interceptor with JWT injection and refresh retry"
```

---

## Task 15: Frontend — Update GrpcClient to Accept Interceptor

**Files:**
- Modify: `frontend/lib/src/core/grpc/grpc_client.dart`

- [ ] **Step 1: Update GrpcClient to accept interceptors**

The current `GrpcClient` is a static singleton that creates a `ClientChannel`. The interceptor is currently passed directly when creating stubs in remote services. Check how existing remote services create their clients. For example, look at any `*_remote_service.dart`:

The existing remote services likely do something like:

```dart
final client = TagServiceClient(
  GrpcClient.channel,
  interceptors: [const AuthInterceptor()],
);
```

Since `AuthInterceptor` now requires `TokenStore` (no longer `const`), we need to provide it via DI. Update `GrpcClient` to hold a shared list of interceptors:

Replace the content of `frontend/lib/src/core/grpc/grpc_client.dart`:

```dart
import 'package:grpc/grpc.dart';
import 'package:pocket_pilot/src/core/constants/constants.dart';

class GrpcClient {
  GrpcClient._();

  static ClientChannel? _channel;
  static List<ClientInterceptor> _interceptors = [];

  /// Must be called once at app startup, before any gRPC client is created.
  static void init({List<ClientInterceptor> interceptors = const []}) {
    _interceptors = interceptors;
  }

  static ClientChannel get channel {
    _channel ??= ClientChannel(
      kGrpcHost,
      port: kGrpcPort,
      options: const ChannelOptions(
        credentials: ChannelCredentials.insecure(),
      ),
    );
    return _channel!;
  }

  /// Returns the shared list of interceptors (e.g., AuthInterceptor).
  static List<ClientInterceptor> get interceptors => _interceptors;

  static Future<void> dispose() async {
    await _channel?.shutdown();
    _channel = null;
  }
}
```

Then update all existing remote services that create gRPC clients to use `GrpcClient.interceptors` instead of `[const AuthInterceptor()]`. This is a search-and-replace across all `*_remote_service.dart` files:

Find:
```dart
interceptors: [const AuthInterceptor()],
```
Replace with:
```dart
interceptors: GrpcClient.interceptors,
```

And remove the import of `auth_interceptor.dart` from those files, replacing it with:
```dart
import 'package:pocket_pilot/src/core/grpc/grpc_client.dart';
```

(Only if `GrpcClient` is not already imported.)

- [ ] **Step 2: Update all remote services**

Run a search to find all files that reference `AuthInterceptor`:

```bash
cd /Volumes/rusty-drive/projects/pocket-pilot/frontend && grep -rl "AuthInterceptor" lib/
```

Update each file found.

- [ ] **Step 3: Verify compilation**

```bash
cd /Volumes/rusty-drive/projects/pocket-pilot/frontend && flutter analyze
```

Expected: No issues found.

- [ ] **Step 4: Commit**

```bash
git add frontend/lib/src/core/grpc/grpc_client.dart
git add frontend/lib/src/features/
git commit -m "refactor(grpc): centralize interceptors in GrpcClient, remove hardcoded AuthInterceptor from remote services"
```

---

## Task 16: Frontend — Login Screen

**Files:**
- Create: `frontend/lib/src/ui/screens/login/login_screen.dart`

- [ ] **Step 1: Create the login screen**

Create `frontend/lib/src/ui/screens/login/login_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:pocket_pilot/src/core/auth/auth_provider.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _loading = false;
  String? _error;

  Future<void> _login(Future<void> Function() loginFn) async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await loginFn();
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthProvider>();
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Pocket Pilot',
                style: theme.textTheme.headlineLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 48),
              if (_error != null) ...[
                Text(
                  _error!,
                  style: TextStyle(color: theme.colorScheme.error),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
              ],
              FilledButton.icon(
                onPressed: _loading ? null : () => _login(auth.loginWithGoogle),
                icon: const Icon(Icons.g_mobiledata),
                label: const Text('Continue with Google'),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _loading ? null : () => _login(auth.loginWithApple),
                icon: const Icon(Icons.apple),
                label: const Text('Continue with Apple'),
              ),
              if (_loading) ...[
                const SizedBox(height: 24),
                const Center(child: CircularProgressIndicator()),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Verify compilation**

```bash
cd /Volumes/rusty-drive/projects/pocket-pilot/frontend && flutter analyze lib/src/ui/screens/login/login_screen.dart
```

Expected: No issues found.

- [ ] **Step 3: Commit**

```bash
git add frontend/lib/src/ui/screens/login/login_screen.dart
git commit -m "feat(auth): add login screen with Google and Apple sign-in buttons"
```

---

## Task 17: Frontend — Update Router with Auth Guard

**Files:**
- Modify: `frontend/lib/src/ui/router.dart`
- Modify: `frontend/lib/src/ui/app.dart`

- [ ] **Step 1: Update router to accept AuthProvider and add login route**

Edit `frontend/lib/src/ui/router.dart`:

1. Add import:
```dart
import 'package:pocket_pilot/src/core/auth/auth_provider.dart';
import 'package:pocket_pilot/src/ui/screens/login/login_screen.dart';
```

2. Change the `buildRouter()` signature to accept `AuthProvider`:
```dart
GoRouter buildRouter(AuthProvider authProvider) {
```

3. Add `refreshListenable` and `redirect` to the `GoRouter` constructor:
```dart
return GoRouter(
  initialLocation: '/dashboard',
  refreshListenable: authProvider,
  redirect: (context, state) {
    final isLoggedIn = authProvider.isAuthenticated;
    final isOnLogin = state.matchedLocation == '/login';

    if (!isLoggedIn && !isOnLogin) return '/login';
    if (isLoggedIn && isOnLogin) return '/dashboard';
    return null;
  },
  routes: [
    GoRoute(
      path: '/login',
      builder: (context, state) => const LoginScreen(),
    ),
    // ... rest of existing routes unchanged ...
  ],
);
```

- [ ] **Step 2: Update `app.dart` to pass AuthProvider to the router**

In `frontend/lib/src/ui/app.dart`, the `PocketPilotApp` already receives `router` as a parameter. The router is built in `main.dart`, so no change needed in `app.dart` — the change is in `main.dart` (next task).

- [ ] **Step 3: Verify compilation**

```bash
cd /Volumes/rusty-drive/projects/pocket-pilot/frontend && flutter analyze lib/src/ui/router.dart
```

Expected: No issues found.

- [ ] **Step 4: Commit**

```bash
git add frontend/lib/src/ui/router.dart
git commit -m "feat(auth): add login route and auth redirect guard to router"
```

---

## Task 18: Frontend — Update main.dart (Wire Everything)

**Files:**
- Modify: `frontend/lib/main.dart`

- [ ] **Step 1: Wire auth into main.dart**

Edit `frontend/lib/main.dart`:

1. Add imports at the top (after existing imports):
```dart
import 'package:pocket_pilot/src/core/auth/auth_provider.dart';
import 'package:pocket_pilot/src/core/auth/auth_retry.dart';
import 'package:pocket_pilot/src/core/auth/auth_service.dart';
import 'package:pocket_pilot/src/core/auth/token_store.dart';
import 'package:pocket_pilot/src/core/grpc/grpc_client.dart';
```

2. At the beginning of the `main()` function, after `WidgetsFlutterBinding.ensureInitialized()`, add auth initialization:

```dart
  // Auth setup — must happen before any gRPC client is created.
  final tokenStore = TokenStore();
  final authService = AuthService(tokenStore: tokenStore);
  final authProvider = AuthProvider(
    authService: authService,
    tokenStore: tokenStore,
  );
  await authProvider.init();

  final authInterceptor = AuthInterceptor(tokenStore: tokenStore);
  GrpcClient.init(interceptors: [authInterceptor]);
```

Also add the import for `AuthInterceptor`:
```dart
import 'package:pocket_pilot/src/core/grpc/auth_interceptor.dart';
```

3. Remove the `kMvpUserId` reference. Find the `CategorySeeder` instantiation and replace `userId: kMvpUserId` with the userId from auth:

```dart
  // Category seeder needs a userId. If not authenticated, skip seeding
  // (it will run after first login via sync).
  final userId = await tokenStore.getUserId();
```

Then update the seeder:
```dart
  if (userId != null) {
    final categorySeeder = CategorySeeder(
      local: CategoryLocalStore(db: dbHelper),
      db: dbHelper,
      outbox: syncOutbox,
      userId: userId,
    );
    // ... pre-seed pull and seedIfNeeded ...
  }
```

4. Remove the import of `auth_interceptor.dart` from the old location if it's imported for `kMvpUserId`. The `kMvpUserId` constant should no longer be referenced anywhere.

5. Update the `buildRouter()` call to pass `authProvider`:
```dart
child: PocketPilotApp(router: buildRouter(authProvider)),
```

6. Add `AuthProvider` to the `MultiProvider`:
```dart
ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
```

- [ ] **Step 2: Remove kMvpUserId references**

Search for any remaining `kMvpUserId` references:

```bash
cd /Volumes/rusty-drive/projects/pocket-pilot/frontend && grep -r "kMvpUserId" lib/
```

Remove or replace all references found.

- [ ] **Step 3: Verify full app compilation**

```bash
cd /Volumes/rusty-drive/projects/pocket-pilot/frontend && flutter analyze
```

Expected: No issues found.

- [ ] **Step 4: Commit**

```bash
git add frontend/lib/main.dart
git add frontend/lib/src/
git commit -m "feat(auth): wire auth provider, token store, and interceptor into app bootstrap"
```

---

## Task 19: End-to-End Verification

- [ ] **Step 1: Verify backend builds and starts**

```bash
cd /Volumes/rusty-drive/projects/pocket-pilot && make migrate
cd backend && JWT_SECRET=dev-secret-32-chars-minimum-here GOOGLE_CLIENT_ID=test APPLE_CLIENT_ID=test DATABASE_URL=postgres://pocket_pilot:pocket_pilot@localhost:5432/pocket_pilot?sslmode=disable GEMINI_API_KEY=test go run ./cmd/server
```

Expected: Server starts, prints "gRPC server listening on :50051".

- [ ] **Step 2: Verify AuthService is registered**

In a separate terminal:

```bash
grpcurl -plaintext localhost:50051 list
```

Expected: `pocket_pilot.v1.AuthService` appears in the list alongside existing services.

```bash
grpcurl -plaintext localhost:50051 list pocket_pilot.v1.AuthService
```

Expected: Shows OAuthLogin, RefreshToken, Logout, RevokeAllSessions.

- [ ] **Step 3: Verify public routes don't require auth**

```bash
grpcurl -plaintext -d '{"provider":"google","id_token":"fake"}' localhost:50051 pocket_pilot.v1.AuthService/OAuthLogin
```

Expected: Error about invalid token (not "authorization token missing") — confirms the route is public.

- [ ] **Step 4: Verify protected routes require auth**

```bash
grpcurl -plaintext localhost:50051 pocket_pilot.v1.AuthService/RevokeAllSessions
```

Expected: Error "authorization token missing" — confirms the route requires auth.

- [ ] **Step 5: Verify Flutter compiles**

```bash
cd /Volumes/rusty-drive/projects/pocket-pilot/frontend && flutter analyze
```

Expected: No issues.

- [ ] **Step 6: Commit any remaining fixes**

```bash
git add -A
git commit -m "feat(auth): complete custom auth implementation with social login"
```
