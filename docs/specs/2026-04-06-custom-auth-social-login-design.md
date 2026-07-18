# Custom Auth con Social Login (Google & Apple)

## Resumen

Sistema de autenticación propio usando login social (Google/Apple) como puerta de entrada. El cliente Flutter obtiene el OIDC `id_token` del proveedor nativo y lo envía al backend Go vía gRPC. El backend valida criptográficamente el token usando JWKS manual puro (sin dependencias externas para JWKS), y emite access tokens (JWT HS256, 15 min) y refresh tokens (opacos, 30 días) propios.

## Decisiones de diseño

| Decisión | Elección | Razón |
|---|---|---|
| Account linking | Sí — por email | Un usuario con mismo email en Google y Apple comparte el mismo `user_id` |
| Logout | Individual + Revoke All | Cubrir ambos escenarios de cierre de sesión |
| Sync de entidad User | No | Auth es infraestructura core; datos de perfil van en claims del JWT |
| JWKS | Manual puro | Zero dependencias externas; control total del cache y parsing |
| Provider CHECK constraint | No | Flexibilidad para agregar más proveedores en el futuro |
| Migración | En `001_initial_schema.sql` | No estamos en producción, una sola migración |

### Desviaciones de convenciones existentes

Las tablas de auth se desvían del patrón estándar del proyecto (`user_id` + `deleted_at` + soft delete en todas las tablas) porque:
- `users` **es** la tabla de identidad — no tiene `user_id` ni `deleted_at`.
- `user_identities` y `refresh_tokens` referencian `users(id)` via `user_id` pero no usan soft delete (`refresh_tokens` usa `is_revoked`).

### Limitación conocida: Apple Private Relay

Cuando un usuario usa Apple Private Relay, el email devuelto (ej: `abc123@privaterelay.appleid.com`) será diferente al email real de Google. En ese caso, el account linking por email **no funcionará** y se crearán dos usuarios separados. Esto se acepta como limitación de MVP — un flujo de merge manual puede agregarse después.

---

## 1. Esquema de Base de Datos

Agregado a `backend/migrations/001_initial_schema.sql`:

### Tabla `users`

```sql
CREATE TABLE users (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email       TEXT NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
```

- Sin `UNIQUE(email)` — el email puede cambiar (Apple relay) y no es la identidad primaria.
- Sin `deleted_at` — no hay soft delete para usuarios.
- Race condition en creación concurrente con mismo email: se mitiga usando `SELECT ... FOR UPDATE` o `SERIALIZABLE` en la transacción de `CreateUserWithIdentity`.

### Tabla `user_identities`

```sql
CREATE TABLE user_identities (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id       UUID NOT NULL REFERENCES users(id),
    provider      TEXT NOT NULL,
    provider_id   TEXT NOT NULL,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(provider, provider_id)
);
```

- Cada fila = un proveedor vinculado a un usuario.
- Account linking: al hacer login, si el email ya existe en `users`, se vincula la nueva identidad al mismo `user_id`.

### Tabla `refresh_tokens`

```sql
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
```

- Hash SHA-256 del refresh token opaco.
- 30 días de expiración.
- `is_revoked` para logout; bulk revoke por `user_id` para revoke-all.

---

## 2. Contratos gRPC

Nuevo archivo: `proto/pocket_pilot/v1/auth_service.proto`

```protobuf
syntax = "proto3";
package pocket_pilot.v1;

option go_package = "github.com/AlanIsaacV/pocket-pilot/backend/internal/gen/proto/pocket_pilot/v1;pocketpilotv1";

import "google/protobuf/empty.proto";

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

- Mensajes no representan entidades DB → no aplica regla de índices 1,2,3.
- `Logout` y `RefreshToken` no requieren auth — el refresh token es prueba de posesión.
- `RevokeAllSessions` es ruta protegida — `user_id` se extrae del access token via interceptor.

---

## 3. Backend Go

### Estructura de paquetes

```
backend/internal/
  auth/
    handler.go       # AuthServiceServer: OAuthLogin, RefreshToken, Logout, RevokeAllSessions
    repository.go    # DB queries: users, user_identities, refresh_tokens
    model.go         # Structs: User, UserIdentity, RefreshTokenRecord
    token.go         # Genera JWT (HS256) y refresh tokens opacos
  jwks/
    jwks.go          # Fetch JWKS de Google/Apple, parseo RSA, cache en memoria con TTL
    verify.go        # Valida id_token: firma RSA, exp, aud → retorna claims (email, sub)
