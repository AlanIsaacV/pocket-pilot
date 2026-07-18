# Authentication Architecture

Custom auth system using social login (Google/Apple) as the entry point. No Firebase or BaaS.

## Flow Overview

```
Flutter (native SDK) → id_token → gRPC OAuthLogin → Backend validates JWKS → Issues own JWT + Refresh Token
```

1. Flutter obtains OIDC `id_token` from Google (`google_sign_in`) or Apple (`sign_in_with_apple`).
2. Sends `{provider, id_token}` to backend via `AuthService.OAuthLogin`.
3. Backend validates the token cryptographically (RSA signature via manual JWKS fetch from Google/Apple endpoints).
4. Backend creates/links the user (account linking by email), issues:
   - **Access Token**: JWT signed with HS256, 15 min expiry. Claims: `sub` (user_id), `email`, `iat`, `exp`.
   - **Refresh Token**: 32 bytes `crypto/rand`, hex encoded. Stored as SHA-256 hash in DB. 30 days expiry.
5. Flutter stores both tokens in `flutter_secure_storage`.

## Backend Packages

- `internal/auth/` — Domain package (handler, repository, model, token generation).
- `internal/jwks/` — Infrastructure package (JWKS fetch, RSA key cache with 1h TTL, token signature verification).

### Database Tables

- `users` — Core identity. No `user_id` column (it IS the user table). No `deleted_at`.
- `user_identities` — Links providers to users. `UNIQUE(provider, provider_id)`. Account linking: if email matches an existing user, the new identity is linked to that user.
- `refresh_tokens` — Stores hashed tokens with expiry and revocation flag. Indexed on `token_hash` (unique) and `user_id`.

These tables deviate from the standard project convention (`user_id` + `deleted_at` + soft delete) because they ARE the auth infrastructure.

### Auth Middleware (`middleware/auth.go`)

- `NewUnaryAuthInterceptor(jwtSecret)` — Returns a `grpc.UnaryServerInterceptor` that validates JWT access tokens.
- Public routes (no auth required): `OAuthLogin`, `RefreshToken`, `Logout`.
- Protected routes extract `user_id` from JWT `sub` claim into context (same mechanism as before).

### Config (env vars)

- `JWT_SECRET` (required) — HS256 signing key for access tokens.
- `GOOGLE_CLIENT_ID` (optional) — Web Application Client ID, used to validate `aud` claim.
- `APPLE_CLIENT_ID` (optional) — Services ID, used to validate `aud` claim.

## Frontend Structure

Auth lives in `lib/src/core/auth/` (infrastructure, not a syncable feature):

- `token_store.dart` — `flutter_secure_storage` wrapper. Stores `access_token`, `refresh_token`, `user_id`. Has `getEmail()` that decodes JWT payload to extract email claim.
- `auth_service.dart` — Calls native SDKs + gRPC `AuthService`. Methods: `loginWithGoogle()`, `loginWithApple()`, `authenticate()`, `refresh()`, `logout()`, `revokeAllSessions()`. Its internal `AuthServiceClient` is built **without** interceptors, so the `/RefreshToken` RPC bypasses `AuthInterceptor` (prevents recursive refresh loops).
- `auth_provider.dart` — `ChangeNotifier` with `isAuthenticated` state. Used as `refreshListenable` in `go_router` for redirect guard. Exposes `forceLogout()` used by `AuthInterceptor` when the refresh token is invalid/revoked.
- `auth_retry.dart` — **Deprecated / dead code.** Was designed as a per-call wrapper with response-side retry on `UNAUTHENTICATED`, but was never wired into any repository. Its logic (serialized refresh via `Completer`, `forceLogout` fallback) now lives inside `AuthInterceptor`. Kept only as reference; safe to delete.

### gRPC Interceptor (`core/grpc/auth_interceptor.dart`)

Attaches the current access token to every outgoing request **and proactively refreshes it before sending** when it is expired or within 30 s of expiring (covers small client/server clock skew and network latency).

Why proactive (pre-send) instead of reactive (retry on `UNAUTHENTICATED`): `gRPC-Dart`'s `ClientInterceptor.interceptUnary` must return a `ResponseFuture<R>` synchronously, and `ResponseFuture` can only be constructed from an internal `ClientCall`. Response-side retry therefore requires either wrapping every call site (the old `AuthRetry` approach) or re-issuing the invocation manually. Refreshing inside `CallOptions.providers` achieves the same guarantee automatically for every RPC, avoids a wasted round-trip, and keeps the interceptor bidirectionless.

Key properties:
- Decodes `exp` from the JWT payload (`base64Url` decode of the middle segment). If `exp` can't be parsed, the request is sent anyway and the server decides — defensive fallback.
- Serializes concurrent refreshes with a single `Completer<bool>`: during heavy sync, only one `/RefreshToken` RPC is issued; all other in-flight calls await the same completer.
- On refresh failure (refresh token expired, revoked, or network error), calls `AuthProvider.forceLogout()` and throws `GrpcError.unauthenticated('Session expired. Please log in again.')`.
- Wired in `main.dart` as `AuthInterceptor(tokenStore, authService, authProvider)` and passed to `GrpcClient.init(interceptors: [...])`.

### GrpcClient (`core/grpc/grpc_client.dart`)

Now has `init(interceptors: [...])` and a static `interceptors` getter. All remote services use `GrpcClient.interceptors` instead of instantiating their own.

### DB Wipe on User Change

On login, `AuthProvider._clearDbIfUserChanged()` compares the new `userId` with `last_user_id` in SQLite `app_metadata`. If different, calls `DatabaseHelper.deleteAndReset()` to wipe and recreate the DB. Sync repopulates data for the new user.

### Platform-Specific Login

- **iOS**: Google + Apple sign-in buttons.
- **Android**: Google only. Apple Sign-In on Android requires a web OAuth redirect server (deferred).

### Google Sign-In: `serverClientId`

`GoogleSignIn` requires a `serverClientId` (the **Web Application** Client ID, not the Android Client ID) to return an `id_token`. Passed via `--dart-define=GOOGLE_SERVER_CLIENT_ID=xxx.apps.googleusercontent.com`. The Android Client ID is validated automatically by Google via SHA-1 fingerprint — it's never passed in code.

## Known Limitations

- **Apple Private Relay**: If a user uses Apple's private relay email, account linking by email won't work with their Google account (different emails). Accepted as MVP limitation.
- **No user profile sync**: User data (email, name) is not synced to SQLite. Profile info is extracted from JWT claims client-side.

## Proto Contract

`proto/pocket_pilot/v1/auth_service.proto` — Messages do NOT represent DB entities, so the field index rule (1=created_at, 2=updated_at, 3=deleted_at) does not apply.

```
service AuthService {
  rpc OAuthLogin(OAuthLoginRequest) returns (AuthResponse);
  rpc RefreshToken(RefreshRequest) returns (AuthResponse);
  rpc Logout(LogoutRequest) returns (google.protobuf.Empty);
  rpc RevokeAllSessions(google.protobuf.Empty) returns (google.protobuf.Empty);
}
```

- `Logout`: Revokes a single refresh token. No auth required (token itself is proof of possession).
- `RevokeAllSessions`: Revokes all refresh tokens for the user. Requires auth (user_id from JWT).
- Refresh token rotation: every use of `RefreshToken` revokes the old token and issues a new pair.