```

Nota: `jwks/` es un paquete separado (no un feature domain) porque es infraestructura de seguridad reutilizable, no una entidad de negocio.

### JWKS (`internal/jwks/`)

**`jwks.go`** — Cache y fetch:
- Mapa en memoria: `provider → {keys map[kid]*rsa.PublicKey, fetchedAt time.Time}`
- TTL: 1 hora. Si expirado al momento de verificar, re-fetch.
- URLs:
  - Google: `https://www.googleapis.com/oauth2/v3/certs`
  - Apple: `https://appleid.apple.com/auth/keys`
- Parseo: Descargar JSON → extraer `n`, `e`, `kid` de cada key → construir `*rsa.PublicKey`

**`verify.go`** — Validación del id_token:
1. Decodificar header del JWT (sin verificar) → extraer `kid`
2. Obtener la clave RSA correspondiente al `kid` del cache (re-fetch si TTL expirado)
3. Verificar firma RSA (RS256)
4. Validar claims: `exp` no expirado, `aud` coincide con el Client ID del provider
5. Retornar `{email, sub}` extraídos de los claims

### Auth Handler (`internal/auth/handler.go`)

**`OAuthLogin(ctx, req)`:**
1. `jwks.Verify(req.Provider, req.IdToken)` → `{email, sub}`
2. `repo.FindUserByEmail(email)` → busca usuario existente
3. Si existe → `repo.LinkIdentity(userID, provider, sub)` (ON CONFLICT DO NOTHING)
4. Si no existe → `repo.CreateUserWithIdentity(email, provider, sub)` (INSERT user + identity en transacción)
5. `token.GenerateAccessToken(userID, email)` → JWT HS256, exp 15 min, claims: `sub=userID`, `email=email`
6. `token.GenerateRefreshToken()` → 32 bytes crypto/rand, hex encoded
7. `repo.SaveRefreshToken(userID, sha256(refreshToken), expiresAt=now+30d)`
8. Retorna `AuthResponse{accessToken, refreshToken, userID}`

**`RefreshToken(ctx, req)`:**
1. `hash = sha256(req.RefreshToken)`
2. `repo.FindRefreshToken(hash)` → verifica `!is_revoked && expires_at > now`
3. `repo.RevokeToken(tokenID)` — rotation: el token usado se revoca
4. Genera nuevo par access + refresh
5. `repo.SaveRefreshToken(userID, newHash, newExpiresAt)`
6. Retorna `AuthResponse`

**`Logout(ctx, req)`:**
1. `hash = sha256(req.RefreshToken)`
2. `repo.RevokeToken(hash)`

**`RevokeAllSessions(ctx, req)`:**
1. `userID` extraído del contexto (ruta protegida)
2. `repo.RevokeAllTokens(userID)` → `UPDATE refresh_tokens SET is_revoked = TRUE WHERE user_id = $1 AND is_revoked = FALSE`

### Token Generation (`internal/auth/token.go`)

**Access Token (JWT):**
- Algoritmo: HS256
- Secret: `JWT_SECRET` (env var)
- Claims: `sub` (user_id), `email`, `iat`, `exp` (15 min)
- Librería: `github.com/golang-jwt/jwt/v5`

**Refresh Token:**
- 32 bytes de `crypto/rand`, hex encoded (64 chars)
- Se almacena `sha256(token)` en DB, se envía el token raw al cliente

### Config nuevas

Env vars agregadas a `config/config.go`:
- `GOOGLE_CLIENT_ID`
- `APPLE_CLIENT_ID`
- `JWT_SECRET`

---

## 4. Modificaciones al backend existente

### `middleware/auth.go`

Reemplazar la validación hardcoded de `"MVP-TOKEN-123"`:
- Parsear `Bearer {jwt}` del metadata `authorization`
- Validar JWT con `JWT_SECRET` (HS256), verificar `exp`
- Extraer `user_id` del claim `sub`, inyectar en context (mismo mecanismo actual)
- Rutas excluidas: `/pocket_pilot.v1.AuthService/OAuthLogin`, `/pocket_pilot.v1.AuthService/RefreshToken`, `/pocket_pilot.v1.AuthService/Logout`

### `cmd/server/main.go`

- Instanciar `auth.Repository`, `auth.Handler`
- Registrar `AuthServiceServer` en el gRPC server
- Pasar `JWTSecret` al middleware

---

## 5. Frontend Flutter

### Estructura

```
frontend/lib/src/
  core/
    auth/
      auth_provider.dart     # ChangeNotifier: isAuthenticated, login(), logout(), revokeAll()
      auth_service.dart      # Llama SDKs nativos + gRPC AuthService
      token_store.dart       # flutter_secure_storage wrapper: access_token, refresh_token, user_id
    grpc/
      auth_interceptor.dart  # (modificado) Inyecta JWT, retry en UNAUTHENTICATED
```

### `token_store.dart`

Wrapper sobre `flutter_secure_storage`:
- `save(accessToken, refreshToken, userId)`
- `getAccessToken()`, `getRefreshToken()`, `getUserId()`
- `clear()` — borra todo

### `auth_service.dart`

**`loginWithGoogle()`:**
1. `GoogleSignIn().signIn()` → `authentication.idToken`
2. Retorna el `idToken`

**`loginWithApple()`:**
1. `SignInWithApple.getAppleIDCredential(scopes: [email])` → `identityToken`
2. Retorna el `identityToken` (decode utf8 del credential.identityToken bytes)

**`authenticate(provider, idToken)`:**
1. gRPC `AuthService.OAuthLogin(provider, idToken)` → `AuthResponse`
2. `TokenStore.save(response.accessToken, response.refreshToken, response.userId)`

**`refresh()`:**
1. `TokenStore.getRefreshToken()`
2. gRPC `AuthService.RefreshToken(refreshToken)` → `AuthResponse`
3. `TokenStore.save(newAccessToken, newRefreshToken, userId)`

**`logout()`:**
1. `TokenStore.getRefreshToken()`
2. gRPC `AuthService.Logout(refreshToken)`
3. `TokenStore.clear()`

**`revokeAllSessions()`:**
1. gRPC `AuthService.RevokeAllSessions()`
2. `TokenStore.clear()`

### `auth_provider.dart`

```dart
class AuthProvider extends ChangeNotifier {
  bool _isAuthenticated = false;
  bool get isAuthenticated => _isAuthenticated;

  Future<void> init()       // Lee TokenStore → setea _isAuthenticated
  Future<void> login(...)   // Llama AuthService → notifyListeners()
  Future<void> logout()     // Llama AuthService → notifyListeners()
  Future<void> revokeAll()  // Llama AuthService → notifyListeners()
  void forceLogout()        // Llamado por el interceptor cuando refresh falla → notifyListeners()
}
```

### `auth_interceptor.dart` (modificación)

Reemplazar token MVP hardcoded:
1. Leer `accessToken` de `TokenStore`
2. Si no hay token → dejar pasar sin header (rutas públicas)
3. Inyectar `Bearer {accessToken}` en metadata
4. Si respuesta es `UNAUTHENTICATED`:
   - Serializar refresh attempts con un `Completer` (lock): si ya hay un refresh en vuelo, los demás callers esperan el mismo resultado en vez de disparar refreshes concurrentes
   - Llamar `AuthService.refresh()`
   - Si éxito → reintentar request original con nuevo token
   - Si falla → `AuthProvider.forceLogout()`
5. Máximo 1 reintento por request

### `main.dart`

- Agregar `TokenStore`, `AuthService`, `AuthProvider` al `MultiProvider` global
- `AuthProvider.init()` en startup (restaurar sesión)

### Routing

- Login screen como ruta
- Redirect guard en `go_router`: si `!AuthProvider.isAuthenticated` → login
- `AuthProvider` como `refreshListenable` del router

---

## 6. Dependencias nuevas

### Backend (Go)
- `github.com/golang-jwt/jwt/v5` — Generación y validación de JWT

### Frontend (Flutter)
- `google_sign_in` — SDK nativo de Google Sign-In
- `sign_in_with_apple` — SDK nativo de Apple Sign-In
- `flutter_secure_storage` — Almacenamiento seguro de tokens

### FK de tablas existentes

Las tablas existentes (accounts, categories, etc.) tienen `user_id UUID NOT NULL` pero sin FK a `users` porque la tabla no existía. Como estamos pre-producción y modificamos `001_initial_schema.sql`, agregamos `REFERENCES users(id)` a todas las tablas existentes.

---

## 7. Lo que NO cambia

- Sistema de sync completo (outbox, delta pull, handlers, SyncService)
- Repositorios, handlers, ViewModels de entidades existentes
- SQLite local (no se agrega tabla users)
- `grpc_client.dart` (ClientChannel singleton se reutiliza)
